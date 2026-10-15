import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/caption.dart';
import '../../domain/models/clip.dart';
import '../../domain/models/export_settings.dart';
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
    ExportSettings settings = const ExportSettings(),
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    final totalDuration =
        clips.fold<double>(0, (sum, c) => sum + c.duration);

    // If any clip carries captions, burn them into the output via ffmpeg's
    // `subtitles` filter, fed from a temp .srt built from all clips' caption
    // lists with their timing shifted onto the final, concatenated timeline.
    // Keep this fully additive: no captions anywhere means no subtitles
    // filter and export behaves exactly as before.
    File? srtFile;
    if (clips.any((c) => c.captions.isNotEmpty)) {
      srtFile = File(
          '${Directory.systemTemp.path}/vidkaat_captions_${DateTime.now().millisecondsSinceEpoch}.srt');
      await srtFile.writeAsString(_buildSrt(clips));
    }

    try {
      // One ffmpeg call: each clip is an input trimmed with -ss/-to, then the
      // concat filter joins them. Re-encoding (not stream copy) so clips with
      // different codecs/resolutions still join cleanly — correctness over
      // speed for v0.1.
      final args = <String>['-y'];
      for (final clip in clips) {
        args.addAll([
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

      // Chain optional stages (scale from export settings, then subtitles) onto
      // the concat output, each writing to a fresh label so the filtergraph
      // stays a simple linear pipe no matter which stages are present.
      var videoLabel = '[vcat]';
      var nextLabelIndex = 1;
      final scaleFilter = settings.scaleFilter;
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

      args.addAll([
        '-filter_complex', filter.toString(),
        '-map', videoLabel,
        '-map', '[outa]',
        ...settings.toFfmpegArgs(),
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
        throw EngineException('ffmpeg export failed (exit $code):\n$stderr');
      }
      onProgress?.call(1);
    } finally {
      if (srtFile != null && srtFile.existsSync()) {
        try {
          await srtFile.delete();
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
