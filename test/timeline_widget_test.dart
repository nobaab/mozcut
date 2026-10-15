import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/engine.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/export_settings.dart';
import 'package:mozcut/domain/models/text_overlay.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/views/timeline_panel.dart';

/// A stand-in engine so UI tests never touch ffmpeg.
class FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 12.0;

  @override
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    void Function(double)? onProgress,
  }) async {}

  @override
  Future<void> savePoster({
    required Clip clip,
    required String outputPath,
    int width = 480,
  }) async {}

  @override
  Future<void> extractAudio({
    required Clip clip,
    required String outputPath,
  }) async {}
}

void main() {
  testWidgets('empty timeline shows the hint', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TimelinePanel())),
      ),
    );
    expect(find.textContaining('clips show up here'), findsOneWidget);
  });

  testWidgets('adding a clip renders a bar on the timeline', (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TimelinePanel())),
      ),
    );

    // Drive the real controller — fake engine supplies the duration.
    await container
        .read(editorProvider.notifier)
        .addClip('/Users/x/My Videos/holiday.mp4');
    await tester.pump();

    // The clip appears as a bar on the timeline, named.
    expect(find.text('holiday.mp4'), findsOneWidget);

    // Selected clip should be highlighted — state wiring works.
    expect(container.read(editorProvider).selected?.fileName, 'holiday.mp4');
    expect(container.read(editorProvider).clips.first.duration, 12.0);
  });

  testWidgets('split turns one clip into two bars', (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TimelinePanel())),
      ),
    );

    final ctrl = container.read(editorProvider.notifier);
    await ctrl.addClip('/a/clip.mp4'); // 12s
    ctrl.splitSelectedAt(5);
    await tester.pump();

    // Two bars now (same source name), durations 5s + 7s.
    final clips = container.read(editorProvider).clips;
    expect(clips.length, 2);
    expect(clips[0].duration, closeTo(5, 0.001));
    expect(clips[1].duration, closeTo(7, 0.001));
    expect(find.text('clip.mp4'), findsNWidgets(2));
  });

  test('updateTransform mutates only the selected clip, partial updates keep the rest',
      () async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(FakeEngine())],
    );
    addTearDown(container.dispose);
    final editor = container.read(editorProvider.notifier);

    await editor.addClip('/a/clip.mp4');
    await editor.addClip('/b/clip.mp4'); // selected

    editor.updateTransform(scale: 2.0, posX: 0.5, rotation: 45, flipH: true);

    final selected = container.read(editorProvider).selected!;
    expect(selected.scale, 2.0);
    expect(selected.posX, 0.5);
    expect(selected.posY, 0.0); // untouched field keeps its default
    expect(selected.rotation, 45);
    expect(selected.flipH, isTrue);

    // The other (unselected) clip is untouched.
    final other = container.read(editorProvider).clips.first;
    expect(other.scale, 1.0);
    expect(other.flipH, isFalse);

    // A later partial update only changes what's passed.
    editor.updateTransform(posY: -0.5);
    final updated = container.read(editorProvider).selected!;
    expect(updated.posY, -0.5);
    expect(updated.scale, 2.0, reason: 'unrelated fields stay as they were');

    // resetTransform() brings it back to identity.
    editor.resetTransform();
    final reset = container.read(editorProvider).selected!;
    expect(reset.scale, 1.0);
    expect(reset.posX, 0.0);
    expect(reset.posY, 0.0);
    expect(reset.rotation, 0.0);
    expect(reset.flipH, isFalse);
  });

  test('updateTransform clamps scale away from zero', () async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(FakeEngine())],
    );
    addTearDown(container.dispose);
    final editor = container.read(editorProvider.notifier);

    await editor.addClip('/a/clip.mp4');
    editor.updateTransform(scale: 0.0);

    expect(container.read(editorProvider).selected!.scale, greaterThan(0.0));
  });
}
