#!/usr/bin/env bash
# Prepare dependencies and the production build. Uses apt as root or with passwordless sudo;
# otherwise extracts Xvfb into youtube-live/.local without touching the system.
set -euo pipefail
cd "$(dirname "$0")/.."
local_dir=youtube-live/.local

as_root=()
if [ "$(id -u)" = 0 ]; then can_root=1; elif sudo -n true 2>/dev/null; then can_root=1; as_root=(sudo); else can_root=0; fi

if [ "$can_root" = 1 ] && command -v apt-get >/dev/null; then
  required=(); optional=()
  command -v Xvfb >/dev/null || required+=(xvfb)
  command -v ffmpeg >/dev/null || required+=(ffmpeg)
  command -v pactl >/dev/null || optional+=(pulseaudio-utils)
  command -v obs >/dev/null || optional+=(obs-studio)
  apt_install() { "${as_root[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"; }
  if [ $((${#required[@]} + ${#optional[@]})) -gt 0 ]; then "${as_root[@]}" apt-get update -qq; fi
  if [ ${#required[@]} -gt 0 ]; then apt_install "${required[@]}"; fi
  # OBS and pactl are optional: run.sh falls back to ffmpeg and a silent track.
  for pkg in "${optional[@]}"; do apt_install "$pkg" || echo "optional package $pkg not installed"; done
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
  if [ "$can_root" = 1 ]; then npx playwright install --with-deps chromium; else npx playwright install chromium; fi
fi
npm run build
youtube-live/preflight.sh
