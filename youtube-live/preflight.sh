#!/usr/bin/env bash
# Read-only environment check for the YouTube Live exhibition stream. Installs nothing.
set -u
cd "$(dirname "$0")/.."
fails=0
row() { printf '%-5s %-22s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && fails=$((fails + 1)); return 0; }
has() { command -v "$1" >/dev/null 2>&1; }
tcp() { timeout 5 bash -c "</dev/tcp/$1/$2" >/dev/null 2>&1; }

row INFO os "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}") $(uname -m)"
row INFO resources "cpus=$(nproc) mem=$(awk '/MemTotal/{printf "%.1fGiB", $2/1048576}' /proc/meminfo) disk=$(df -h . | awk 'NR==2{print $4}') free"
if [ "$(id -u)" = 0 ]; then row PASS sudo "running as root"
elif sudo -n true 2>/dev/null; then row PASS sudo "passwordless"; else row WARN sudo "unavailable: setup.sh uses user-space Xvfb"; fi
has apt-get && row PASS apt-get "present" || row WARN apt-get "missing"

node_major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
if [ "$node_major" = 22 ]; then row PASS node "$(node -v)"
elif [ "$node_major" -gt 22 ]; then row WARN node "$(node -v): project targets 22 (npm warns EBADENGINE; tests/build passed on 24)"
else row FAIL node "Node.js 22 required ($(node -v 2>/dev/null || echo missing))"; fi
has npm && row PASS npm "$(npm -v)" || row FAIL npm "missing"
if has google-chrome; then row PASS chrome "$(google-chrome --version)"
elif ls ~/.cache/ms-playwright/chromium-* >/dev/null 2>&1; then row PASS chrome "Playwright Chromium"
else row FAIL chrome "missing (setup.sh installs Playwright Chromium)"; fi

xvfb=${XVFB_BIN:-$(command -v Xvfb || echo youtube-live/.local/xvfb/usr/bin/Xvfb)}
[ -x "$xvfb" ] && row PASS xvfb "$xvfb" || row FAIL xvfb "missing (setup.sh)"
if has obs; then row PASS obs "$(obs --version 2>/dev/null | head -1)"; else row WARN obs "missing: use LIVE_ENCODER=ffmpeg"; fi
if has ffmpeg; then
  enc=$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -oE 'libx264|h264_nvenc' | sort -u | tr '\n' ' ')
  dev=$(ffmpeg -hide_banner -devices 2>/dev/null | grep -oE 'x11grab|pulse' | sort -u | tr '\n' ' ')
  case "$enc$dev" in *libx264*x11grab*) row PASS ffmpeg "$enc$dev";; *) row WARN ffmpeg "incomplete: $enc$dev";; esac
else row WARN ffmpeg "missing"; fi
has obs || has ffmpeg || row FAIL encoder "neither OBS nor ffmpeg"
has pactl && row PASS audio "pactl (game audio routed)" || row WARN audio "no pactl: stream carries silence"
has nvidia-smi && nvidia-smi -L >/dev/null 2>&1 && row INFO gpu "$(nvidia-smi -L | head -1)" || row INFO gpu "none: x264 software encoding"

tcp a.rtmp.youtube.com 1935 && row PASS rtmp-1935 "a.rtmp.youtube.com" || row WARN rtmp-1935 "blocked"
tcp a.rtmps.youtube.com 443 && row PASS rtmps-443 "a.rtmps.youtube.com (used)" || row FAIL rtmps-443 "blocked: cannot reach YouTube ingest"
tcp github.com 443 && row PASS github "reachable" || row WARN github "unreachable"

sleep 3 & bg=$!; kill -0 "$bg" 2>/dev/null && row PASS background "child processes run" || row FAIL background "cannot keep child processes"
wait "$bg" 2>/dev/null
[ -d dist ] && row PASS build "dist/ present" || row WARN build "dist/ missing (setup.sh builds it)"

echo "RESULT: $([ $fails -eq 0 ] && echo READY || echo "NOT READY ($fails fail)")"
exit $((fails > 0))
