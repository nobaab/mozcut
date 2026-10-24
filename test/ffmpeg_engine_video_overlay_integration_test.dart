@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/video_overlay.dart';

/// Up to [n] real video files from the user's Documents folder — same
/// discovery helper as `test/end_to_end_test.dart`.
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

/// Exercises the video-overlay (picture-in-picture) feature against the real
/// `ffmpeg`/`ffprobe` binaries and real sample videos — unlike
/// test/ffmpeg_engine_video_overlay_test.dart (which uses a fake ffmpeg
/// script to inspect the generated filter string), this actually renders and
/// verifies a genuine, playable MP4 comes out the other end, for both the
/// `'normal'` (positioned overlay) and a non-normal (`blend`) mode.
void main() {
  final videos = sampleVideos(2);
  final skip = videos.length < 2 ? 'needs ≥2 .mp4 files in ~/Documents' : null;

  Clip clipFor(String path, double duration) =>
      Clip(sourcePath: path, sourceDuration: duration, inPoint: 0, outPoint: duration);

  test('exports a real MP4 with a normal-mode picture-in-picture overlay',
      () async {
    final engine = FfmpegEngine();
    final mainDuration = await engine.probeDuration(videos[0]);
    final overlayDuration = await engine.probeDuration(videos[1]);
    final clipLen = mainDuration.clamp(0.0, 5.0);
    final overlayLen = overlayDuration.clamp(0.0, 3.0);

    final out =
        '${Directory.systemTemp.path}/mozcut_vo_normal_${DateTime.now().millisecondsSinceEpoch}.mp4';
    await engine.export(
      clips: [clipFor(videos[0], clipLen)],
      outputPath: out,
      videoOverlays: [
        VideoOverlay(
          sourcePath: videos[1],
          sourceDuration: overlayDuration,
          outPoint: overlayLen,
          startTime: 0.5,
          scale: 0.4,
          posX: 0.75,
          posY: 0.25,
          opacity: 0.9,
        ),
      ],
    );

    final file = File(out);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    expect(await engine.probeDuration(out), closeTo(clipLen, 0.6));

    final probe = await Process.run('ffprobe', [
      '-v', 'error',
      '-show_entries', 'stream=codec_type',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      out,
    ]);
    final streams = probe.stdout.toString().trim().split('\n');
    expect(streams, containsAll(['video', 'audio']));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

  test('exports a real MP4 with a non-normal blend-mode overlay', () async {
    final engine = FfmpegEngine();
    final mainDuration = await engine.probeDuration(videos[0]);
    final overlayDuration = await engine.probeDuration(videos[1]);
    final clipLen = mainDuration.clamp(0.0, 5.0);
    final overlayLen = overlayDuration.clamp(0.0, 3.0);

    final out =
        '${Directory.systemTemp.path}/mozcut_vo_blend_${DateTime.now().millisecondsSinceEpoch}.mp4';
    await engine.export(
      clips: [clipFor(videos[0], clipLen)],
      outputPath: out,
      videoOverlays: [
        VideoOverlay(
          sourcePath: videos[1],
          sourceDuration: overlayDuration,
          outPoint: overlayLen,
          startTime: 0.2,
          blendMode: 'screen',
          opacity: 0.7,
        ),
      ],
    );

    final file = File(out);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    expect(await engine.probeDuration(out), closeTo(clipLen, 0.6));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

  test('renderPreview with a video overlay produces a valid proxy MP4',
      () async {
    final engine = FfmpegEngine();
    final mainDuration = await engine.probeDuration(videos[0]);
    final overlayDuration = await engine.probeDuration(videos[1]);
    final clipLen = mainDuration.clamp(0.0, 4.0);

    final path = await engine.renderPreview(
      clips: [clipFor(videos[0], clipLen)],
      videoOverlays: [
        VideoOverlay(
          sourcePath: videos[1],
          sourceDuration: overlayDuration,
          outPoint: overlayDuration.clamp(0.0, 2.0),
          startTime: 0,
        ),
      ],
    );

    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);
}
