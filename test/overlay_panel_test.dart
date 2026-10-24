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
import 'package:mozcut/ui/features/editor/view_models/video_overlays_view_model.dart';
import 'package:mozcut/ui/features/editor/views/overlay_panel.dart';

/// A stand-in engine so the "On this project" list can be populated without
/// going through the file picker (which needs a platform channel) — same
/// pattern as test/stickers_panel_test.dart / test/audio_panel_test.dart.
class _FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 6.0;

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
  Widget harness(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: OverlayPanel())),
      );

  testWidgets('shows the "Import video" action and an empty-state message',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container));

    expect(find.text('Import video'), findsOneWidget);
    expect(find.textContaining('No overlays yet'), findsOneWidget);
  });

  testWidgets(
      'a placed overlay shows inspector-style controls: scale, position, '
      'rotation, opacity and a blend-mode dropdown', (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    // Place one overlay directly via the notifier, bypassing the file
    // picker (same approach test/stickers_panel_test.dart uses for its
    // "On this project" list).
    await container
        .read(videoOverlaysProvider.notifier)
        .addFromPath('/videos/pip.mp4');

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    expect(find.text('pip.mp4'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Scale'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Blend'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    // Every slider (start/scale/x/y/rotate/opacity) is present.
    expect(find.byType(Slider), findsNWidgets(6));
  });

  testWidgets('dragging the opacity slider updates the overlay\'s opacity',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await container
        .read(videoOverlaysProvider.notifier)
        .addFromPath('/videos/pip.mp4');

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final opacitySlider = find.ancestor(
        of: find.text('Opacity'), matching: find.byType(Row));
    expect(opacitySlider, findsWidgets);

    // Drag the last slider (Blend has no slider, Opacity is the last one
    // with a Slider) to a lower value.
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    final opacityIndex = sliders.length - 1;
    await tester.drag(
        find.byType(Slider).at(opacityIndex), const Offset(-100, 0));
    await tester.pumpAndSettle();

    expect(container.read(videoOverlaysProvider).first.opacity, lessThan(1.0));
  });

  testWidgets('choosing a blend mode from the dropdown updates the overlay',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await container
        .read(videoOverlaysProvider.notifier)
        .addFromPath('/videos/pip.mp4');

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    expect(container.read(videoOverlaysProvider).first.blendMode, 'normal');

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen').last);
    await tester.pumpAndSettle();

    expect(container.read(videoOverlaysProvider).first.blendMode, 'screen');
  });

  testWidgets('the delete button removes the overlay', (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await container
        .read(videoOverlaysProvider.notifier)
        .addFromPath('/videos/pip.mp4');

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    expect(container.read(videoOverlaysProvider), hasLength(1));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(container.read(videoOverlaysProvider), isEmpty);
  });
}
