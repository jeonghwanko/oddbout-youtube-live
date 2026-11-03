#!/usr/bin/env bash
# Prepare dependencies and the production build. Uses apt only with passwordless sudo;
# otherwise extracts Xvfb into youtube-live/.local without touching the system.
set -euo pipefail
cd "$(dirname "$0")/.."
local_dir=youtube-live/.local

if sudo -n true 2>/dev/null && command -v apt-get >/dev/null; then
  missing=()
  command -v Xvfb >/dev/null || missing+=(xvfb)
  command -v ffmpeg >/dev/null || missing+=(ffmpeg)
  command -v pactl >/dev/null || missing+=(pulseaudio-utils)
  command -v obs >/dev/null || missing+=(obs-studio)
  if [ ${#missing[@]} -gt 0 ]; then sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"; fi
elif ! command -v Xvfb >/dev/null && [ ! -x "$local_dir/xvfb/usr/bin/Xvfb" ]; then
  tmp=$(mktemp -d)
  (cd "$tmp" && apt-get download xvfb)
  mkdir -p "$local_dir/xvfb"
  dpkg -x "$tmp"/xvfb_*.deb "$local_dir/xvfb"
  rm -rf "$tmp"
  missing_libs=$(ldd "$local_dir/xvfb/usr/bin/Xvfb" | grep 'not found' || true)
  [ -z "$missing_libs" ] || { echo "Xvfb libraries missing:"; echo "$missing_libs"; exit 1; }
fi

npm ci
if ! command -v google-chrome >/dev/null; then
  if sudo -n true 2>/dev/null; then npx playwright install --with-deps chromium; else npx playwright install chromium; fi
fi
npm run build
youtube-live/preflight.sh
