#!/usr/bin/env bash
# Stream (or record) the agent exhibition from a virtual display.
#   YOUTUBE_STREAM_KEY=... youtube-live/run.sh            go live until Ctrl-C
#   youtube-live/run.sh --record=90                        rehearse: record 90 s to youtube-live/recordings/
# Options: --record[=SECONDS] --cups=N (0 = forever) --encoder=obs|ffmpeg
# The stream key is read from the environment only, written to a private temp file for OBS, and never printed.
set -euo pipefail
set +x
cd "$(dirname "$0")/.."

mode=stream; record_s=0; cups=0; encoder=${LIVE_ENCODER:-obs}
for arg in "$@"; do
  case "$arg" in
    --record) mode=record;;
    --record=*) mode=record; record_s=${arg#*=};;
    --cups=*) cups=${arg#*=};;
    --encoder=*) encoder=${arg#*=};;
    *) echo "unknown option: $arg" >&2; exit 2;;
  esac
done
[ "$encoder" = obs ] || [ "$encoder" = ffmpeg ] || { echo "--encoder must be obs or ffmpeg" >&2; exit 2; }
if [ "$mode" = stream ] && [ -z "${YOUTUBE_STREAM_KEY:-}" ]; then echo "YOUTUBE_STREAM_KEY is not set (use --record to rehearse)" >&2; exit 2; fi
[ -d dist ] || { echo "dist/ missing: run youtube-live/setup.sh" >&2; exit 2; }

display=${LIVE_DISPLAY:-:99}; obs_display=:$(( ${display#:} + 1 )); port=${LIVE_PORT:-5178}; width=1920; height=1080; fps=30
ingest=${YOUTUBE_INGEST:-rtmps://a.rtmps.youtube.com:443/live2}
xvfb=${XVFB_BIN:-$(command -v Xvfb || echo youtube-live/.local/xvfb/usr/bin/Xvfb)}
out=youtube-live/recordings; mkdir -p "$out"
work=$(mktemp -d); chmod 700 "$work"
pids=()

cleanup() {
  trap - EXIT INT TERM
  # Encoder first (it finalises the file), Xvfb last, one at a time.
  for ((i=${#pids[@]}-1; i>=0; i--)); do
    pid=${pids[i]}; kill -INT "$pid" 2>/dev/null || continue
    for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$pid" 2>/dev/null || true
  done
  [ -n "${sink_module:-}" ] && pactl unload-module "$sink_module" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT INT TERM
log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1. Virtual displays: the page on $display; OBS's own window on a second display so it never appears in the capture.
start_display() {
  if [ ! -e "/tmp/.X11-unix/X${1#:}" ]; then
    "$xvfb" "$1" -screen 0 "$2x24" -nolisten tcp >"$work/xvfb${1#:}.log" 2>&1 & pids+=($!)
    for _ in $(seq 20); do [ -e "/tmp/.X11-unix/X${1#:}" ] && break; sleep 0.5; done
  fi
  [ -e "/tmp/.X11-unix/X${1#:}" ] || { echo "Xvfb $1 did not start" >&2; cat "$work/xvfb${1#:}.log" >&2; exit 1; }
}
start_display "$display" "${width}x${height}"
export DISPLAY=$display
log "display $display ready"

# 2. Optional game audio: a private null sink the browser plays into and the encoder captures.
audio_src=""
if command -v pactl >/dev/null && pactl info >/dev/null 2>&1; then
  sink_module=$(pactl load-module module-null-sink sink_name=oddbout_live sink_properties=device.description=oddbout_live)
  export PULSE_SINK=oddbout_live; audio_src=oddbout_live.monitor
  log "audio: oddbout_live sink"
else
  log "audio: none (silent track)"
fi

# 3. Production build + agent runner
node_modules/.bin/vite preview --port "$port" --strictPort --host 127.0.0.1 >"$work/preview.log" 2>&1 & pids+=($!)
for _ in $(seq 40); do curl -fsS "http://127.0.0.1:$port/broadcast.html" >/dev/null 2>&1 && break; sleep 0.5; done
curl -fsS "http://127.0.0.1:$port/broadcast.html" >/dev/null || { echo "preview did not start" >&2; cat "$work/preview.log" >&2; exit 1; }
node youtube-live/runner.mjs --url="http://127.0.0.1:$port/broadcast.html?lang=en" --cups="$cups" --width=$width --height=$height \
  > >(tee "$out/runner-$(date +%Y%m%d-%H%M%S).log") 2>&1 & pids+=($!)
runner_pid=$!
sleep 5

# 4. Encoder
stamp=$(date +%Y%m%d-%H%M%S)
if [ "$encoder" = obs ]; then
  start_display "$obs_display" 1280x720
  cfg="$work/config/obs-studio"; mkdir -p "$cfg/basic/profiles/live" "$cfg/basic/scenes"
  cat >"$cfg/global.ini" <<EOF
[General]
EnableAutoUpdates=false
[Video]
Renderer=OpenGL
EOF
  cat >"$cfg/user.ini" <<EOF
[General]
FirstRun=true
ConfirmOnExit=false
[BasicWindow]
SysTrayEnabled=true
[Basic]
Profile=live
ProfileDir=live
SceneCollection=live
SceneCollectionFile=live.json
EOF
  cat >"$cfg/basic/profiles/live/basic.ini" <<EOF
[General]
Name=live
[Video]
BaseCX=$width
BaseCY=$height
OutputCX=$width
OutputCY=$height
FPSType=0
FPSCommon=$fps
[Audio]
SampleRate=48000
ChannelSetup=Stereo
[Output]
Mode=Simple
[SimpleOutput]
StreamEncoder=x264
Preset=veryfast
VBitrate=6000
ABitrate=160
RecQuality=Stream
RecFormat2=mkv
FilePath=$PWD/$out
FileNameWithoutSpace=true
EOF
  # Key goes only into this 0700 temp directory, removed on exit.
  YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY:-} INGEST=$ingest node -e '
    require("fs").writeFileSync(process.argv[1], JSON.stringify({ type: "rtmp_custom",
      settings: { server: process.env.INGEST, key: process.env.YOUTUBE_STREAM_KEY, use_auth: false } }), { mode: 0o600 });' \
    "$cfg/basic/profiles/live/service.json"
  AUDIO_SRC=$audio_src CAPTURE_DISPLAY=$display node -e '
    const audio = process.env.AUDIO_SRC;
    const source = (name, id, settings) => ({ name, id, versioned_id: id, uuid: require("crypto").randomUUID(), settings, enabled: true, volume: 1 });
    const screen = source("Arena screen", "xshm_input", { screen: 0, show_cursor: false, advanced: true, server: process.env.CAPTURE_DISPLAY });
    const scene = source("Arena", "scene", { id_counter: 1, items: [{ name: screen.name, source_uuid: screen.uuid, id: 1, visible: true,
      pos: { x: 0, y: 0 }, scale: { x: 1, y: 1 }, rot: 0, align: 5, bounds_type: 0 }] });
    const collection = { name: "live", current_scene: "Arena", current_program_scene: "Arena", scene_order: [{ name: "Arena" }],
      sources: [screen, scene], groups: [], transitions: [], current_transition: "Fade", transition_duration: 300 };
    if (audio) collection.DesktopAudioDevice1 = { ...source("Game audio", "pulse_output_capture", { device_id: audio }), mixers: 255 };
    require("fs").writeFileSync(process.argv[1], JSON.stringify(collection));' "$cfg/basic/scenes/live.json"
  start_flag=--startstreaming; [ "$mode" = record ] && start_flag=--startrecording
  # A private session bus: OBS plugins can block on the desktop session's portal otherwise.
  if command -v dbus-daemon >/dev/null; then
    bus_info=$(dbus-daemon --session --fork --print-address=1 --print-pid=1)
    export DBUS_SESSION_BUS_ADDRESS=$(sed -n 1p <<<"$bus_info"); pids+=("$(sed -n 2p <<<"$bus_info")")
  else
    unset DBUS_SESSION_BUS_ADDRESS
  fi
  DISPLAY=$obs_display XDG_CONFIG_HOME="$work/config" JACK_NO_START_SERVER=1 obs --multi --disable-updater --disable-shutdown-check --minimize-to-tray \
    --profile live --collection live "$start_flag" >"$work/obs.log" 2>&1 & pids+=($!)
  encoder_pid=$!
else
  if [ -n "$audio_src" ]; then audio_in=(-f pulse -i "$audio_src"); else audio_in=(-f lavfi -i anullsrc=r=48000:cl=stereo); fi
  if [ "$mode" = record ]; then target=(-f matroska "$out/live-$stamp.mkv"); else target=(-f flv "$ingest/$YOUTUBE_STREAM_KEY"); fi
  ffmpeg -hide_banner -loglevel warning -nostdin -f x11grab -framerate $fps -video_size ${width}x${height} -draw_mouse 0 -i "$display" "${audio_in[@]}" \
    -c:v libx264 -preset veryfast -b:v 6000k -maxrate 6000k -bufsize 12000k -pix_fmt yuv420p -g $((fps * 2)) \
    -c:a aac -b:a 160k -ar 48000 "${target[@]}" >"$work/ffmpeg.log" 2>&1 & pids+=($!)
  encoder_pid=$!
fi
log "$encoder ${mode}ing (Ctrl-C to stop)"

# 5. Run until the duration ends, the encoder exits, or Ctrl-C.
started=$SECONDS
while kill -0 "$encoder_pid" 2>/dev/null; do
  kill -0 "$runner_pid" 2>/dev/null || { log "runner exited"; break; }
  [ "$record_s" -gt 0 ] && [ $((SECONDS - started)) -ge "$record_s" ] && break
  sleep 2
done
if ! kill -0 "$encoder_pid" 2>/dev/null; then
  log "$encoder exited early; last log lines:"
  tail -n 30 "$work/$encoder.log" | sed -E 's#(live2/)[^ ]+#\1***#g'
  exit 1
fi
log "stopping after $((SECONDS - started)) s; output in $out/"
