import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/caption.dart';
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

      final filter = StringBuffer();
      for (var i = 0; i < clips.length; i++) {
        filter.write('[$i:v:0][$i:a:0]');
      }
      filter.write('concat=n=${clips.length}:v=1:a=1[v0][outa]');

      var videoLabel = '[v0]';
      if (srtFile != null) {
        filter.write(';[v0]subtitles=${_escapeFilterPath(srtFile.path)}[v1]');
        videoLabel = '[v1]';
      }

      args.addAll([
        '-filter_complex', filter.toString(),
        '-map', videoLabel,
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
