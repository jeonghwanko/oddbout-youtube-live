# YouTube Live (experimental)

Streams the agent exhibition page (`/broadcast.html`) to YouTube Live from a headless Linux host. Nothing in the game or Twitch Cup code changes: a virtual X display shows the page, `runner.mjs` calls `window.oddboutBroadcast.runCup` cup after cup, and OBS (or ffmpeg) captures the display and pushes RTMPS to YouTube.

| File | Role |
| --- | --- |
| `preflight.sh` | Read-only check: Node 22, Chrome, Xvfb, OBS/ffmpeg, audio, YouTube ingest reachability, background processes |
| `setup.sh` | Installs missing packages with passwordless sudo, otherwise extracts Xvfb into `youtube-live/.local/`; then `npm ci`, Chromium if needed, `npm run build` |
| `run.sh` | Xvfb → `vite preview` → runner → OBS or ffmpeg; stops each process in reverse order on exit |
| `runner.mjs` | Visible fullscreen Chrome (1920×1080) running cups with random built-in fighters and uint32 seeds |
| `GROK.md` | Instructions to paste into an external agent (Grok bot) |

## Use

```sh
youtube-live/setup.sh
youtube-live/run.sh --record=170 --cups=1          # rehearsal: youtube-live/recordings/*.mkv, no key needed
YOUTUBE_STREAM_KEY=... youtube-live/run.sh          # go live until Ctrl-C
YOUTUBE_STREAM_KEY=... youtube-live/run.sh --encoder=ffmpeg
```

Create the live event in YouTube Studio first and copy its stream key. Output is 1920×1080, 30 fps, x264 veryfast at 6000 kbps, 2 s keyframes, AAC 160 kbps, sent to `rtmps://a.rtmps.youtube.com:443/live2` (override with `YOUTUBE_INGEST`).

OBS runs on a second virtual display (`LIVE_DISPLAY` + 1) with a private D-Bus session and captures the page display through XSHM, so its own window and dialogs never reach the stream. Chrome is put in a fullscreen window through CDP because `--kiosk` needs a window manager.

Environment: `LIVE_DISPLAY` (default `:99`), `LIVE_PORT` (default `5178`, so stop `npm run dev`/`preview` first), `XVFB_BIN`, `LIVE_BROWSER_CHANNEL`, `LIVE_ENCODER`.

## Keys and logs

- The stream key is read from `YOUTUBE_STREAM_KEY` only. With OBS it is written to a 0600 `service.json` in a 0700 temporary config directory that is deleted on exit. Your own `~/.config/obs-studio` is not touched.
- With `--encoder=ffmpeg` the key is part of the ffmpeg output URL and is therefore visible in the local process list while streaming; error output is masked.
- Runner logs in `youtube-live/recordings/` contain seeds, winners, and digests only. `recordings/` and `.local/` are ignored by git.

## Local verification

2026-11-03, Ubuntu 24.04, no sudo (user-space Xvfb), Chrome 151, OBS 32.2.0 (Mesa llvmpipe renderer, x264): `run.sh --record=150 --cups=1` recorded a 135.6 s 1920×1080 30 fps H.264 + AAC file covering both semifinals, the final, and the champion card (seed 2115739349, digests `7b7934fe`/`237264ac`/`23e16d95`, cup wall time 141.9 s). `--encoder=ffmpeg --record=40` produced a 40.0 s file of the same format. No stream key was used and nothing was sent to YouTube; audio was a silent track because `pactl` was absent.

## Limits

- Audio is routed only when `pactl` reaches a PulseAudio/PipeWire server; otherwise the stream carries a silent track.
- Viewer participation through YouTube chat (`!join`) is not implemented; this streams the exhibition only.
- `broadcast.html` keeps its protocol-1 contract. A failed cup makes the runner reload the page and start a new job.
