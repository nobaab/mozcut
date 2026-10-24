# AI Video Upscale — Implementation Plan

> Feature: select clip(s) on the timeline → **AI Upscale ✨** → clip's source is
> replaced by an AI-upscaled (up to 4K) version, cached on disk, used
> automatically on export.
>
> Status: **planned / not started**. This doc is the full recipe. Everything
> here was verified end-to-end by hand on a 13s 60fps Roblox clip (3072×3840)
> on an Apple M3 before writing it down.

---

## 1. Why this fits MozCut cleanly

The whole mechanism already exists in the codebase — AI upscale is the **same
shape** as the existing speech-to-text feature.

`lib/data/speech/whisper_service.dart` already:
- shells out to an **external AI binary** (`whisper-cli`) via `Process.run`,
- resolves the binary + a **model file** from known dirs, falling back to PATH,
- uses `ffmpeg` to pre-process media (audio extract),
- **degrades gracefully** with a friendly install message when the binary/model
  is missing,
- cleans up its temp dir in a `finally`.

AI upscale is literally the same pattern with different nouns:

| whisper_service (exists)      | upscale_service (new)                       |
| ----------------------------- | ------------------------------------------- |
| ffmpeg → extract audio (wav)  | ffmpeg → extract **frames** (png)           |
| `whisper-cli` binary          | `realesrgan-ncnn-vulkan` binary             |
| `ggml-*.bin` model            | `realesr-animevideov3` model (.param/.bin)  |
| parse `.srt` → captions       | ffmpeg → **re-encode** frames → mp4         |

The `Engine` interface (`lib/data/engine/engine.dart`) explicitly documents
itself as "the boundary between the UI and the heavy video work" — but upscale
is **not** ffmpeg work, so it belongs in its **own service** (like
`WhisperService`), which *uses* the ffmpeg engine for extract/encode. Do **not**
bloat the `Engine` interface with it.

---

## 2. The tool: Real-ESRGAN ncnn-vulkan

- Binary: `realesrgan-ncnn-vulkan` (the ncnn/Vulkan build — **no Python, no
  PyTorch**, runs on GPU via Metal(mac)/Vulkan(win,linux); matches MozCut's
  macOS/Windows/Linux targets exactly).
- Upstream: `github.com/xinntao/Real-ESRGAN-ncnn-vulkan` releases
  (`*-macos.zip`, `*-windows.zip`, `*-ubuntu.zip`).
- ⚠️ **Gotcha discovered:** the release zips ship the binary **without** the
  model files, and the models in the repo are Git-LFS pointers (raw download =
  HTML). Get real `.param`/`.bin` models from a mirror that stores them as plain
  files, e.g. the `Tohrusky/realesrgan-ncnn-py` repo under
  `src/realesrgan_ncnn_py/models/` (raw.githubusercontent works).
  - `realesr-animevideov3-x4.param` / `.bin` (~1.2 MB) — **use this** (video,
    fast, temporally stable).
  - `realesrgan-x4plus.param` / `.bin` (~33 MB) — sharper but ~9× slower and
    flickers frame-to-frame on video. Optional "max quality" mode only.

### CLI usage (verified)
```bash
realesrgan-ncnn-vulkan \
  -i  <input_frames_dir> \
  -o  <output_frames_dir> \
  -n  realesr-animevideov3 \
  -m  <models_dir> \
  -s  4            # scale: 2, 3, or 4 (integer only)
  -f  png \
  -g  0            # gpu id
```
Directory in/out = model loaded once, all frames processed. Help: run with no args.

---

## 3. The pipeline (verified recipe)

The key insight from testing: **upscaling fixes low detail, not resolution.**
If the source already has high resolution but looks blurry ("looks like 144p"),
downscale to the true detail level first, then AI-upscale back up — this gives
the cleanest reconstruction and controls compute/disk.

### Decision: downscale base + scale factor
Pick a base so that `base × scale == target`. For a 3072×3840 vertical clip:
- **768×960 base + `-s 4`** → 3072×3840. Most aggressive cleanup. Best for
  pure gameplay footage with no fine text/graphics. (This was the chosen recipe
  for the clean, text-free clip.)
- **1536×1920 base + `-s 2`** → 3072×3840. Gentler; preserves fine detail /
  sharp text much better. Use when the frame contains crisp overlays.

> ⚠️ **Sharp text/vector overlays get mangled by aggressive downscale+AI.**
> Correct product behaviour: upscale **raw footage only**; text/stickers/effects
> are burned in *after* upscaling (MozCut already composites those at export —
> so a clip whose source is upscaled gets sharp overlays for free). Do NOT feed
> already-captioned footage through the upscaler.

### Steps (per clip, chunked to stay disk-safe)
1. **Extract audio:** `ffmpeg -i src -vn -c:a copy audio.m4a`
2. **Extract base frames:** `ffmpeg -i src -vf "scale=W:H:flags=lanczos" -start_number 0 base/f_%06d.png`
3. **Chunk loop** (e.g. 64 frames/chunk — keeps peak disk ≈ 2–3 GB, not 16 GB):
   - move chunk's frames into `cin/`
   - `realesrgan-ncnn-vulkan -i cin -o cout -n realesr-animevideov3 -m MODELS -s 4 -f png -g 0`
   - encode segment: `ffmpeg -framerate <fps> -start_number <i> -i cout/f_%06d.png -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p -x264-params keyint=<fps>:min-keyint=<fps>:scenecut=0 segs/seg_<k>.mp4`
   - `rm cin/* cout/*`  ← frees disk every chunk
4. **Concat segments:** `ffmpeg -f concat -safe 0 -i list.txt -c copy video_noaudio.mp4`
5. **Mux audio back:** `ffmpeg -i video_noaudio.mp4 -i audio.m4a -c:v copy -c:a aac -b:a 192k -shortest out.mp4`
6. Delete all intermediates.

A reference bash implementation of exactly this lives in the chat history
(`upscale.sh`) — port its logic to Dart.

### Measured performance (Apple M3, 768→4x, 3072×3840 out)
- `realesr-animevideov3`: **~2 s/frame** → 768 frames ≈ **25–30 min**.
- `realesrgan-x4plus`: ~18 s/frame → ≈ 4 hours. (Not worth it for video.)
- Progress = `frames_done / total_frames` → drive the 0..1 progress bar.

---

## 4. Code changes

### New: `lib/data/upscale/upscale_service.dart`
Model it on `WhisperService`. Sketch:

```dart
@Riverpod(keepAlive: true)
UpscaleService upscaleService(Ref ref) => UpscaleService();

class UpscaleService {
  UpscaleService({String? ffmpegPath, String? binaryPath, String? modelsDir})
      : _ffmpeg = ffmpegPath ?? _resolveFfmpeg(),
        _binaryOverride = binaryPath,
        _modelsOverride = modelsDir;

  // Candidate binary names: 'realesrgan-ncnn-vulkan' (+ '.exe' on Windows).
  // Candidate dirs: bundled app resources first, then PATH (see _which).

  /// Upscales [clip]'s trimmed region to [targetWidth]×[targetHeight],
  /// writing an mp4 to [outputPath]. Reports 0..1 via [onProgress].
  /// Throws [UpscaleException] (friendly install msg) if binary/model missing.
  Future<void> upscale({
    required Clip clip,
    required String outputPath,
    required int targetWidth,
    required int targetHeight,
    int scale = 4,                 // 2|3|4; base = target / scale
    String model = 'realesr-animevideov3',
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    CancellationToken? cancel,     // see §5
  }) async { /* pipeline from §3, chunked */ }
}

class UpscaleException implements Exception { ... }
```

Reuse `WhisperService`'s `_which` / `_resolveFfmpeg` / `_resolve*` helpers
(consider extracting them to a shared `tool_resolver.dart`).

### Caching (don't re-upscale)
Follow `FfmpegEngine._mediaCacheDir()` / `project_store`'s
`getApplicationSupportDirectory()`. Cache key = hash of
`(sourcePath, inPoint, outPoint, targetW, targetH, scale, model)`. If the cached
mp4 exists, return it instantly.

### Wiring into the editor
- `Clip.sourcePath` is swappable via `copyWith` (`lib/domain/models/clip.dart`).
  After upscale, set the selected clip's `sourcePath` to the cached upscaled
  file (reset `inPoint=0`, `outPoint=duration` since the cache is already
  trimmed). Keep a `String? originalSourcePath` so "Revert to original" works.
- Selection already exists: `EditorState.selectedId` / `.selected`
  (`editor_view_model.dart`). Support multi-select later; MVP = selected clip.
- Add a `UpscaleViewModel` (riverpod) holding `{status, progress, isRunning}`.

### UI
- Button in the **inspector panel** (`inspector_panel.dart`) or timeline toolbar:
  "AI Upscale ✨" + a target dropdown (e.g. 1080p / 4K).
- While running: progress bar + **Cancel**. On missing binary: show the
  `UpscaleException` message (install steps) like whisper does.

---

## 4b. ⚠️ Chunked-encode keyframe bug (hit during testing — do NOT repeat)

The first chunked run encoded each chunk with
`-x264-params keyint=<fps>:min-keyint=<fps>:scenecut=0` to make the segments
concat cleanly. **`scenecut=0` disables scene-change keyframes.** Any hard cut in
the footage that does *not* land on the forced keyframe grid then gets encoded as
P-frames predicting a completely different scene across the cut → visible
**stutter/smear/"lag" at those cuts** (the decoded pixels are fine; it's a GOP
problem). Cuts that happened to sit next to a forced keyframe looked OK, which is
why only *some* cuts glitched — a confusing symptom.

**Fix / rules:**
- Do **not** set `scenecut=0`. Leave x264 scene detection on (default `scenecut=40`).
- Each concat segment still starts with an IDR anyway (segment frame 0), so
  concat `-c copy` keeps working with scene detection enabled.
- For guaranteed-correct cuts, detect the source's scene cuts and **force
  keyframes exactly there**:
  ```bash
  CUTS=$(ffmpeg -i src.mp4 -vf "select='gt(scene,0.25)',showinfo" -f null - 2>&1 \
         | grep -oE 'pts_time:[0-9.]+' | sed 's/pts_time://' | paste -sd, -)
  ffmpeg -i in.mp4 -c:v libx264 -crf 16 -pix_fmt yuv420p \
         -force_key_frames "$CUTS" -x264-params "scenecut=40:keyint=120:min-keyint=2" \
         -c:a copy -movflags +faststart out.mp4
  ```
- Best of all: when disk allows, do a **single final encode** over all upscaled
  frames (not per-chunk segments) so there's no concat/GOP juggling at all.
- Note `-ss` seeking is approximate; verify keyframes landed with
  `ffprobe -select_streams v:0 -skip_frame nokey -show_entries frame=pts_time`.

## 5. Things to get right
- **Cancellation:** keep the `Process` handle; on cancel, `process.kill()` and
  stop the chunk loop. (Whisper doesn't cancel today — this feature needs it,
  jobs are long.)
- **Disk:** always chunk + delete per chunk. Check free space before starting;
  warn if low. (Hit a 4.8 GB-free machine during testing — chunking was
  essential.)
- **Audio & fps:** preserve both. Read fps via `ffprobe r_frame_rate`; pass to
  the encode so 60fps stays 60fps.
- **Even dimensions:** libx264 needs even W/H (`yuv420p`). Integer scales of even
  bases stay even.
- **Keep overlays out:** upscale the raw clip source only (see §3 warning).
- **Run off the UI isolate:** it's `Process`-based so it won't block the UI
  thread, but marshal progress via a stream/callback like whisper's `onStatus`.

---

## 6. Bundling (post-MVP)
MVP can resolve the binary from PATH + show an install hint (exactly like
whisper). For shipping:
- Put per-platform `realesrgan-ncnn-vulkan` + `models/` under app resources
  (macOS: `.app/Contents/Resources`; Windows/Linux: alongside the exe), add to
  `_candidateDirs` ahead of PATH.
- macOS: strip quarantine / sign the binary (`xattr -dr com.apple.quarantine`
  during dev) or it won't launch.
- Models are small for animevideov3 (~1.2 MB) — fine to bundle. x4plus (~33 MB)
  only if offering a "max quality" mode.

---

## 7. MVP checklist
- [ ] `UpscaleService` with chunked pipeline (§3) + binary/model resolution
- [ ] Binary + models available on PATH for dev (`realesr-animevideov3`)
- [ ] Caching keyed on clip+target
- [ ] `UpscaleViewModel` (status/progress/running) + cancellation
- [ ] Inspector button + target dropdown + progress bar + cancel
- [ ] Swap `Clip.sourcePath` → cached file; keep `originalSourcePath` for revert
- [ ] Friendly error when binary/model missing (mirror whisper's message)
- [ ] Unit-test the pure parts (cache-key, dim/scale math) without the binary
