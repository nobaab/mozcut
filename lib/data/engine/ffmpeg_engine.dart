import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/caption.dart';
import '../../domain/models/clip.dart';
import '../../domain/models/export_settings.dart';
import '../../domain/models/text_overlay.dart';
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

  // The engine interface doesn't (yet) carry the project's VideoSettings, so
  // export assumes the standard 1920x1080 canvas every clip's transform is
  // expressed against. When Engine.export grows a `VideoSettings` parameter,
  // thread it through here instead of this constant.
  static const _canvasWidth = 1920;
  static const _canvasHeight = 1080;
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
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    final totalDuration =
        clips.fold<double>(0, (sum, c) => sum + c.duration);

    final graph = await _buildFilterGraph(
      clips: clips,
      textOverlays: textOverlays,
      scaleFilter: settings.scaleFilter,
    );
    try {
      // One ffmpeg call: each clip is an input trimmed with -ss/-to, then the
      // concat filter joins them. Re-encoding (not stream copy) so clips with
      // different codecs/resolutions still join cleanly — correctness over
      // speed for v0.1.
      final args = <String>[
        '-y',
        ...graph.inputArgs,
        '-filter_complex', graph.filterComplex,
        '-map', graph.videoLabel,
        '-map', graph.audioLabel,
        ...settings.toFfmpegArgs(),
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
  Future<String> renderPreview({
    required List<Clip> clips,
    List<TextOverlay> textOverlays = const [],
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to preview — the timeline is empty.');
    }

    final totalDuration =
        clips.fold<double>(0, (sum, c) => sum + c.duration);
    final outputPath =
        '${Directory.systemTemp.path}/mozcut_preview_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Same filtergraph as export() (via _buildFilterGraph) so the preview is
    // never out of sync with the real edit — just scaled down and encoded for
    // speed instead of quality.
    final graph = await _buildFilterGraph(
      clips: clips,
      textOverlays: textOverlays,
      scaleFilter: 'scale=$_previewWidth:-2',
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
  /// per entry in [textOverlays]. Factored out of `export` so the two call
  /// sites can never drift — this is exactly the graph `export` built inline
  /// before [renderPreview] existed.
  ///
  /// Returns the pieces still needed to assemble a full ffmpeg invocation,
  /// plus any temp files (captions .srt, overlay text files) the caller must
  /// delete once its ffmpeg process has exited.
  Future<_FilterGraph> _buildFilterGraph({
    required List<Clip> clips,
    required List<TextOverlay> textOverlays,
    String? scaleFilter,
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

      final inputArgs = <String>[];
      for (final clip in clips) {
        inputArgs.addAll([
          '-ss', clip.inPoint.toStringAsFixed(3),
          '-to', clip.outPoint.toStringAsFixed(3),
          '-i', clip.sourcePath,
        ]);
      }

      // Per clip: transform (scale/pos/rotate/flip) on video, speed (setpts +
      // atempo), then audio volume/fades — then concat, then burn captions.
      // Every step is additive: a default clip reproduces the old graph exactly.
      final filter = StringBuffer();
      final videoLabels = <String>[];
      final audioLabels = <String>[];
      for (var i = 0; i < clips.length; i++) {
        final clip = clips[i];
        var vlabel = _videoFilterChain(filter, i, clip); // label, no brackets
        var alabel = '$i:a:0';
        if (clip.speed != 1.0) {
          filter.write(
              '[$vlabel]setpts=PTS/${_fmtFilterNum(clip.speed)}[sv$i];');
          vlabel = 'sv$i';
          final atempo = _atempoChain(clip.speed)
              .map((f) => 'atempo=${_fmtFilterNum(f)}')
              .join(',');
          filter.write('[$i:a:0]$atempo[sa$i];');
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
      for (var i = 0; i < clips.length; i++) {
        filter.write('[${videoLabels[i]}][${audioLabels[i]}]');
      }
      filter.write('concat=n=${clips.length}:v=1:a=1[vcat][outa]');

      // Chain optional stages (resize, then subtitles) onto the concat
      // output, each writing to a fresh label so the filtergraph stays a
      // simple linear pipe no matter which stages are present.
      var videoLabel = '[vcat]';
      var nextLabelIndex = 1;
      if (scaleFilter != null) {
        final outLabel = '[vs$nextLabelIndex]';
        filter.write(';$videoLabel$scaleFilter$outLabel');
        videoLabel = outLabel;
        nextLabelIndex++;
      }
      if (srtFile != null) {
        final outLabel = '[vs$nextLabelIndex]';
        filter.write(
            ';${videoLabel}subtitles=${_escapeFilterPath(srtFile.path)}$outLabel');
        videoLabel = outLabel;
        nextLabelIndex++;
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

      return _FilterGraph(
        inputArgs: inputArgs,
        filterComplex: filter.toString(),
        videoLabel: videoLabel,
        audioLabel: '[outa]',
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
  /// output pad label (without brackets) to feed into concat.
  String _videoFilterChain(StringBuffer filter, int i, Clip clip) {
    final bg = 'bg$i';
    final fg = 'fg$i';
    final out = 'v$i';

    // 1. A black canvas-sized background. `color` is a zero-input source
    // filter — no extra `-i` needed. It's infinite; `overlay`'s shortest=1
    // below trims the result to the (finite) foreground's duration.
    filter.write(
      'color=c=black:s=${_canvasWidth}x$_canvasHeight:r=$_canvasFps[$bg];',
    );

    // 2. Foreground: fit into the canvas ("contain", preserving aspect
    // ratio — ffmpeg computes this from the real source size at run time,
    // so no probing of pixel dimensions is needed here), then the clip's
    // own `scale` on top of that fit, then flip/rotate.
    final steps = <String>[
      'scale=w=$_canvasWidth:h=$_canvasHeight:force_original_aspect_ratio=decrease',
      // trunc(.../2)*2 keeps dimensions even, which libx264 requires.
      "scale=w='trunc(iw*${clip.scale}/2)*2':h='trunc(ih*${clip.scale}/2)*2'",
    ];
    if (clip.flipH) steps.add('hflip');
    if (clip.rotation != 0) {
      final radians = clip.rotation * 3.141592653589793 / 180.0;
      // Expands the bounding box to fit the rotated frame (rotw()/roth()
      // are ffmpeg's rotate-filter helper functions for exactly this —
      // the bare `rotw`/`roth` constants only exist inside them); the
      // corners this exposes are filled black, matching the background.
      steps.add('rotate=$radians:ow=rotw($radians):oh=roth($radians):c=black');
    }
    filter.write('[$i:v:0]${steps.join(',')}[$fg];');

    // 3. Composite the foreground onto the background, offset from center
    // by posX/posY (fractions of half the canvas size — see Clip's doc
    // comments). `overlay` clips anything outside the canvas automatically,
    // so a scale > 1 ("zoomed in") frame is cropped rather than erroring.
    final offsetX = clip.posX * _canvasWidth / 2;
    final offsetY = clip.posY * _canvasHeight / 2;
    filter.write(
      "[$bg][$fg]overlay=x='(W-w)/2+($offsetX)':y='(H-h)/2+($offsetY)':"
      "shortest=1,setsar=1,format=yuv420p[$out];",
    );

    return out;
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
