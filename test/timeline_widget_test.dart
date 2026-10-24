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
import 'package:mozcut/domain/models/video_overlay.dart';
import 'package:mozcut/ui/features/editor/view_models/audio_clips_view_model.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_ui_state.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/view_models/text_overlays_view_model.dart';
import 'package:mozcut/ui/features/editor/view_models/video_overlays_view_model.dart';
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
    List<VideoOverlay> videoOverlays = const [],
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
    List<VideoOverlay> videoOverlays = const [],
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
  Future<void> exportStillFrame({
    required List<Clip> clips,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    required double atSeconds,
    required String outputPath,
  }) async {}

  @override
  Future<void> extractAudio({
    required Clip clip,
    required String outputPath,
  }) async {}

  @override
  Future<String> generateSfx(String id) async => '';

  @override
  Future<String> generateShape(String id) async => '';

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

  testWidgets('adding a video overlay renders a bar on the overlay lane',
      (tester) async {
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

    await container
        .read(videoOverlaysProvider.notifier)
        .addFromPath('/Users/x/My Videos/pip.mp4', startTime: 2.0);
    await tester.pump();

    // The overlay appears as its own bar on the overlay lane, named, and is
    // tracked independently of the (empty) main track/audio lane.
    expect(find.text('pip.mp4'), findsOneWidget);
    expect(container.read(videoOverlaysProvider).first.startTime, 2.0);

    // Tapping it selects it on the overlay lane (same tap-to-select idiom
    // as a main-track clip and an audio-lane clip).
    await tester.tap(find.text('pip.mp4'));
    await tester.pump();
    expect(container.read(selectedVideoOverlayProvider),
        container.read(videoOverlaysProvider).first.id);
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

  testWidgets('a text overlay renders a bar on the text track',
      (tester) async {
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

    // The text lane only appears once there's something on it (CapCut hides
    // empty tracks) — adding an overlay should bring the bar (and its text)
    // into view.
    container.read(textOverlaysProvider.notifier).add();
    await tester.pump();

    expect(find.text('Sample text'), findsOneWidget);
  });

  testWidgets(
      'a transition marker appears between two adjacent clips and toggling '
      'it sets a transition on the right-hand clip', (tester) async {
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

    final editor = container.read(editorProvider.notifier);
    await editor.addClip('/a/first.mp4');
    await editor.addClip('/b/second.mp4');
    await tester.pump();

    // One boundary between the two clips -> exactly one marker.
    expect(find.byIcon(Icons.compare_arrows), findsOneWidget);

    // Tapping it applies a default transition entering the clip on the
    // right of that boundary (Clip.transitionId lives on the "into" side of
    // a cut — see its doc comment).
    await tester.tap(find.byIcon(Icons.compare_arrows));
    await tester.pump();

    final clips = container.read(editorProvider).clips;
    expect(clips[0].transitionId, isNull);
    expect(clips[1].transitionId, isNotNull);

    // Tapping again clears it.
    await tester.tap(find.byIcon(Icons.compare_arrows));
    await tester.pump();
    expect(container.read(editorProvider).clips[1].transitionId, isNull);
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

  group('timeline snapping', () {
    testWidgets(
        'dragging an audio clip close to a video clip edge snaps to it',
        (tester) async {
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

      // 12s clip (FakeEngine.probeDuration) at the default 40px/s zoom ends
      // at timeline second 12 (480px).
      await container.read(editorProvider.notifier).addClip('/a/clip.mp4');
      await container
          .read(audioClipsProvider.notifier)
          .addFromPath('/x.mp3', start: 5.0);
      await tester.pumpAndSettle();
      expect(container.read(audioClipsProvider).first.start, 5.0);
      expect(container.read(snapIndicatorProvider), isNull);

      // Drag it right, close to the video clip's end (12s @ 40px/s =
      // 480px). `tester.drag` consumes some of the requested offset
      // overcoming the gesture recognizer's touch slop before any of it
      // reaches `onUpdate`, so the nominal offset is well past the target —
      // comfortably landing the *actual* delivered candidate within the
      // 8px/0.2s snap threshold either way.
      await tester.drag(find.text('x.mp3'), const Offset(300, 0));
      await tester.pump();

      expect(container.read(audioClipsProvider).first.start, closeTo(12.0, 0.05));
      // The indicator clears once the drag/gesture has ended.
      expect(container.read(snapIndicatorProvider), isNull);
    });

    testWidgets('turning snapping off leaves the raw drag position alone',
        (tester) async {
      final container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(FakeEngine())],
      );
      addTearDown(container.dispose);
      container.read(snapEnabledProvider.notifier).set(false);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: TimelinePanel())),
        ),
      );

      // 12s clip ends at timeline second 12 (480px @ 40px/s).
      await container.read(editorProvider.notifier).addClip('/a/clip.mp4');
      await container
          .read(audioClipsProvider.notifier)
          .addFromPath('/x.mp3', start: 2.0);
      await tester.pumpAndSettle();

      // A modest drag, clearly short of the 12.0s clip edge either way —
      // with snapping off it should land roughly proportional to the drag,
      // nowhere near that target.
      await tester.drag(find.text('x.mp3'), const Offset(100, 0));
      await tester.pump();

      final start = container.read(audioClipsProvider).first.start;
      expect(start, greaterThan(2.0));
      expect(start, lessThan(10.0));
    });
  });

  group('playback auto-scroll-follow', () {
    Future<ScrollController> pumpWideTimeline(
        WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: TimelinePanel())),
        ),
      );
      // Lots of 12s clips (FakeEngine.probeDuration) so the timeline is well
      // wider than the viewport and there's real room to scroll.
      final editor = container.read(editorProvider.notifier);
      for (var i = 0; i < 20; i++) {
        await editor.addClip('/clip$i.mp4');
      }
      await tester.pumpAndSettle();
      final scrollView =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      return scrollView.controller!;
    }

    testWidgets(
        'nudges the scroll offset to follow the playhead while playing',
        (tester) async {
      final container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(FakeEngine())],
      );
      addTearDown(container.dispose);
      final controller = await pumpWideTimeline(tester, container);
      expect(controller.offset, 0);

      container.read(isPlayingProvider.notifier).set(true);
      container.read(playheadProvider.notifier).set(200); // deep in the timeline
      await tester.pump();

      expect(controller.offset, greaterThan(0));
    });

    testWidgets('does not auto-scroll while not playing', (tester) async {
      final container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(FakeEngine())],
      );
      addTearDown(container.dispose);
      final controller = await pumpWideTimeline(tester, container);

      // isPlayingProvider stays at its default (false).
      container.read(playheadProvider.notifier).set(200);
      await tester.pump();

      expect(controller.offset, 0);
    });
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
