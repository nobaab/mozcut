@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';

/// Up to [n] real video files from the user's Documents folder, so the test
/// doesn't depend on one hard-coded filename that may be deleted.
List<String> sampleVideos([int n = 2]) {
  final dir = Directory('/Users/nobaab/Documents');
  if (!dir.existsSync()) return const [];
  final vids = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.toLowerCase().endsWith('.mp4'))
      .toList()
    ..sort();
  return vids.take(n).toList();
}

/// Exercises the real FfmpegEngine against real files on disk.
/// Run with: flutter test test/engine_integration_test.dart
void main() {
  final engine = FfmpegEngine();
  final videos = sampleVideos(2);
  final skip =
      videos.length < 2 ? 'needs ≥2 .mp4 files in ~/Documents' : null;

  test('probeDuration reads real durations', () async {
    for (final v in videos) {
      expect(await engine.probeDuration(v), greaterThan(0));
    }
  }, skip: skip);

  test('probeDuration throws on a non-media file', () async {
    final junk = File('${Directory.systemTemp.path}/not_a_video.txt')
      ..writeAsStringSync('hello');
    expect(() => engine.probeDuration(junk.path), throwsException);
    junk.deleteSync();
  });

  test('export trims two clips and concats them into a valid MP4', () async {
    // Take a short slice from each source (clamped to its real duration).
    final clips = <Clip>[];
    for (final v in videos) {
      final dur = await engine.probeDuration(v);
      clips.add(Clip(
          sourcePath: v,
          sourceDuration: dur,
          inPoint: 0,
          outPoint: dur < 3 ? dur : 3));
    }
    final expected = clips.fold<double>(0, (s, c) => s + c.duration);

    final out =
        '${Directory.systemTemp.path}/mozcut_it_${DateTime.now().millisecondsSinceEpoch}.mp4';
    var lastProgress = 0.0;
    await engine.export(
        clips: clips, outputPath: out, onProgress: (p) => lastProgress = p);

    final file = File(out);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
    expect(lastProgress, 1.0);

    final outDur = await engine.probeDuration(out);
    expect(outDur, inInclusiveRange(expected - 1.5, expected + 1.5));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 3)), skip: skip);
}
