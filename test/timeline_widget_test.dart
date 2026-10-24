import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/engine.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/audio_clip.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/export_settings.dart';
import 'package:mozcut/domain/models/sticker_overlay.dart';
import 'package:mozcut/domain/models/text_overlay.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_ui_state.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/views/timeline_panel.dart';

/// A stand-in engine so UI tests never touch ffmpeg.
class FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 12.0;

  @override
  Future<(int, int)> probeDimensions(String path) async => (1920, 1080);

  @override
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double)? onProgress,
  }) async {}

  @override
  Future<String> renderPreview({
    required List<Clip> clips,
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double)? onProgress,
  }) async => '';

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

  @override
  Future<String> generateSfx(String id) async => '';

  @override
  Future<List<String>> extractThumbnails({
    required Clip clip,
    required int count,
    int height = 64,
  }) async => const [];

  @override
  Future<String?> waveformPng({
    required Clip clip,
    required int width,
    int height = 40,
  }) async => null;
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

  test('updateTransform mutates only the selected clip, partial updates keep the rest', () async {
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

  group('zoomAnchoredScrollOffset', () {
    test('keeps the time under the cursor stationary when zooming in', () {
      // At 40px/s, scrolled 100px in, with the cursor 50px into the
      // viewport: the cursor sits over t = (100 + 50) / 40 = 3.75s.
      // Zooming to 80px/s, that instant should now be at 3.75 * 80 = 300px
      // of content — so the new scroll offset must be 300 - 50 = 250.
      final offset = zoomAnchoredScrollOffset(
        oldOffset: 100,
        cursorDx: 50,
        oldPx: 40,
        newPx: 80,
        maxScrollExtent: 1000,
      );
      expect(offset, closeTo(250, 0.0001));
    });

    test('keeps the time under the cursor stationary when zooming out', () {
      final offset = zoomAnchoredScrollOffset(
        oldOffset: 250,
        cursorDx: 50,
        oldPx: 80,
        newPx: 40,
        maxScrollExtent: 1000,
      );
      expect(offset, closeTo(100, 0.0001));
    });

    test('is a no-op when the zoom level does not change', () {
      final offset = zoomAnchoredScrollOffset(
        oldOffset: 123,
        cursorDx: 50,
        oldPx: 40,
        newPx: 40,
        maxScrollExtent: 1000,
      );
      expect(offset, closeTo(123, 0.0001));
    });

    test('clamps to the scrollable range', () {
      // Zooming out far enough that the anchor math would go negative.
      final low = zoomAnchoredScrollOffset(
        oldOffset: 0,
        cursorDx: 500,
        oldPx: 40,
        newPx: 6,
        maxScrollExtent: 1000,
      );
      expect(low, 0);

      // Zooming in far enough that the anchor math would overshoot the end.
      final high = zoomAnchoredScrollOffset(
        oldOffset: 900,
        cursorDx: 0,
        oldPx: 40,
        newPx: 240,
        maxScrollExtent: 1000,
      );
      expect(high, 1000);
    });
  });

  group('TimelineZoom', () {
    test('zoomIn/zoomOut and set clamp to [6, 240] px/sec', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(timelineZoomProvider.notifier);

      expect(container.read(timelineZoomProvider), 40);

      notifier.set(1000);
      expect(container.read(timelineZoomProvider), 240);

      notifier.set(-5);
      expect(container.read(timelineZoomProvider), 6);

      notifier.set(50);
      notifier.zoomOut();
      expect(container.read(timelineZoomProvider), closeTo(50 / 1.3, 0.0001));

      notifier.set(50);
      notifier.zoomIn();
      expect(container.read(timelineZoomProvider), closeTo(50 * 1.3, 0.0001));
    });
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
