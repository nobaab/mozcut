# Building & releasing MozCut

This document covers how to produce a distributable build of MozCut. It's
written macOS-first (the current target platform); Windows and Linux notes are
at the bottom as future work.

> MozCut ships as a Flutter desktop app that shells out to a system-installed
> `ffmpeg` / `ffprobe` (see `lib/data/engine/ffmpeg_engine.dart`). That has two
> consequences for packaging, called out below: **bundling FFmpeg** and
> **re-enabling the app sandbox**.

## Prerequisites

- Flutter SDK (stable channel) with macOS desktop support enabled
  (`flutter config --enable-macos-desktop`)
- Xcode (for code signing / the macOS toolchain)
- `ffmpeg` on PATH if you want to run/test locally: `brew install ffmpeg`
- Optional, for a nicer `.dmg`: [`create-dmg`](https://github.com/create-dmg/create-dmg)
  (`brew install create-dmg`)

## 1. Build the release app

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build macos --release
```

The built app bundle lands at:

```
build/macos/Build/Products/Release/mozcut.app
```

You can smoke-test it directly:

```sh
open build/macos/Build/Products/Release/mozcut.app
```

## 2. Bundle FFmpeg (do this before shipping)

Today `FfmpegEngine` resolves `ffmpeg`/`ffprobe` from `PATH`, then falls back
to common Homebrew/system install locations (`/opt/homebrew/bin`,
`/usr/local/bin`, `/usr/bin`). That's fine for local development, but an
end user downloading MozCut will likely **not** have FFmpeg installed, so pick
one of:

- **Bundle the binaries** (recommended for a real release): copy static
  `ffmpeg` / `ffprobe` builds (e.g. from [evermeet.cx](https://evermeet.cx/ffmpeg/)
  or your own `ffmpeg` build with a compatible license — check LGPL/GPL
  implications for distribution) into
  `mozcut.app/Contents/Resources/ffmpeg` and `.../ffprobe`, then update
  `FfmpegEngine._candidateDirs` / resolution logic to also check
  `Contents/Resources` relative to the running executable. This is tracked as
  a TODO — no code change has been made for this yet, intentionally, since
  it's a product/licensing decision as much as an engineering one.
- **Document the prerequisite**: ship as-is and tell users to
  `brew install ffmpeg` before running MozCut. This is the current de facto
  behavior and is fine for early builds / developer-facing releases.

Whichever you choose, update this section and the README once it's decided.

## 3. Re-enable the app sandbox

The sandbox is currently **off** in both
`macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements` (`com.apple.security.app-sandbox = false`),
because the app spawns the system `ffmpeg`/`ffprobe` and reads arbitrary user
files on disk — both of which the sandbox restricts by default.

Before shipping outside the Mac App Store review process you still want the
sandbox on for defense-in-depth (and it's required if you ever target the Mac
App Store). To re-enable it:

1. In `macos/Runner/Release.entitlements`, set:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <true/>
   ```
2. Add the entitlements the app actually needs under sandboxing, e.g.:
   - `com.apple.security.files.user-selected.read-write` — for files picked
     via `file_picker`
   - `com.apple.security.files.bookmarks.app-scope` — if you need persistent
     access to previously-picked folders/projects across launches
   - If FFmpeg is bundled inside the app bundle (see above), no extra
     entitlement is needed to execute it (it's part of your own bundle); if
     it's expected to be found on the user's system `PATH` instead, that
     will **not** work under a sandboxed app — this is another reason to
     bundle FFmpeg before turning the sandbox on.
3. Test thoroughly: importing media, saving/opening projects, and exporting
   all need to keep working with the sandbox on.

This is left as a TODO for a dedicated pass once FFmpeg bundling is decided,
since the two are linked (a sandboxed app generally can't just exec a binary
found on `PATH`).

## 4. Code signing & notarization (TODO)

For distribution outside your own machine, macOS requires the app to be
signed with a Developer ID and notarized by Apple, or Gatekeeper will block
it.

High-level steps (placeholders — fill in with your Apple Developer account
details when ready to ship):

```sh
# Sign (replace with your Developer ID Application identity)
codesign --deep --force --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  build/macos/Build/Products/Release/mozcut.app

# Notarize (requires an app-specific password or API key stored in the keychain,
# e.g. via `xcrun notarytool store-credentials`)
xcrun notarytool submit MozCut.dmg --keychain-profile "notary-profile" --wait

# Staple the notarization ticket to the app/dmg
xcrun stapler staple MozCut.dmg
```

TODO: set up a `notary-profile` keychain entry and an Apple Developer ID
before a public release; CI does not currently sign/notarize anything (no
secrets are configured, by design — see `.github/workflows/ci.yml`).

## 5. Package as a `.dmg`

Two options, simplest first:

### Option A — `hdiutil` (no extra tools)

```sh
APP=build/macos/Build/Products/Release/mozcut.app
STAGING=build/dmg-staging
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "MozCut" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  build/MozCut.dmg
```

### Option B — `create-dmg` (nicer background/icon layout)

```sh
brew install create-dmg

create-dmg \
  --volname "MozCut" \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 200 \
  build/MozCut.dmg \
  build/macos/Build/Products/Release/mozcut.app
```

A best-effort helper script that does the build + Option A packaging is at
[`scripts/package-macos.sh`](scripts/package-macos.sh):

```sh
./scripts/package-macos.sh
```

## Windows & Linux (future work)

Not set up yet. Rough plan for later:

- **Windows:** `flutter build windows --release`, then package with
  [Inno Setup](https://jrsoftware.org/isinfo.php) or `msix` for a Microsoft
  Store-style installer. FFmpeg needs bundling the same way (a static
  `ffmpeg.exe`/`ffprobe.exe` next to the app executable). Code signing uses an
  Authenticode certificate (TODO).
- **Linux:** `flutter build linux --release`, then package as an AppImage or
  a `.deb`/`.rpm`. FFmpeg can often be a declared package dependency instead
  of bundled, depending on the target distro/package manager (TODO: decide
  per-distro).

## Related

- CI (`.github/workflows/ci.yml`) runs `flutter analyze` and
  `flutter test --exclude-tags integration` on every push/PR — it does **not**
  build or package a release artifact. Packaging/signing/notarization is a
  manual (or future, separate) workflow for now.
- `docs/FEATURES.md` lists "Bundle FFmpeg + signed installers for macOS /
  Windows / Linux" on the roadmap — this document is the working notes for
  that item.
