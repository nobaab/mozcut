@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';

/// Up to [n] real video files from the user's Documents folder.
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

/// Drives the WHOLE app flow through the real Editor + real FfmpegEngine + real
/// video files — exactly the logic each toolbar button triggers — then verifies
/// the exported file is a genuine, playable MP4.
void main() {
  final videos = sampleVideos(2);
  final skip =
      videos.length < 2 ? 'needs ≥2 .mp4 files in ~/Documents' : null;

  late ProviderContainer container;
  late Editor editor;

  setUp(() {
    container = ProviderContainer();
    editor = container.read(editorProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('full edit → export journey produces a valid MP4', () async {
    final a = videos[0], b = videos[1];

    // --- IMPORT (two clips) ---
    await editor.addClip(a);
    await editor.addClip(b);
    expect(container.read(editorProvider).clips.length, 2);
    expect(
        container.read(editorProvider).clips[0].sourceDuration, greaterThan(4));

    // --- TRIM both to a 3s region (Set In / Set Out), 1..4s ---
    editor.select(container.read(editorProvider).clips[0].id);
    editor.trimSelected(inPoint: 1, outPoint: 4);
    editor.select(container.read(editorProvider).clips[1].id);
    editor.trimSelected(inPoint: 1, outPoint: 4);

    var clips = container.read(editorProvider).clips;
    expect(clips[0].duration, closeTo(3, 0.001));
    expect(clips[1].duration, closeTo(3, 0.001));

    // --- SPLIT clip A at its midpoint (timeline 1.5s) into 1.5s + 1.5s ---
    // splitSelectedAt takes a timeline position; clip A occupies [0, 3].
    editor.select(clips[0].id);
    editor.splitSelectedAt(1.5);
    clips = container.read(editorProvider).clips;
    expect(clips.length, 3, reason: 'split added one clip');
    expect(clips[0].duration, closeTo(1.5, 0.001));
    expect(clips[1].duration, closeTo(1.5, 0.001));
    expect(clips[2].duration, closeTo(3, 0.001));
    expect(container.read(editorProvider).totalDuration, closeTo(6, 0.001));

    // --- DELETE: add a throwaway clip, then remove it ---
    await editor.addClip(b);
    expect(container.read(editorProvider).clips.length, 4);
    editor.removeSelected();
    expect(container.read(editorProvider).clips.length, 3);

    // --- EXPORT ---
    final engine = container.read(engineProvider);
    final out =
        '${Directory.systemTemp.path}/mozcut_e2e_${DateTime.now().millisecondsSinceEpoch}.mp4';
    var progress = 0.0;
    await engine.export(
      clips: container.read(editorProvider).clips,
      outputPath: out,
      onProgress: (p) => progress = p,
    );
    expect(progress, 1.0);

    // --- VERIFY ---
    final file = File(out);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    expect(await engine.probeDuration(out), inInclusiveRange(5.0, 7.5));

    final probe = await Process.run('ffprobe', [
      '-v', 'error',
      '-show_entries', 'stream=codec_type',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      out,
    ]);
    final streams = probe.stdout.toString().trim().split('\n');
    expect(streams, containsAll(['video', 'audio']));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 4)), skip: skip);
}
