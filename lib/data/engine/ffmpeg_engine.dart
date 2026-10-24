import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/audio_clip.dart';
import '../../domain/models/caption.dart';
import '../../domain/models/clip.dart';
import '../../domain/models/color_filter_presets.dart';
import '../../domain/models/effect_presets.dart';
import '../../domain/models/export_settings.dart';
import '../../domain/models/keyframe.dart';
import '../../domain/models/media_type.dart';
import '../../domain/models/sfx_presets.dart';
import '../../domain/models/shape_presets.dart';
import '../../domain/models/sticker_overlay.dart';
import '../../domain/models/text_overlay.dart';
import '../../domain/models/transition_presets.dart';
import '../../domain/models/video_overlay.dart';
import 'engine.dart';

part 'ffmpeg_engine.g.dart';

/// The app's single engine. Swap the implementation here (e.g. to a Rust-backed
/// engine) and nothing else changes.
@Riverpod(keepAlive: true)
Engine engine(Ref ref) => FfmpegEngine();

/// Engine implementation backed by the system `ffmpeg` / `ffprobe` binaries.
///
/// This spawns processes; it never links FFmpeg in-process. That is a feature:
/// it keeps the hard C out of the Dart app for now, and it is the easiest thing
/// that actually works on macOS and Windows. The binary is resolved from PATH,
/// then from the usual install locations.
class FfmpegEngine implements Engine {
  FfmpegEngine({String? ffmpegPath, String? ffprobePath})
      : _ffmpeg = ffmpegPath ?? _resolve('ffmpeg'),
        _ffprobe = ffprobePath ?? _resolve('ffprobe');

  final String _ffmpeg;
  final String _ffprobe;

  // Cache for [_resolveUsableEmojiFont]'s capability probe — it spawns a real
  // ffmpeg process, so it's worth paying once per engine lifetime rather than
  // once per sticker/export. `_emojiFontProbed` distinguishes "not probed
  // yet" from "probed, and no usable font was found" (where the cache itself
  // would be null).
  String? _emojiFontCache;
  bool _emojiFontProbed = false;

  // The internal filtergraph timebase every per-clip chain runs at (the
  // `color=` background source's `r=`, and the `fps=` re-assertion before
  // each `xfade`). Independent of the project's canvas *size* (threaded
  // through via `canvasWidth`/`canvasHeight` params below) and of the
  // export's own output frame rate (`ExportSettings.fps`, applied by ffmpeg
  // at encode time) — this is purely an internal constant so every clip's
  // chain shares one timebase before concat/xfade.
  static const _canvasFps = 30;

  // renderPreview's proxy render: small enough to render fast, big enough to
  // judge framing/captions/overlays at a glance.
  static const _previewWidth = 640;

  static const _candidateDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];

  static String _resolve(String tool) {
    final exe = Platform.isWindows ? '$tool.exe' : tool;
    for (final dir in _candidateDirs) {
      final p = '$dir/$exe';
      if (File(p).existsSync()) return p;
    }
    // Fall back to bare name and let the OS search PATH.
    return exe;
  }

  @override
  Future<double> probeDuration(String path) async {
    final result = await Process.run(_ffprobe, [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('ffprobe failed: ${result.stderr}');
    }
    final value = double.tryParse(result.stdout.toString().trim());
    if (value == null || value <= 0) {
      throw EngineException('Could not read duration from "$path"');
    }
    return value;
  }

  @override
  Future<(int, int)> probeDimensions(String path) async {
    final result = await Process.run(_ffprobe, [
      '-v', 'error',
      '-select_streams', 'v:0',
      '-show_entries', 'stream=width,height',
      '-of', 'csv=s=x:p=0',
      path,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('ffprobe failed: ${result.stderr}');
    }
    final parts = result.stdout.toString().trim().split('x');
    final width = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final height = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw EngineException('Could not read dimensions from "$path"');
    }
    return (width, height);
  }

  @override
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    List<VideoOverlay> videoOverlays = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    final totalDuration =
        _timelineDurationOf(clips, audioClips, videoOverlays);

    final graph = await _buildFilterGraph(
      clips: clips,
      textOverlays: textOverlays,
      stickerOverlays: stickerOverlays,
      audioClips: audioClips,
      videoOverlays: videoOverlays,
      scaleFilter: settings.scaleFilter,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      timelineDuration: totalDuration,
    );
    try {
      // GIF has no audio track and needs its own palette: ffmpeg's default
      // GIF quantizer (a fixed websafe-ish palette) looks noticeably banded,
      // so the standard fix is to build a per-export palette from the actual
      // frames (`palettegen`) and dither against it (`paletteuse`). `split`
      // feeds the same video pad into both: one copy becomes the palette
      // source, the other is the stream that gets quantized against it.
      // Appended onto the *existing* filtergraph's final video label, so
      // every earlier stage (transforms, captions, text/sticker overlays,
      // resize) still applies exactly as it does for every other format —
      // this is strictly additive, no format but GIF ever reaches this
      // branch, so `mp4`/`mov` exports are byte-for-byte unaffected.
      // ffmpeg's -filter_complex parser requires every declared output pad
      // to be *connected* to something — mapped to the output file, or fed
      // into another filter — or it refuses to run at all ("Filter ...
      // unconnected"). GIF never maps the audio pad (`graph.audioLabel`,
      // e.g. `[outa]`), so route it into `anullsink` (a filter that just
      // discards its input) purely to satisfy that requirement — no audio
      // stream ends up in the output either way.
      final isGif = settings.isGif;
      final filterComplex = isGif
          ? '${graph.filterComplex};${graph.videoLabel}split[gifsrc][gifpal];'
              '[gifpal]palettegen[gifp];'
              '[gifsrc][gifp]paletteuse[gifout];'
              '${graph.audioLabel}anullsink'
          : graph.filterComplex;
      final videoMapLabel = isGif ? '[gifout]' : graph.videoLabel;

      // One ffmpeg call: each clip is an input trimmed with -ss/-to, then the
      // concat filter joins them. Re-encoding (not stream copy) so clips with
      // different codecs/resolutions still join cleanly — correctness over
      // speed for v0.1.
      final args = <String>[
        '-y',
        ...graph.inputArgs,
        '-filter_complex', filterComplex,
        '-map', videoMapLabel,
        if (!isGif) ...['-map', graph.audioLabel],
        ...settings.toFfmpegArgs(),
        // Bound the output to the timeline length. Overlays whose image is a
        // looped still (`-loop 1` stickers) are infinite inputs, so without an
        // explicit `-t` the mux would never terminate; the timeline duration
        // is the only correct stop point regardless of which inputs are finite.
        '-t', totalDuration.toStringAsFixed(3),
        '-progress', 'pipe:1',
        '-nostats',
        outputPath,
      ];

      await _runFfmpeg(args,
          totalDuration: totalDuration,
          action: 'export',
          onProgress: onProgress);
    } finally {
      await _deleteAll(graph.tempFiles);
    }
  }

  @override
  Future<void> exportStillFrame({
    required List<Clip> clips,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    required double atSeconds,
    required String outputPath,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    // Reuses the exact same filtergraph export()/renderPreview() build (same
    // transforms, captions, text/sticker overlays) so a still frame always
    // matches what the real export would show at this instant — the only
    // difference is `-ss` (seeked on the *composited* output, after the
    // filtergraph, so it lines up with the same timeline TextOverlay.start/
    // end and captions are defined against) plus `-frames:v 1` instead of a
    // full encode.
    final graph = await _buildFilterGraph(
      clips: clips,
      textOverlays: textOverlays,
      stickerOverlays: stickerOverlays,
      scaleFilter: settings.scaleFilter,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
    try {
      // Same `anullsink` reasoning as the GIF branch in [export]: this never
      // maps `graph.audioLabel` (a still frame has no audio), so it has to
      // be routed somewhere or ffmpeg's filtergraph parser rejects the whole
      // graph as having an unconnected output pad.
      final filterComplex = '${graph.filterComplex};${graph.audioLabel}anullsink';
      final args = <String>[
        '-y',
        ...graph.inputArgs,
        '-filter_complex', filterComplex,
        '-map', graph.videoLabel,
        '-ss', atSeconds.toStringAsFixed(3),
        '-frames:v', '1',
        outputPath,
      ];
      final result = await Process.run(_ffmpeg, args);
      if (result.exitCode != 0) {
        throw EngineException('still-frame export failed: ${result.stderr}');
      }
    } finally {
      await _deleteAll(graph.tempFiles);
    }
  }

  @override
  Future<String> renderPreview({
    required List<Clip> clips,
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    List<VideoOverlay> videoOverlays = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to preview — the timeline is empty.');
    }

    final totalDuration =
        _timelineDurationOf(clips, audioClips, videoOverlays);
    final outputPath =
        '${Directory.systemTemp.path}/mozcut_preview_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Same filtergraph as export() (via _buildFilterGraph) so the preview is
    // never out of sync with the real edit — just scaled down and encoded for
    // speed instead of quality.
    final graph = await _buildFilterGraph(
      clips: clips,
      textOverlays: textOverlays,
      stickerOverlays: stickerOverlays,
      audioClips: audioClips,
      videoOverlays: videoOverlays,
      scaleFilter: 'scale=$_previewWidth:-2',
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      timelineDuration: totalDuration,
    );
    try {
      final args = <String>[
        '-y',
        ...graph.inputArgs,
        '-filter_complex', graph.filterComplex,
        '-map', graph.videoLabel,
        '-map', graph.audioLabel,
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-crf', '28',
        '-c:a', 'aac',
        // See export(): bound to the timeline so looped-still overlay inputs
        // (`-loop 1` stickers) can't make the preview render run forever.
        '-t', totalDuration.toStringAsFixed(3),
        '-progress', 'pipe:1',
        '-nostats',
        outputPath,
      ];

      await _runFfmpeg(args,
          totalDuration: totalDuration,
          action: 'preview render',
          onProgress: onProgress);
      return outputPath;
    } finally {
      await _deleteAll(graph.tempFiles);
    }
  }

  /// Builds the input args and `-filter_complex` graph shared by [export] and
  /// [renderPreview]: per-clip transform (scale/pos/rotate/flip) on video,
  /// speed (setpts + atempo), then audio volume/fades — concatenated in
  /// order, optionally resized (via [scaleFilter], an ffmpeg filter fragment
  /// like `scale=1920:-2`, or `null` to keep the concatenated resolution),
  /// then captions burned in from clips' caption lists, then one `drawtext`
  /// per entry in [textOverlays], then one more `drawtext` per entry in
  /// [stickerOverlays] (an emoji sticker is rendered as text, with a
  /// colour-emoji font — see [_resolveUsableEmojiFont]), then composites one
  /// more layer per entry in [videoOverlays] (the picture-in-picture lane —
  /// see the block below for the ffmpeg mapping). Factored out of `export` so
  /// the two call sites can never drift — this is exactly the graph `export`
  /// built inline before [renderPreview] existed.
  ///
  /// Returns the pieces still needed to assemble a full ffmpeg invocation,
  /// plus any temp files (captions .srt, overlay/sticker text files) the
  /// caller must delete once its ffmpeg process has exited.
  Future<_FilterGraph> _buildFilterGraph({
    required List<Clip> clips,
    required List<TextOverlay> textOverlays,
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    List<VideoOverlay> videoOverlays = const [],
    String? scaleFilter,
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    double timelineDuration = 0,
  }) async {
    File? srtFile;
    final overlayFiles = <File>[];
    try {
      // If any clip carries captions, burn them into the output via ffmpeg's
      // `subtitles` filter, fed from a temp .srt built from all clips'
      // caption lists with their timing shifted onto the final, concatenated
      // timeline. Keep this fully additive: no captions anywhere means no
      // subtitles filter and the graph is exactly what it was before.
      if (clips.any((c) => c.captions.isNotEmpty)) {
        srtFile = File(
            '${Directory.systemTemp.path}/mozcut_captions_${DateTime.now().millisecondsSinceEpoch}.srt');
        await srtFile.writeAsString(_buildSrt(clips));
      }

      // Each clip contributes one video input, plus (for an image clip, which
      // has no audio stream of its own) a second, synthetic silent-audio
      // input right after it — see the `MediaType.image` branch below. Index
      // bookkeeping is kept in parallel lists rather than assuming "clip i ==
      // input i" (true only when there are no image clips), so the two never
      // drift.
      final inputArgs = <String>[];
      final videoInputIndex = <int>[];
      final audioInputIndex = <int>[];
      var nextInputIndex = 0;
      for (final clip in clips) {
        if (clip.mediaType == MediaType.image) {
          // `-loop 1 -t <duration> -i <image>` turns a still image into a
          // finite video stream of exactly the clip's trimmed length (an
          // image has no intrinsic duration, so there is no `-ss`/`-to`
          // region to seek — the whole file is "the frame"). `-t` is applied
          // pre-speed, same as `-to - -ss` is for a real video clip; the
          // clip's own `speed` is applied afterwards via `setpts`, same as
          // every other clip.
          final stillDuration =
              (clip.outPoint - clip.inPoint).clamp(0.01, double.infinity);
          inputArgs.addAll([
            '-loop', '1',
            '-t', stillDuration.toStringAsFixed(3),
            '-i', clip.sourcePath,
          ]);
          videoInputIndex.add(nextInputIndex++);
          // A silent audio input of the same length, so this clip's `[N:a:0]`
          // exists and lines up with the video input's duration — needed
          // because `concat`/`xfade`+`acrossfade` (and later, mixing in
          // `audioClips`) all expect every clip to have an audio pad.
          inputArgs.addAll([
            '-f', 'lavfi',
            '-t', stillDuration.toStringAsFixed(3),
            '-i', 'anullsrc=r=48000:cl=stereo',
          ]);
          audioInputIndex.add(nextInputIndex++);
        } else {
          inputArgs.addAll([
            '-ss', clip.inPoint.toStringAsFixed(3),
            '-to', clip.outPoint.toStringAsFixed(3),
            '-i', clip.sourcePath,
          ]);
          videoInputIndex.add(nextInputIndex);
          audioInputIndex.add(nextInputIndex);
          nextInputIndex++;
        }
      }

      // Per clip: transform (scale/pos/rotate/flip) on video, speed (setpts +
      // atempo), then audio volume/fades — then concat, then burn captions.
      // Every step is additive: a default clip reproduces the old graph exactly.
      final filter = StringBuffer();
      final videoLabels = <String>[];
      final audioLabels = <String>[];
      for (var i = 0; i < clips.length; i++) {
        final clip = clips[i];
        var vlabel = _videoFilterChain(filter, i, videoInputIndex[i], clip,
            canvasWidth, canvasHeight); // label, no brackets
        var alabel = '${audioInputIndex[i]}:a:0';
        if (clip.speed != 1.0) {
          filter.write(
              '[$vlabel]setpts=PTS/${_fmtFilterNum(clip.speed)}[sv$i];');
          vlabel = 'sv$i';
          final atempo = _atempoChain(clip.speed)
              .map((f) => 'atempo=${_fmtFilterNum(f)}')
              .join(',');
          filter.write('[${audioInputIndex[i]}:a:0]$atempo[sa$i];');
          alabel = 'sa$i';
        }
        final achain = _audioFilterChain(clip);
        if (achain != null) {
          filter.write('[$alabel]$achain[fa$i];');
          alabel = 'fa$i';
        }
        videoLabels.add(vlabel);
        audioLabels.add(alabel);
      }
      final joined = _joinClips(filter, clips, videoLabels, audioLabels);

      // Chain optional stages onto the joined output, each writing to a fresh
      // label so the filtergraph stays a simple linear pipe no matter which
      // stages are present. NB: the optional resize ([scaleFilter]) is applied
      // LAST, after captions and every overlay, so overlays composite against
      // the full-resolution canvas pad (see the final-resize block below).
      var videoLabel = '[${joined.video}]';
      if (srtFile != null) {
        const outLabel = '[vsub]';
        filter.write(
            ';${videoLabel}subtitles=${_escapeFilterPath(srtFile.path)}$outLabel');
        videoLabel = outLabel;
      }

      // Burn in text/title overlays, one `drawtext` filter per overlay,
      // chained in order. Each is timed with `enable='between(t,start,end)'`
      // against `t`, which on this output label is already the final,
      // concatenated timeline — exactly what TextOverlay.start/end are
      // defined against. Fully additive: no overlays, no filter stage, and
      // the graph is byte-for-byte what it was before this feature.
      if (textOverlays.isNotEmpty) {
        final fontFile = _resolveFont();
        for (var i = 0; i < textOverlays.length; i++) {
          final textFile = File(
              '${Directory.systemTemp.path}/mozcut_text_${DateTime.now().millisecondsSinceEpoch}_$i.txt');
          await textFile.writeAsString(textOverlays[i].text);
          overlayFiles.add(textFile);

          final nextLabel = '[vt$i]';
          filter.write(
              ';$videoLabel${_drawtextFilter(textOverlays[i], textFile, fontFile)}$nextLabel');
          videoLabel = nextLabel;
        }
      }

      // Burn in sticker overlays, one per sticker, chained after the title
      // overlays — each is either an *image* sticker (a user-imported file
      // or a generated shape, composited with `overlay`) or an *emoji*
      // sticker (just text, via `drawtext` — the original behaviour).
      // Fully additive: no stickers, no filter stage, and the graph is
      // byte-for-byte what it was before this feature existed.
      if (stickerOverlays.isNotEmpty) {
        // The emoji-capable font is only resolved the first time it's
        // actually needed (lazily, not up front) — a project with only
        // image stickers never pays for the capability probe
        // [_resolveUsableEmojiFont] runs.
        String? emojiFont;
        var emojiFontResolved = false;

        for (var i = 0; i < stickerOverlays.length; i++) {
          final sticker = stickerOverlays[i];

          if (sticker.isImage) {
            // One extra `-i` input for this sticker's image (`-loop 1` so
            // it keeps producing frames for `overlay` to read for as long
            // as the output runs, the same convention an image *clip*
            // input uses above, for the same reason — the output is bounded
            // by the `-t` the caller adds, never by this infinite input).
            // Scaled to `size` (a fraction of the frame *height*) with a plain
            // `scale` to absolute pixels: the running pad is exactly
            // [canvasWidth]x[canvasHeight] at this point (the optional resize
            // happens LAST, after every overlay), so pixels derived from the
            // canvas are correct, and `scale=-2:h` preserves the image's own
            // aspect. A plain `scale` is used instead of `scale2ref` on
            // purpose: two chained `scale2ref` (one per sticker, one per PiP
            // overlay) dead-lock this ffmpeg before it can emit a frame.
            // Optionally rotated (`c=none` keeps the corners exposed by
            // rotation transparent instead of filling them), then composited
            // with `overlay`, anchored at its `x`/`y` center, windowed with
            // `enable='between(t,start,end)'` like every other overlay.
            inputArgs.addAll(['-loop', '1', '-i', sticker.imagePath!]);
            final imgInput = nextInputIndex++;

            final scaledLabel = '[stksc$i]';
            final stkH = _evenPx(canvasHeight * sticker.size);
            filter.write(
                ';[$imgInput:v]format=rgba,scale=-2:$stkH$scaledLabel');

            var imagePad = scaledLabel;
            if (sticker.rotation != 0) {
              final radians = sticker.rotation * 3.141592653589793 / 180.0;
              final rotLabel = '[stkrot$i]';
              filter.write(';${imagePad}rotate=${_fmtFilterNum(radians)}:'
                  'ow=rotw(${_fmtFilterNum(radians)}):'
                  'oh=roth(${_fmtFilterNum(radians)}):c=none$rotLabel');
              imagePad = rotLabel;
            }

            final nextLabel = '[vimg$i]';
            filter.write(';$videoLabel${imagePad}overlay=x='
                "'main_w*${_fmtFilterNum(sticker.x)}-overlay_w/2':y="
                "'main_h*${_fmtFilterNum(sticker.y)}-overlay_h/2':enable="
                "'between(t,${sticker.start.toStringAsFixed(3)},"
                "${sticker.end.toStringAsFixed(3)})'$nextLabel");
            videoLabel = nextLabel;
            continue;
          }

          // The only difference from a text overlay is the font — plain
          // system fonts (Arial/DejaVu/Liberation, see `_resolveFont`) don't
          // carry colour glyphs for emoji, so this resolves a colour-emoji
          // font instead (e.g. macOS's Apple Color Emoji) and passes that as
          // `fontfile`, *after* confirming this machine's ffmpeg can
          // actually rasterize it — see [_resolveUsableEmojiFont] for why
          // that check exists and isn't optional (on an unsupported build,
          // just pointing `fontfile` at a colour-bitmap font doesn't
          // degrade gracefully, it aborts the whole filtergraph).
          if (!emojiFontResolved) {
            emojiFont = await _resolveUsableEmojiFont();
            emojiFontResolved = true;
          }
          final stickerFile = File(
              '${Directory.systemTemp.path}/mozcut_sticker_${DateTime.now().millisecondsSinceEpoch}_$i.txt');
          await stickerFile.writeAsString(sticker.emoji ?? '');
          overlayFiles.add(stickerFile);

          final nextLabel = '[vk$i]';
          filter.write(
              ';$videoLabel${_drawtextFilter(_asTextOverlay(sticker), stickerFile, emojiFont)}$nextLabel');
          videoLabel = nextLabel;
        }
      }

      // Composite the picture-in-picture lane: one more video (or
      // image-as-video) layer per [VideoOverlay], each with its own trimmed
      // `-i` input (`-ss`/`-to`, same convention as a main clip), chained
      // after text/sticker burn-in so a PiP floats above both. `mixLabels`
      // for overlay *audio* (if any) is collected here but mixed in below,
      // alongside `audioClips`, so there is exactly one `amix` stage.
      //
      // Each overlay's video is: reset to pts 0 (`setpts=PTS-STARTPTS`, same
      // safety [AudioClip]'s trim relies on implicitly) then shifted so its
      // first frame lands at `startTime` on the *output* timeline
      // (`+startTime/TB`) — `overlay`/`blend`'s own frame-sync only decides
      // *when* to apply the filter (via `enable`), it never shifts an
      // input's own timestamps, so without this shift the overlay would
      // always appear to start at t=0 regardless of `startTime`. Then scaled
      // with a plain `scale` to absolute pixels derived from
      // [canvasWidth]/[canvasHeight]: the running pad is exactly that size at
      // this point (the optional preview resize runs LAST, after every
      // overlay), so canvas pixels are correct. A plain `scale` is used
      // instead of `scale2ref` on purpose — two chained `scale2ref` (sticker
      // + PiP) dead-lock this ffmpeg before it can emit a single frame.
      //
      // `blendMode == 'normal'` composites with a plain, positioned
      // `overlay` (opacity faked via `colorchannelmixer=aa=`, since `overlay`
      // has no opacity option of its own) — sized to a fraction of the canvas
      // *width*, aspect preserved (`scale=W:-2`); this is the only mode that
      // honours [VideoOverlay.scale]/[posX]/[posY]/[rotation]. Every other
      // mode uses ffmpeg's `blend=all_mode=<mode>:all_opacity=<opacity>`
      // instead (verified against a real local ffmpeg 8.0: `blend` supports
      // the same `enable` timeline windowing `overlay` does), which requires
      // both inputs to share exactly one size — so a non-normal blend mode
      // fills the *full* canvas rather than honouring scale/position/rotation.
      // This is a deliberate, documented simplification (see
      // docs/CAPCUT-SPEC.md): every blend mode and opacity visibly work, just
      // without independent PiP framing.
      //
      // Fully additive: an empty [videoOverlays] (the default) never writes
      // any of this stage, so the graph is byte-for-byte what it was before
      // this feature existed.
      final overlayAudioLabels = <String>[];
      for (var i = 0; i < videoOverlays.length; i++) {
        final overlay = videoOverlays[i];
        inputArgs.addAll([
          '-ss', overlay.inPoint.toStringAsFixed(3),
          '-to', overlay.outPoint.toStringAsFixed(3),
          '-i', overlay.sourcePath,
        ]);
        final voInput = nextInputIndex++;

        final isBlend = overlay.blendMode != 'normal';
        final scaledLabel = '[vosc$i]';
        final scaleExpr = isBlend
            ? '$canvasWidth:$canvasHeight'
            : '${_evenPx(canvasWidth * overlay.scale)}:-2';
        filter.write(';[$voInput:v:0]format=rgba,setpts=PTS-STARTPTS+'
            '${_fmtFilterNum(overlay.startTime)}/TB,scale=$scaleExpr'
            '$scaledLabel');

        var overlayPad = scaledLabel;
        if (!isBlend && overlay.rotation != 0) {
          final radians = overlay.rotation * 3.141592653589793 / 180.0;
          final rotLabel = '[vorot$i]';
          filter.write(';${overlayPad}rotate=${_fmtFilterNum(radians)}:'
              'ow=rotw(${_fmtFilterNum(radians)}):'
              'oh=roth(${_fmtFilterNum(radians)}):c=none$rotLabel');
          overlayPad = rotLabel;
        }

        final opacity = overlay.opacity.clamp(0.0, 1.0);
        if (!isBlend && opacity < 1.0) {
          final opLabel = '[voop$i]';
          filter.write(
              ';${overlayPad}colorchannelmixer=aa=${_fmtFilterNum(opacity)}$opLabel');
          overlayPad = opLabel;
        }

        final windowEnd = overlay.startTime + overlay.duration;
        final enable =
            "enable='between(t,${overlay.startTime.toStringAsFixed(3)},"
            "${windowEnd.toStringAsFixed(3)})'";
        final nextLabel = '[vo$i]';
        if (isBlend) {
          filter.write(';$videoLabel${overlayPad}blend=all_mode=${overlay.blendMode}:'
              'all_opacity=${_fmtFilterNum(opacity)}:$enable$nextLabel');
        } else {
          filter.write(';$videoLabel${overlayPad}overlay=x='
              "'main_w*${_fmtFilterNum(overlay.posX)}-overlay_w/2':y="
              "'main_h*${_fmtFilterNum(overlay.posY)}-overlay_h/2':$enable$nextLabel");
        }
        videoLabel = nextLabel;

        // Only reference this overlay's `:a:0` pad if its source actually
        // has one — referencing a stream specifier that matches nothing
        // aborts the *entire* filtergraph (`Stream specifier ... matches no
        // streams`), so a video-only overlay must never be wired into the
        // amix below.
        if (await _probeHasAudio(overlay.sourcePath)) {
          final alabel = 'voa$i';
          final delayMs =
              (overlay.startTime * 1000).clamp(0, double.infinity).round();
          filter.write(';[$voInput:a:0]adelay=$delayMs:all=1[$alabel]');
          overlayAudioLabels.add(alabel);
        }
      }

      // Mix in the project's audio lane: each AudioClip gets its own input
      // (trimmed the same way a video clip's is, via -ss/-to), a
      // volume/fade chain, then `adelay` to place it at its `start` on the
      // final timeline, then one `amix` combines all of them with the main
      // joined audio. `adelay=...:all=1` applies the same delay to every
      // channel without needing to know the source's channel count up front.
      // Fully additive: empty `audioClips` and `videoOverlays` (both default
      // to empty) never write any of this, so `audioLabel` stays exactly
      // `[${joined.audio}]` — the graph export/renderPreview already produced
      // before either feature existed.
      var audioLabel = '[${joined.audio}]';
      if (audioClips.isNotEmpty || overlayAudioLabels.isNotEmpty) {
        final mixLabels = <String>[joined.audio];
        for (var i = 0; i < audioClips.length; i++) {
          final ac = audioClips[i];
          inputArgs.addAll([
            '-ss', ac.inPoint.toStringAsFixed(3),
            '-to', ac.outPoint.toStringAsFixed(3),
            '-i', ac.sourcePath,
          ]);
          final srcIndex = nextInputIndex++;
          final chain = <String>[
            ?_audioClipFilterChain(ac),
            'adelay=${(ac.start * 1000).clamp(0, double.infinity).round()}:all=1',
          ];
          final label = 'mixa$i';
          filter.write(';[$srcIndex:a:0]${chain.join(',')}[$label]');
          mixLabels.add(label);
        }
        // The video-overlay stage above already built each overlay's own
        // delayed audio pad (if its source has one) — just fold them in.
        mixLabels.addAll(overlayAudioLabels);
        final mixedLabel = 'outmix';
        // `duration=longest` so a music track longer than the video keeps
        // playing to its end (the video is padded to match, below) instead of
        // being cut when the main clip audio runs out.
        filter.write(
            ';${mixLabels.map((l) => '[$l]').join()}amix=inputs=${mixLabels.length}:duration=longest:normalize=0[$mixedLabel]');
        audioLabel = '[$mixedLabel]';
      }

      // If the audio lane or an overlay runs past the last video clip, pad the
      // video track with black to the full timeline length so that extra
      // audio/overlay time is kept (the amix above already uses
      // duration=longest). No-op when the video is the longest track.
      final videoSum = clips.fold<double>(0, (s, c) => s + c.duration);
      if (timelineDuration - videoSum > 0.01) {
        final outLabel = '[vpad]';
        filter.write(';${videoLabel}tpad=stop_duration='
            '${_fmtFilterNum(timelineDuration - videoSum)}$outLabel');
        videoLabel = outLabel;
      }

      // Optional resize LAST — after captions and every overlay have
      // composited against the full-resolution canvas pad. A `renderPreview`
      // passes a downscale here (`scale=640:-2`) to render a fast proxy; an
      // export passes whatever its [ExportSettings] resolution needs (often
      // nothing). Applying it earlier would shrink the pad before overlays,
      // throwing off every pixel-sized sticker/PiP overlay above.
      if (scaleFilter != null) {
        final outLabel = '[vsfinal]';
        filter.write(';$videoLabel$scaleFilter$outLabel');
        videoLabel = outLabel;
      }

      return _FilterGraph(
        inputArgs: inputArgs,
        filterComplex: filter.toString(),
        videoLabel: videoLabel,
        audioLabel: audioLabel,
        tempFiles: [?srtFile, ...overlayFiles],
      );
    } catch (_) {
      // Building the graph failed partway (e.g. a temp-file write error) —
      // clean up whatever was already written before letting the error
      // surface, same best-effort spirit as the success-path cleanup.
      await _deleteAll([?srtFile, ...overlayFiles]);
      rethrow;
    }
  }

  // ── transition ──

  /// Joins every clip's per-clip video/audio pad (already transformed by
  /// [_videoFilterChain]/[_audioFilterChain]/speed, in [videoLabels] /
  /// [audioLabels], same order as [clips]) into a single video + audio pad,
  /// writing the join filters into [filter] and returning the final (bare,
  /// unbracketed) pad labels.
  ///
  /// Fast path: if no clip has a [Clip.transitionId], this is byte-for-byte
  /// the original graph — one N-ary `concat` filter — so a timeline with no
  /// transitions exports identically to before this feature existed.
  ///
  /// Otherwise, clips are folded left-to-right into a single running pad: a
  /// clip with a transition is joined to the running pad with ffmpeg's
  /// `xfade` (video) + `acrossfade` (audio) instead of `concat`; a clip
  /// without one is still joined with (a binary) `concat`. `concat` and
  /// `xfade` boundaries can be freely mixed on the same timeline — each step
  /// only needs to know the running pad's current duration so far (tracked in
  /// Dart alongside the graph), which is unaffected by what kind of join
  /// produced it.
  ///
  /// `xfade`'s `offset` (when, on the running pad, the transition starts)
  /// is the running duration minus the transition's own duration; after an
  /// `xfade` join the running duration shrinks by the transition duration
  /// (the two clips overlap during it), while after a `concat` join it is
  /// simply the sum (no overlap).
  _JoinResult _joinClips(
    StringBuffer filter,
    List<Clip> clips,
    List<String> videoLabels,
    List<String> audioLabels,
  ) {
    if (!clips.any((c) => c.transitionId != null)) {
      for (var i = 0; i < clips.length; i++) {
        filter.write('[${videoLabels[i]}][${audioLabels[i]}]');
      }
      filter.write('concat=n=${clips.length}:v=1:a=1[vcat][outa]');
      return const _JoinResult(video: 'vcat', audio: 'outa');
    }

    // Built in a local buffer (rather than writing straight into [filter])
    // so the trailing ';' separator between clauses can be stripped off the
    // very last one before it's appended — same convention the fast path
    // above (and every other stage of this graph) relies on: a stage either
    // ends the whole filter_complex, or a later stage prepends its own ';'.
    final local = StringBuffer();
    var runningVideo = videoLabels[0];
    var runningAudio = audioLabels[0];
    var runningDuration = clips[0].duration;
    for (var i = 1; i < clips.length; i++) {
      final clip = clips[i];
      final nextVideo = videoLabels[i];
      final nextAudio = audioLabels[i];
      final outVideo = 'jv$i';
      final outAudio = 'ja$i';
      if (clip.transitionId != null) {
        // Clamp so `duration` never exceeds either side's own length (an
        // overlap longer than a clip would make `offset` negative or the
        // overlap ill-defined) — floor of 0.05s keeps it a real transition.
        final maxDuration =
            (runningDuration < clip.duration ? runningDuration : clip.duration) *
                0.9;
        final duration = clip.transitionDuration
            .clamp(0.05, maxDuration < 0.05 ? 0.05 : maxDuration);
        final offset = (runningDuration - duration).clamp(0.0, double.infinity);
        final xfadeType = xfadeTransitionFor(clip.transitionId!);
        // `xfade` requires both inputs to share a timebase. Every per-clip
        // chain already runs at a constant `_canvasFps` (via the `color=`
        // source in `_videoFilterChain`), but a `concat` filter's output pad
        // has a different, generic timebase — so if the running pad came out
        // of a `concat` join, feeding it straight into `xfade` fails with
        // "timebase ... do not match". Re-asserting `fps=$_canvasFps` on both
        // sides right before every `xfade` is a no-op for an already-correct
        // timebase and fixes it otherwise, regardless of which kind of join
        // produced the running pad.
        final normRunning = 'xn${i}a';
        final normNext = 'xn${i}b';
        local.write('[$runningVideo]fps=$_canvasFps[$normRunning];');
        local.write('[$nextVideo]fps=$_canvasFps[$normNext];');
        local.write('[$normRunning][$normNext]xfade=transition=$xfadeType:'
            'duration=${_fmtFilterNum(duration)}:offset=${_fmtFilterNum(offset)}'
            '[$outVideo];');
        local.write(
            '[$runningAudio][$nextAudio]acrossfade=d=${_fmtFilterNum(duration)}[$outAudio];');
        runningDuration = runningDuration + clip.duration - duration;
      } else {
        local.write('[$runningVideo][$runningAudio][$nextVideo][$nextAudio]'
            'concat=n=2:v=1:a=1[$outVideo][$outAudio];');
        runningDuration += clip.duration;
      }
      runningVideo = outVideo;
      runningAudio = outAudio;
    }
    final clauses = local.toString();
    filter.write(
        clauses.endsWith(';') ? clauses.substring(0, clauses.length - 1) : clauses);
    return _JoinResult(video: runningVideo, audio: runningAudio);
  }

  /// Runs ffmpeg with [args], forwarding `-progress pipe:1` output as a 0..1
  /// fraction of [totalDuration] to [onProgress], and throws
  /// [EngineException] (worded with [action], e.g. `'export'`) if it exits
  /// non-zero. On success, calls `onProgress(1)` once.
  Future<void> _runFfmpeg(
    List<String> args, {
    required double totalDuration,
    required String action,
    void Function(double progress)? onProgress,
  }) async {
    if (Platform.environment['MOZCUT_DUMP_FFMPEG'] == '1') {
      // ignore: avoid_print
      print('[$action] $_ffmpeg ${args.join(' ')}');
    }
    final process = await Process.start(_ffmpeg, args);

    // ffmpeg prints `out_time_ms=...` lines on stdout with -progress.
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (onProgress == null || totalDuration <= 0) return;
      if (line.startsWith('out_time_ms=')) {
        final us =
            int.tryParse(line.substring('out_time_ms='.length).trim());
        if (us != null) {
          onProgress((us / 1e6 / totalDuration).clamp(0.0, 1.0));
        }
      }
    });

    final stderr = StringBuffer();
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(stderr.write);

    final code = await process.exitCode;
    if (code != 0) {
      throw EngineException('ffmpeg $action failed (exit $code):\n$stderr');
    }
    onProgress?.call(1);
  }

  /// Best-effort deletes every file in [files], ignoring individual failures.
  static Future<void> _deleteAll(List<File> files) async {
    for (final file in files) {
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  /// Builds a single .srt covering all [clips] in order, shifting each
  /// clip's (clip-relative) caption timings by the cumulative duration of the
  /// clips before it — i.e. onto the timeline of the final concatenated
  /// export.
  static String _buildSrt(List<Clip> clips) {
    final buffer = StringBuffer();
    var offset = 0.0;
    var index = 1;
    for (final clip in clips) {
      for (final caption in clip.captions) {
        final start = offset + caption.start;
        final end = offset + caption.end;
        if (end > start) {
          buffer
            ..writeln(index++)
            ..writeln(
                '${formatSrtTimestamp(start)} --> ${formatSrtTimestamp(end)}')
            ..writeln(caption.text)
            ..writeln();
        }
      }
      offset += clip.duration;
    }
    return buffer.toString();
  }

  /// Decomposes an arbitrary speed factor into a chain of `atempo` filter
  /// values, since ffmpeg's `atempo` filter only accepts values in the range
  /// [0.5, 2.0]. The product of the returned factors equals [speed].
  static List<double> _atempoChain(double speed) {
    final factors = <double>[];
    var remaining = speed;
    while (remaining > 2.0) {
      factors.add(2.0);
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      factors.add(0.5);
      remaining /= 0.5;
    }
    if (factors.isEmpty || (remaining - 1.0).abs() > 1e-9) {
      factors.add(remaining);
    }
    return factors;
  }

  /// Formats a number for embedding in an ffmpeg filtergraph expression —
  /// fixed-point, so floating point division never produces scientific
  /// notation (which ffmpeg's filter parser rejects).
  static String _fmtFilterNum(double value) => value.toStringAsFixed(6);

  /// The timeline's total length in seconds: the longest of the video track
  /// (the clips, laid end to end), the audio lane, and the overlay (PiP) lane.
  /// A long music track or a late overlay keeps playing past the last video
  /// clip (the video track just shows black for the remainder), matching
  /// CapCut — rather than the whole export ending when the video does.
  static double _timelineDurationOf(
    List<Clip> clips,
    List<AudioClip> audioClips,
    List<VideoOverlay> videoOverlays,
  ) {
    var d = clips.fold<double>(0, (s, c) => s + c.duration);
    for (final a in audioClips) {
      final end = a.start + a.duration;
      if (end > d) d = end;
    }
    for (final o in videoOverlays) {
      final end = o.startTime + o.duration;
      if (end > d) d = end;
    }
    return d;
  }

  /// Rounds [px] to the nearest even integer ≥ 2 — a size in whole pixels
  /// safe to hand to `scale`/`overlay` (H.264 and most filters want even
  /// dimensions, and a degenerate 0 would abort the graph).
  static int _evenPx(double px) {
    final n = px.round();
    final even = n - (n % 2);
    return even < 2 ? 2 : even;
  }

  /// Escapes a filesystem path for safe use inside an ffmpeg filtergraph
  /// option string (colons, backslashes and quotes are all filtergraph
  /// syntax), then wraps it in single quotes.
  static String _escapeFilterPath(String path) {
    final escaped = path
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
    return "'$escaped'";
  }

  /// Writes clip [i]'s transform filter chain into [filter] and returns the
  /// output pad label (without brackets) to feed into concat. [i] only names
  /// this clip's intermediate labels (`bg$i`/`fg$i`/`v$i`) — the actual ffmpeg
  /// input to read video from is [inputIndex] (`[$inputIndex:v:0]`), which
  /// differs from [i] once an earlier clip is an image (see
  /// `_buildFilterGraph`'s `videoInputIndex`/`audioInputIndex` bookkeeping).
  /// [canvasWidth]/[canvasHeight] are the project's output canvas (its aspect
  /// ratio) — every clip is fit ("contain") into this size before
  /// composition.
  String _videoFilterChain(StringBuffer filter, int i, int inputIndex,
      Clip clip, int canvasWidth, int canvasHeight) {
    final bg = 'bg$i';
    final fg = 'fg$i';
    final out = 'v$i';

    // Keyframes for the four animatable transform properties (see
    // domain/models/keyframe.dart and docs/CAPCUT-SPEC.md §2.6). A list with
    // fewer than 2 entries can't be "animated" (0 = use the clip's own
    // field; 1 = that single keyframe just pins a constant value) — only
    // those get a real time-based ffmpeg expression. This is what keeps an
    // unanimated clip's filtergraph byte-identical to before this feature
    // existed.
    final kfScale = clip.keyframes[kKeyframeScale] ?? const <Keyframe>[];
    final kfPosX = clip.keyframes[kKeyframePosX] ?? const <Keyframe>[];
    final kfPosY = clip.keyframes[kKeyframePosY] ?? const <Keyframe>[];
    final kfRotation = clip.keyframes[kKeyframeRotation] ?? const <Keyframe>[];
    final kfOpacity = clip.keyframes[kKeyframeOpacity] ?? const <Keyframe>[];

    // 1. A black canvas-sized background. `color` is a zero-input source
    // filter — no extra `-i` needed. It's infinite; `overlay`'s shortest=1
    // below trims the result to the (finite) foreground's duration.
    filter.write(
      'color=c=black:s=${canvasWidth}x$canvasHeight:r=$_canvasFps[$bg];',
    );

    // 2. Foreground: fit into the canvas ("contain", preserving aspect
    // ratio — ffmpeg computes this from the real source size at run time,
    // so no probing of pixel dimensions is needed here), then the clip's
    // own `scale` on top of that fit, then flip/rotate.
    final steps = <String>[
      'scale=w=$canvasWidth:h=$canvasHeight:force_original_aspect_ratio=decrease',
    ];
    if (kfScale.length < 2) {
      // trunc(.../2)*2 keeps dimensions even, which libx264 requires.
      final scaleValue = kfScale.isEmpty ? clip.scale : kfScale.single.value;
      steps.add(
        "scale=w='trunc(iw*$scaleValue/2)*2':h='trunc(ih*$scaleValue/2)*2'",
      );
    } else {
      // `eval=frame` makes ffmpeg re-evaluate w/h (and therefore resize)
      // every frame instead of once at init — confirmed against a real
      // ffmpeg build (8.0) that `overlay` downstream handles a per-frame
      // varying foreground size correctly (it re-centers on the current
      // frame's w/h each time, same as it already does for a static size).
      final expr = _piecewiseTimeExpr(kfScale, 't');
      steps.add(
        "scale=w='trunc(iw*($expr)/2)*2':h='trunc(ih*($expr)/2)*2':eval=frame",
      );
    }
    if (clip.flipH) steps.add('hflip');
    if (kfRotation.length < 2) {
      final degrees = kfRotation.isEmpty ? clip.rotation : kfRotation.single.value;
      if (degrees != 0) {
        final radians = degrees * 3.141592653589793 / 180.0;
        // Expands the bounding box to fit the rotated frame (rotw()/roth()
        // are ffmpeg's rotate-filter helper functions for exactly this —
        // the bare `rotw`/`roth` constants only exist inside them); the
        // corners this exposes are filled black, matching the background.
        steps.add(
            'rotate=$radians:ow=rotw($radians):oh=roth($radians):c=black');
      }
    } else {
      // rotw()/roth() can't self-reference an animated `a` expression (they
      // only resolve against a literal angle), so the bounding box is fixed
      // to the frame's diagonal instead — always big enough for any angle
      // the animation reaches, padded with black (matching the canvas
      // background) rather than cropping at some angles.
      final degExpr = _piecewiseTimeExpr(kfRotation, 't');
      const degToRad = 0.017453292519943295;
      steps.add(
        "rotate=a='($degExpr)*$degToRad':ow='hypot(iw,ih)':oh='hypot(iw,ih)':c=black",
      );
    }
    // ── color / filter ──
    // Preset look first (the "base grade"), then the user's manual
    // brightness/contrast/saturation tweaks on top — see
    // domain/models/color_filter_presets.dart for the preset -> ffmpeg
    // mapping. Both are no-ops by default, so a default clip produces
    // exactly the filter chain it did before this feature existed.
    final preset = clip.filterId == null
        ? null
        : kColorFilterPresets[clip.filterId];
    if (preset != null) {
      steps.add(preset.ffmpegFilterChainFor(clip.filterIntensity));
    }
    if (clip.brightness != 0.0 ||
        clip.contrast != 1.0 ||
        clip.saturation != 1.0) {
      steps.add('eq=brightness=${_fmtFilterNum(clip.brightness)}:'
          'contrast=${_fmtFilterNum(clip.contrast)}:'
          'saturation=${_fmtFilterNum(clip.saturation)}');
    }

    // ── effects ──
    // A single stylised effect (blur, distort, grain, etc.) picked from the
    // Effects panel, applied last so it renders on top of the colour grade —
    // see domain/models/effect_presets.dart for the effectId -> ffmpeg
    // mapping. No-op by default, so a default clip produces exactly the
    // filter chain it did before this feature existed.
    final effect =
        clip.effectId == null ? null : kEffectPresets[clip.effectId];
    if (effect != null) steps.add(effect(clip.effectIntensity));

    // ── opacity ──
    // Applied last, over the already colour/effect-graded frame. No-op by
    // default (opacity 1.0, no keyframes), so a default clip produces
    // exactly the filter chain it did before this feature existed.
    if (kfOpacity.length < 2) {
      final opacityValue =
          (kfOpacity.isEmpty ? clip.opacity : kfOpacity.single.value)
              .clamp(0.0, 1.0);
      if (opacityValue < 1.0) {
        // `colorchannelmixer=aa=` scales the alpha channel's gain — cheap
        // (no per-pixel expression evaluation) since the value never
        // changes within this clip.
        steps.add('format=yuva420p');
        steps.add('colorchannelmixer=aa=${_fmtFilterNum(opacityValue)}');
      }
    } else {
      // `colorchannelmixer`'s options aren't re-evaluated per frame, so a
      // genuinely time-varying alpha needs `geq` instead: it rebuilds the
      // frame pixel-by-pixel, but exposes `lum(X,Y)`/`cb(X,Y)`/`cr(X,Y)` to
      // pass the existing picture through unchanged while computing a fresh
      // alpha plane from `T` (geq's own per-pixel expression language uses
      // uppercase `T` for the frame time, unlike every other filter here).
      final expr = _piecewiseTimeExpr(kfOpacity, 'T');
      steps.add('format=yuva420p');
      steps.add(
        "geq=lum='lum(X,Y)':cb='cb(X,Y)':cr='cr(X,Y)':a='($expr)*255'",
      );
    }

    filter.write('[$inputIndex:v:0]${steps.join(',')}[$fg];');

    // 3. Composite the foreground onto the background, offset from center
    // by posX/posY (fractions of half the canvas size — see Clip's doc
    // comments). `overlay` clips anything outside the canvas automatically,
    // so a scale > 1 ("zoomed in") frame is cropped rather than erroring.
    final String offsetXExpr;
    if (kfPosX.length < 2) {
      final v = kfPosX.isEmpty ? clip.posX : kfPosX.single.value;
      offsetXExpr = '${v * canvasWidth / 2}';
    } else {
      offsetXExpr = '(${_piecewiseTimeExpr(kfPosX, 't')})*$canvasWidth/2';
    }
    final String offsetYExpr;
    if (kfPosY.length < 2) {
      final v = kfPosY.isEmpty ? clip.posY : kfPosY.single.value;
      offsetYExpr = '${v * canvasHeight / 2}';
    } else {
      offsetYExpr = '(${_piecewiseTimeExpr(kfPosY, 't')})*$canvasHeight/2';
    }
    filter.write(
      "[$bg][$fg]overlay=x='(W-w)/2+($offsetXExpr)':y='(H-h)/2+($offsetYExpr)':"
      "shortest=1,setsar=1,format=yuv420p[$out];",
    );

    return out;
  }

  /// Builds a piecewise-linear ffmpeg filtergraph expression reproducing
  /// [keyframeValueAt] for [keyframes] (which must have at least 2 entries —
  /// callers handle 0/1 as a static value instead), in terms of [timeVar]
  /// (the current filter's own time variable: lowercase `t` for
  /// `overlay`/`scale`/`rotate`, but uppercase `T` inside `geq`, whose
  /// per-pixel expression language reserves lowercase `t` for something
  /// else). Before the first keyframe / after the last, the value clamps
  /// (no extrapolation) — same semantics as [keyframeValueAt].
  static String _piecewiseTimeExpr(List<Keyframe> keyframes, String timeVar) {
    final sorted = List<Keyframe>.of(keyframes)
      ..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    var expr = _fmtFilterNum(sorted.last.value);
    for (var k = sorted.length - 2; k >= 0; k--) {
      final a = sorted[k];
      final b = sorted[k + 1];
      final span = b.timeSec - a.timeSec;
      final segment = span.abs() < 1e-9
          ? _fmtFilterNum(b.value)
          : '(${_fmtFilterNum(a.value)}+($timeVar-${_fmtFilterNum(a.timeSec)})'
              '*${_fmtFilterNum(b.value - a.value)}/${_fmtFilterNum(span)})';
      expr = 'if(lt($timeVar,${_fmtFilterNum(b.timeSec)}),$segment,$expr)';
    }
    return 'if(lt($timeVar,${_fmtFilterNum(sorted.first.timeSec)}),'
        '${_fmtFilterNum(sorted.first.value)},$expr)';
  }

  /// Builds the `volume`/`afade` filter chain for [clip]'s audio, or `null`
  /// if it is at the defaults (volume 1.0, no fades) and therefore needs no
  /// processing at all. Keeping the no-op case `null` (rather than e.g.
  /// `volume=1.0`) is what keeps [export] fully additive: a timeline of
  /// default clips produces the exact filtergraph it did before this feature
  /// existed.
  static String? _audioFilterChain(Clip clip) {
    final parts = <String>[];
    if (clip.volume != 1.0) {
      parts.add('volume=${clip.volume.toStringAsFixed(3)}');
    }
    if (clip.fadeIn > 0) {
      parts.add('afade=t=in:st=0:d=${clip.fadeIn.toStringAsFixed(3)}');
    }
    if (clip.fadeOut > 0) {
      final start =
          (clip.duration - clip.fadeOut).clamp(0, clip.duration);
      parts.add(
          'afade=t=out:st=${start.toStringAsFixed(3)}:d=${clip.fadeOut.toStringAsFixed(3)}');
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  /// Same idea as [_audioFilterChain] but for an [AudioClip] on the project's
  /// audio lane — volume/fades only (the `adelay` placing it on the final
  /// timeline is added separately by the caller, since it isn't part of
  /// "does this clip need any processing at all").
  static String? _audioClipFilterChain(AudioClip clip) {
    final parts = <String>[];
    if (clip.volume != 1.0) {
      parts.add('volume=${clip.volume.toStringAsFixed(3)}');
    }
    if (clip.fadeIn > 0) {
      parts.add('afade=t=in:st=0:d=${clip.fadeIn.toStringAsFixed(3)}');
    }
    if (clip.fadeOut > 0) {
      final start = (clip.duration - clip.fadeOut).clamp(0, clip.duration);
      parts.add(
          'afade=t=out:st=${start.toStringAsFixed(3)}:d=${clip.fadeOut.toStringAsFixed(3)}');
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  /// Probes whether [path] has at least one audio stream — used by the
  /// video-overlay stage of [_buildFilterGraph] to decide whether an
  /// overlay's `:a:0` pad may safely be referenced in the amix. Best-effort:
  /// any probe failure (unreadable file, no ffprobe, etc.) is treated as "no
  /// audio" rather than thrown, since the consequence is just that overlay
  /// losing its own sound — never worth failing the whole export over.
  Future<bool> _probeHasAudio(String path) async {
    try {
      final result = await Process.run(_ffprobe, [
        '-v', 'error',
        '-select_streams', 'a',
        '-show_entries', 'stream=index',
        '-of', 'csv=p=0',
        path,
      ]);
      return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Builds one `drawtext=...` filter clause (no surrounding `[in][out]`
  /// labels — the caller attaches those) for a single overlay.
  ///
  /// The overlay's text is read from [textFile] via drawtext's `textfile=`
  /// option rather than embedded inline — see the comment above the call
  /// site in [export] for why.
  ///
  /// Position: [TextOverlay.x]/[y] are fractions of the output frame, and the
  /// overlay's `alignment` only shifts where the text box sits relative to
  /// that anchor (left/center/right) — same idea as text-align in CSS.
  /// `fontsize` is left as an ffmpeg expression (`h*fraction`) rather than a
  /// literal number, so it is correct for whatever resolution this project
  /// exports at without Dart needing to know the output size.
  static String _drawtextFilter(
      TextOverlay overlay, File textFile, String? fontFile) {
    final xExpr = switch (overlay.alignment) {
      TextOverlayAlignment.left => '(w*${overlay.x})',
      TextOverlayAlignment.center => '(w*${overlay.x})-text_w/2',
      TextOverlayAlignment.right => '(w*${overlay.x})-text_w',
    };
    final parts = <String>[
      'drawtext=textfile=${_escapeFilterPath(textFile.path)}',
      if (fontFile != null) 'fontfile=${_escapeFilterPath(fontFile)}',
      'fontsize=h*${overlay.fontSize}',
      'fontcolor=${_ffColor(overlay.color)}',
      'x=$xExpr',
      'y=(h*${overlay.y})-text_h/2',
      // `expansion=none` stops drawtext from treating a lone '%' in the text
      // as the start of a `%{...}` template sequence — without it, titles
      // containing a literal '%' silently fail to render at all.
      'expansion=none',
      "enable='between(t,${overlay.start.toStringAsFixed(3)},${overlay.end.toStringAsFixed(3)})'",
    ];
    return parts.join(':');
  }

  /// Adapts a [StickerOverlay] into the [TextOverlay] shape [_drawtextFilter]
  /// expects, so sticker burn-in reuses the exact same drawtext/positioning
  /// logic as title burn-in (an emoji sticker's `x`/`y` are its anchor
  /// *center*, same as a center-aligned text overlay's).
  static TextOverlay _asTextOverlay(StickerOverlay sticker) => TextOverlay(
        text: sticker.emoji ?? '',
        start: sticker.start,
        end: sticker.end,
        fontSize: sticker.size,
        alignment: TextOverlayAlignment.center,
        x: sticker.x,
        y: sticker.y,
      );

  /// Resolves a usable TrueType font for `drawtext`, trying common system
  /// locations across macOS/Windows/Linux. Returns null if none is found —
  /// the caller then omits `fontfile` entirely and lets ffmpeg fall back to
  /// its own default (via fontconfig, where available) rather than crashing.
  static String? _resolveFont() {
    const candidates = [
      // macOS
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      // Linux (common distro paths)
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      // Windows
      'C:/Windows/Fonts/arial.ttf',
      'C:/Windows/Fonts/Arial.ttf',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Finds the system's bundled colour-emoji font, if any — the candidate
  /// [_resolveUsableEmojiFont] then *verifies* before trusting it. Unlike
  /// [_resolveFont]'s plain TrueType fonts, these carry actual coloured
  /// bitmap/COLR glyphs for emoji codepoints. Returns null if none of the
  /// known locations exist.
  static String? _resolveEmojiFont() {
    const candidates = [
      // macOS
      '/System/Library/Fonts/Apple Color Emoji.ttc',
      // Linux (common distro paths for the Noto colour-emoji font)
      '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
      '/usr/share/fonts/noto/NotoColorEmoji.ttf',
      // Windows
      'C:/Windows/Fonts/seguiemj.ttf',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Resolves a font for sticker burn-in that this machine's `ffmpeg` can
  /// actually rasterize, probing once and caching the result for the
  /// engine's lifetime (see [_emojiFontCache] / [_emojiFontProbed] — the
  /// probe below is a real process spawn, worth paying once, not once per
  /// sticker/export).
  ///
  /// This exists because "does a colour-emoji font exist on disk" (what
  /// [_resolveEmojiFont] answers) and "can *this* `ffmpeg` build actually
  /// draw it" are different questions, and getting that wrong doesn't
  /// degrade gracefully. Colour-emoji fonts like Apple Color Emoji embed
  /// fixed-size colour *bitmap* glyphs (not scalable outlines); whether
  /// `drawtext` can rasterize those depends on how the system's `ffmpeg` was
  /// built — its text rendering goes through libfreetype, and only builds
  /// with colour-bitmap support wired up can use them. Verified empirically
  /// against a stock Homebrew `ffmpeg` on macOS: pointing `fontfile` at
  /// `Apple Color Emoji.ttc` doesn't render a blank/monochrome glyph as a
  /// fallback, it fails to initialize the filter at all (`Could not set font
  /// size ... invalid library handle`, or `Monocromatic (1bpp) fonts are not
  /// supported`) and aborts the *entire* export — captions, titles, every
  /// clip, not just the sticker. So before trusting a colour-emoji candidate,
  /// this renders one throwaway frame with it; only on success is it used,
  /// otherwise this falls back to [_resolveFont]'s plain font (which won't
  /// show emoji as a coloured glyph, but reliably won't crash the graph
  /// either) — the actual "best-effort" in this feature's design.
  Future<String?> _resolveUsableEmojiFont() async {
    if (_emojiFontProbed) return _emojiFontCache;
    _emojiFontProbed = true;
    final candidate = _resolveEmojiFont();
    _emojiFontCache = (candidate != null && await _canDrawtextRender(candidate))
        ? candidate
        : _resolveFont();
    return _emojiFontCache;
  }

  /// Renders one throwaway frame with [fontFile] via `drawtext` to check
  /// whether this `ffmpeg`/libfreetype build can rasterize it at all, without
  /// touching any real project files. See [_resolveUsableEmojiFont].
  Future<bool> _canDrawtextRender(String fontFile) async {
    try {
      final result = await Process.run(_ffmpeg, [
        '-v', 'error',
        '-f', 'lavfi', '-i', 'color=c=black:s=64x64:d=0.1:r=1',
        '-vf',
        // A representative emoji codepoint — the actual failure mode above
        // happens trying to size/rasterize the glyph, not from anything
        // sticker-specific, so one probe covers every sticker.
        'drawtext=text=\u{1F600}:fontfile=${_escapeFilterPath(fontFile)}:'
            'fontsize=h*0.12:fontcolor=white',
        '-frames:v', '1',
        '-f', 'null', '-',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Converts a `#RRGGBB` (or `RRGGBB`) hex colour to the `0xRRGGBB` form
  /// ffmpeg's colour parser accepts. Anything that doesn't look like a hex
  /// triplet is passed through as-is (ffmpeg also accepts named colours like
  /// `white`).
  static String _ffColor(String color) {
    final hex = color.startsWith('#') ? color.substring(1) : color;
    final isHex = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
    return isHex ? '0x$hex' : color;
  }

  @override
  Future<void> savePoster({
    required Clip clip,
    required String outputPath,
    int width = 480,
  }) async {
    final result = await Process.run(_ffmpeg, [
      '-y',
      '-ss', clip.inPoint.toStringAsFixed(3),
      '-i', clip.sourcePath,
      '-frames:v', '1',
      '-vf', 'scale=$width:-2',
      outputPath,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('poster extraction failed: ${result.stderr}');
    }
  }

  @override
  Future<void> extractAudio({
    required Clip clip,
    required String outputPath,
  }) async {
    final result = await Process.run(_ffmpeg, [
      '-y',
      '-ss', clip.inPoint.toStringAsFixed(3),
      '-to', clip.outPoint.toStringAsFixed(3),
      '-i', clip.sourcePath,
      '-vn',
      outputPath,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('audio extraction failed: ${result.stderr}');
    }
  }

  @override
  Future<String> generateSfx(String id) async {
    final preset =
        kSfxPresets.where((p) => p.id == id).firstOrNull;
    if (preset == null) {
      throw EngineException('unknown sound effect: $id');
    }

    final dir = _mediaCacheDir();
    final outputPath = '${dir.path}/sfx_${preset.id}.wav';
    if (File(outputPath).existsSync()) return outputPath;

    final result =
        await Process.run(_ffmpeg, preset.buildArgs(outputPath));
    if (result.exitCode != 0 || !File(outputPath).existsSync()) {
      throw EngineException('sfx generation failed: ${result.stderr}');
    }
    return outputPath;
  }

  @override
  Future<String> generateShape(String id) async {
    final preset = kShapePresets.where((p) => p.id == id).firstOrNull;
    if (preset == null) {
      throw EngineException('unknown shape: $id');
    }

    final dir = _mediaCacheDir();
    final outputPath = '${dir.path}/shape_${preset.id}.png';
    if (File(outputPath).existsSync()) return outputPath;

    final result = await Process.run(_ffmpeg, preset.buildArgs(outputPath));
    if (result.exitCode != 0 || !File(outputPath).existsSync()) {
      throw EngineException('shape generation failed: ${result.stderr}');
    }
    return outputPath;
  }

  @override
  Future<List<String>> extractThumbnails({
    required Clip clip,
    required int count,
    int height = 64,
  }) async {
    if (count <= 0) return const [];
    final start = clip.inPoint.clamp(0.0, clip.sourceDuration);
    final end = clip.outPoint.clamp(0.0, clip.sourceDuration);
    final regionDuration = end - start;
    if (regionDuration <= 0) return const [];

    final dir = _mediaCacheDir();
    final key = _cacheKey([
      clip.sourcePath,
      start.toStringAsFixed(3),
      end.toStringAsFixed(3),
      height,
      count,
    ]);
    final prefix = 'thumb_$key';

    final cached = _existingSequence(dir, prefix, '.jpg', count);
    if (cached.isNotEmpty) return cached;

    // One ffmpeg call: resample the trimmed region to a constant
    // `count / duration` fps via the `fps` filter, so the N output frames
    // land evenly spaced across the region in a single pass — cheaper than
    // N separate `-ss` seeks and simpler than building a sprite sheet (which
    // would need an image-decoding dependency on the Dart side to slice back
    // apart). `-start_number 0` makes the numbered outputs predictable.
    final fps = count / regionDuration;
    final pattern = '${dir.path}/${prefix}_%04d.jpg';
    try {
      final result = await Process.run(_ffmpeg, [
        '-y',
        '-ss', start.toStringAsFixed(3),
        '-to', end.toStringAsFixed(3),
        '-i', clip.sourcePath,
        '-vf', 'fps=fps=${_fmtFilterNum(fps)},scale=-2:$height',
        '-frames:v', '$count',
        '-start_number', '0',
        pattern,
      ]);
      if (result.exitCode != 0) return const [];
    } catch (_) {
      return const [];
    }
    return _existingSequence(dir, prefix, '.jpg', count);
  }

  @override
  Future<String?> waveformPng({
    required Clip clip,
    required int width,
    int height = 40,
  }) async {
    if (width <= 0) return null;
    final start = clip.inPoint.clamp(0.0, clip.sourceDuration);
    final end = clip.outPoint.clamp(0.0, clip.sourceDuration);
    if (end - start <= 0) return null;

    final dir = _mediaCacheDir();
    final key = _cacheKey([
      clip.sourcePath,
      start.toStringAsFixed(3),
      end.toStringAsFixed(3),
      width,
      height,
    ]);
    final outputPath = '${dir.path}/wave_$key.png';
    if (File(outputPath).existsSync()) return outputPath;

    try {
      final result = await Process.run(_ffmpeg, [
        '-y',
        '-ss', start.toStringAsFixed(3),
        '-to', end.toStringAsFixed(3),
        '-i', clip.sourcePath,
        // `showwavespic` draws the whole clip as one static image (unlike
        // `showwaves`, which is a video filter meant for real-time
        // playback) — exactly the still strip the timeline needs. Mono
        // keeps stereo/5.1 sources to one waveform line rather than a lane
        // per channel.
        '-filter_complex',
        'aformat=channel_layouts=mono,'
            'showwavespic=s=${width}x$height:colors=${_ffColor(_waveformColor)}',
        '-frames:v', '1',
        outputPath,
      ]);
      // Non-zero here is almost always "no audio stream" (or an otherwise
      // unreadable source) — best-effort, so the timeline just omits the
      // waveform strip rather than surfacing an error.
      if (result.exitCode != 0 || !File(outputPath).existsSync()) return null;
      return outputPath;
    } catch (_) {
      return null;
    }
  }

  /// Colour used for the timeline waveform strip — matches `AppColors.accent`
  /// (kept as a literal here so the engine layer stays UI-token-free).
  static const _waveformColor = '#0568FD';

  /// Cache directory for filmstrip thumbnails and waveform PNGs, created on
  /// first use. Lives under the system temp dir (rather than
  /// `getApplicationSupportDirectory()`) so this stays a plain, synchronous,
  /// no-plugin-dependency helper — same spirit as [renderPreview]'s temp
  /// output file.
  static Directory _mediaCacheDir() {
    final dir = Directory('${Directory.systemTemp.path}/mozcut-thumb-cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// A stable (not [Object.hashCode]-based — that's randomized per isolate in
  /// Dart, so it would make the cache miss on every process restart) hash of
  /// [parts] used to name cache files deterministically. FNV-1a over the
  /// parts joined with a separator that can't appear inside any one part's
  /// own `toString()` (seconds/counts are numeric; the path may contain '|',
  /// but a collision there would require two different inputs to hash to the
  /// very same key, not just the same joined string — astronomically
  /// unlikely for a 64-bit hash).
  static String _cacheKey(List<Object> parts) {
    const fnvPrime = 0x100000001b3;
    var hash = 0xcbf29ce484222325;
    for (final unit in parts.join('|').codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFFFFFFFFFF;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Returns the existing cached `{prefix}_0000.{ext}` .. `{prefix}_{count-1
  /// (zero-padded)}.{ext}` file paths in [dir], or an empty list if any of
  /// them is missing (a partial cache from an interrupted run is treated as
  /// no cache at all, so it's regenerated in full).
  static List<String> _existingSequence(
      Directory dir, String prefix, String ext, int count) {
    final files = <String>[];
    for (var i = 0; i < count; i++) {
      final path =
          '${dir.path}/${prefix}_${i.toString().padLeft(4, '0')}$ext';
      if (!File(path).existsSync()) return const [];
      files.add(path);
    }
    return files;
  }
}

/// The pieces of an ffmpeg invocation produced by
/// [FfmpegEngine._buildFilterGraph], shared by [FfmpegEngine.export] and
/// [FfmpegEngine.renderPreview]: the per-clip `-i` input args, the
/// `-filter_complex` graph string, the final video/audio pad labels to
/// `-map` (brackets included, e.g. `[vt0]` / `[outa]`), and any temp files
/// the graph depends on (captions .srt, overlay text files) that the caller
/// must delete once its ffmpeg process has exited.
class _FilterGraph {
  _FilterGraph({
    required this.inputArgs,
    required this.filterComplex,
    required this.videoLabel,
    required this.audioLabel,
    required this.tempFiles,
  });

  final List<String> inputArgs;
  final String filterComplex;
  final String videoLabel;
  final String audioLabel;
  final List<File> tempFiles;
}

/// The final (bare, unbracketed) video/audio pad labels produced by
/// [FfmpegEngine._joinClips].
class _JoinResult {
  const _JoinResult({required this.video, required this.audio});
  final String video;
  final String audio;
}
