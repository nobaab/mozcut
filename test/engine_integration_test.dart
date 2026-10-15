@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/data/engine/ffmpeg_engine.dart';
import 'package:vidkaat/domain/models/clip.dart';

/// Exercises the real FfmpegEngine against real files on disk.
/// Run with: flutter test test/engine_integration_test.dart
void main() {
  final engine = FfmpegEngine();

  const a = '/Users/nobaab/Documents/2026-10-09 03-32-53.mp4';
  const b = '/Users/nobaab/Documents/2026-10-06 21-03-11.mp4';

  test('probeDuration reads real durations', () async {
    final da = await engine.probeDuration(a);
    final db = await engine.probeDuration(b);
    expect(da, greaterThan(900));
    expect(db, greaterThan(400));
  });

  test('probeDuration throws on a non-media file', () async {
    final junk = File('${Directory.systemTemp.path}/not_a_video.txt')
      ..writeAsStringSync('hello');
    expect(() => engine.probeDuration(junk.path), throwsException);
    junk.deleteSync();
  });

  test('export trims two clips and concats them into a valid MP4', () async {
    // Take a 3s slice from each source.
    final clips = [
      Clip(sourcePath: a, sourceDuration: 1003, inPoint: 10, outPoint: 13),
      Clip(sourcePath: b, sourceDuration: 455, inPoint: 5, outPoint: 8),
    ];

    final out = '${Directory.systemTemp.path}/vidkaat_it_${DateTime.now().millisecondsSinceEpoch}.mp4';
    var lastProgress = 0.0;

    await engine.export(
      clips: clips,
      outputPath: out,
      onProgress: (p) => lastProgress = p,
    );

    final file = File(out);
    expect(file.existsSync(), isTrue, reason: 'output file should exist');
    expect(file.lengthSync(), greaterThan(1000), reason: 'output should not be empty');
    expect(lastProgress, 1.0, reason: 'progress should reach 100%');

    // The result should be ~6s (3 + 3), allow encoder slack.
    final outDuration = await engine.probeDuration(out);
    expect(outDuration, inInclusiveRange(5.0, 7.5));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
