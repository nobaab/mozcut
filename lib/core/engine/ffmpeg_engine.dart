import 'dart:convert';
import 'dart:io';

import '../models/clip.dart';
import 'engine.dart';

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

    final filter = StringBuffer();
    for (var i = 0; i < clips.length; i++) {
      filter.write('[$i:v:0][$i:a:0]');
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
