@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/state/editor_state.dart';

/// Drives the WHOLE app flow through the real EditorController + real
/// FfmpegEngine + real video files — exactly the logic each toolbar button
/// triggers — then verifies the exported file is a genuine, playable MP4.
void main() {
  const a = '/Users/nobaab/Documents/2026-10-09 03-32-53.mp4';
  const b = '/Users/nobaab/Documents/2026-10-06 21-03-11.mp4';

  late ProviderContainer container;
  late EditorController editor;

  setUp(() {
    container = ProviderContainer(); // real engineProvider (FfmpegEngine)
    editor = container.read(editorProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('full edit → export journey produces a valid MP4', () async {
    // --- IMPORT (two clips) -------------------------------------------------
    await editor.addClip(a);
    await editor.addClip(b);
    expect(container.read(editorProvider).clips.length, 2);
    expect(container.read(editorProvider).clips[0].sourceDuration,
        greaterThan(900));

    // --- TRIM both down to short regions (Set In / Set Out) -----------------
    // Select + trim clip A to 10..13s.
    editor.select(container.read(editorProvider).clips[0].id);
    editor.trimSelected(inPoint: 10, outPoint: 13);
    // Select + trim clip B to 5..8s.
    editor.select(container.read(editorProvider).clips[1].id);
    editor.trimSelected(inPoint: 5, outPoint: 8);

    var clips = container.read(editorProvider).clips;
    expect(clips[0].duration, closeTo(3, 0.001));
    expect(clips[1].duration, closeTo(3, 0.001));

    // --- SPLIT clip A at 11.5s (into 1.5s + 1.5s) ---------------------------
    editor.select(clips[0].id);
    editor.splitSelectedAt(11.5);
    clips = container.read(editorProvider).clips;
    expect(clips.length, 3, reason: 'split added one clip');
    expect(clips[0].duration, closeTo(1.5, 0.001));
    expect(clips[1].duration, closeTo(1.5, 0.001));
    expect(clips[2].duration, closeTo(3, 0.001));

    // Total timeline = 1.5 + 1.5 + 3 = 6s.
    expect(container.read(editorProvider).totalDuration, closeTo(6, 0.001));

    // --- DELETE: add a throwaway clip, then remove it -----------------------
    await editor.addClip(b); // selected
    expect(container.read(editorProvider).clips.length, 4);
    editor.removeSelected();
    expect(container.read(editorProvider).clips.length, 3);

    // --- EXPORT (what the Export button does) -------------------------------
    final engine = container.read(engineProvider);
    final out =
        '${Directory.systemTemp.path}/vidkaat_e2e_${DateTime.now().millisecondsSinceEpoch}.mp4';
    var progress = 0.0;
    await engine.export(
      clips: container.read(editorProvider).clips,
      outputPath: out,
      onProgress: (p) => progress = p,
    );
    expect(progress, 1.0);

    // --- VERIFY the real output file ----------------------------------------
    final file = File(out);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));

    // Duration ~6s.
    final outDur = await engine.probeDuration(out);
    expect(outDur, inInclusiveRange(5.0, 7.5));

    // It must have exactly one video and one audio stream (playable edit).
    final probe = await Process.run('ffprobe', [
      '-v', 'error',
      '-show_entries', 'stream=codec_type',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      out,
    ]);
    final streams = probe.stdout.toString().trim().split('\n');
    expect(streams, containsAll(['video', 'audio']));

    file.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
