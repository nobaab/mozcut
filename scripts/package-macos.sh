#!/usr/bin/env bash
#
# Best-effort packaging script: builds the macOS release app and wraps it in
# a .dmg for distribution. See RELEASE.md for the full write-up (FFmpeg
# bundling, sandbox, code signing/notarization are NOT handled here — this
# just automates the mechanical build + dmg steps).
#
# Usage:
#   ./scripts/package-macos.sh
#
# Output:
#   build/MozCut.dmg

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP_NAME="mozcut.app"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}"
DMG_OUT="build/MozCut.dmg"
STAGING_DIR="build/dmg-staging"

log() { printf '\n==> %s\n' "$1"; }

command -v flutter >/dev/null 2>&1 || {
  echo "error: flutter not found on PATH. Install Flutter first." >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script packages a macOS .app/.dmg and must run on macOS." >&2
  exit 1
fi

log "flutter pub get"
flutter pub get

log "Generating code (build_runner)"
if ! dart run build_runner build --delete-conflicting-outputs; then
  echo "warning: build_runner failed or found nothing to do; continuing." >&2
fi

log "Building macOS release app"
flutter build macos --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "warning: ffmpeg not found on PATH. The packaged app will rely on the" >&2
  echo "         end user having ffmpeg/ffprobe installed (see RELEASE.md)." >&2
fi

if command -v create-dmg >/dev/null 2>&1; then
  log "Packaging with create-dmg"
  rm -f "$DMG_OUT"
  create-dmg \
    --volname "MozCut" \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 200 \
    "$DMG_OUT" \
    "$APP_PATH" || {
      echo "warning: create-dmg failed, falling back to hdiutil." >&2
    }
fi

if [[ ! -f "$DMG_OUT" ]]; then
  log "Packaging with hdiutil"
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  cp -R "$APP_PATH" "$STAGING_DIR/"
  ln -sf /Applications "$STAGING_DIR/Applications"

  rm -f "$DMG_OUT"
  hdiutil create -volname "MozCut" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_OUT"

  rm -rf "$STAGING_DIR"
fi

log "Done: $DMG_OUT"
echo "Note: this .dmg is unsigned and not notarized. See RELEASE.md section 4"
echo "before distributing it publicly."
