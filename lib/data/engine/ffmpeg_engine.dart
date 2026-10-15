import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/clip.dart';
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
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    final totalDuration =
        clips.fold<double>(0, (sum, c) => sum + c.duration);

    // One ffmpeg call: each clip is an input trimmed with -ss/-to, then the
    // concat filter joins them. Re-encoding (not stream copy) so clips with
    // different codecs/resolutions still join cleanly — correctness over speed
    // for v0.1.
    final args = <String>['-y'];
    for (final clip in clips) {
      args.addAll([
        '-ss', clip.inPoint.toStringAsFixed(3),
        '-to', clip.outPoint.toStringAsFixed(3),
        '-i', clip.sourcePath,
      ]);
    }

    // Per-input filter chain applying each clip's transform, then concat.
    //
    // Every clip (even an untouched one, scale=1/pos=0/rotation=0/no flip) is
    // run through the same chain so every input lands on the identical
    // `_canvasWidth`x`_canvasHeight` canvas before concat — concat requires
    // matching frame sizes, and source clips may not all share a resolution.
    //
    // Per clip this builds three filter-graph nodes (see _videoFilterChain):
    //   1. a solid black `color` source the size of the canvas (background).
    //   2. the clip scaled ("contain" fit, then the clip's own `scale`),
    //      flipped and/or rotated as requested.
    //   3. an `overlay` of (2) onto (1) at the `posX`/`posY` offset.
    // Using overlay (rather than `pad`) means a zoomed-in clip (scale > 1,
    // larger than the canvas) is simply cropped by the canvas edges instead
    // of making `pad` fail — the correct, expected behavior for a zoom.
    final filter = StringBuffer();
    final videoLabels = <String>[];
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final label = _videoFilterChain(filter, i, clip);
      videoLabels.add(label);
    }
    for (var i = 0; i < clips.length; i++) {
      filter.write('[${videoLabels[i]}][$i:a:0]');
    }
    filter.write('concat=n=${clips.length}:v=1:a=1[outv][outa]');

    args.addAll([
      '-filter_complex', filter.toString(),
      '-map', '[outv]',
      '-map', '[outa]',
      '-c:v', 'libx264',
      '-preset', 'medium',
      '-crf', '18',
      '-c:a', 'aac',
      '-progress', 'pipe:1',
      '-nostats',
      outputPath,
    ]);

    final process = await Process.start(_ffmpeg, args);

    // ffmpeg prints `out_time_ms=...` lines on stdout with -progress.
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (onProgress == null || totalDuration <= 0) return;
      if (line.startsWith('out_time_ms=')) {
        final us = int.tryParse(line.substring('out_time_ms='.length).trim());
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
      throw EngineException('ffmpeg export failed (exit $code):\n$stderr');
    }
    onProgress?.call(1);
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
}
