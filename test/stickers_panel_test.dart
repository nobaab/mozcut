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
import 'package:mozcut/ui/features/editor/view_models/sticker_overlays_view_model.dart';
import 'package:mozcut/ui/features/editor/views/stickers_panel.dart';

/// A stand-in engine so shape-generation tests never touch ffmpeg — same
/// pattern as test/effects_panel_test.dart / test/audio_panel_test.dart.
class _FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 3.0;

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
  Future<String> generateShape(String id) async => '/tmp/shape_$id.png';

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
  Widget harness() => const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StickersPanel())),
      );

  testWidgets('shows the emoji category by default with a populated grid',
      (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('😀'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('the Shapes category shows the built-in generated shapes',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    expect(find.text('😀'), findsNothing);
    expect(find.byIcon(Icons.crop_square_outlined), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });

  testWidgets(
      'tapping a shape generates it and adds an image sticker to the project',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StickersPanel())),
      ),
    );

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Added "Circle" to the project'), findsOneWidget);
    final overlays = container.read(stickerOverlaysProvider);
    expect(overlays.length, 1);
    expect(overlays.first.isImage, isTrue);
    expect(overlays.first.imagePath, '/tmp/shape_circle.png');
  });

  testWidgets('a still-stubbed category shows generic placeholders',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Arrows'));
    await tester.pumpAndSettle();

    expect(find.text('😀'), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
  });

  testWidgets('tapping a still-stubbed sticker shows a coming-soon snackbar',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Arrows'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.image_outlined).first);
    await tester.pump();

    expect(find.text('Placing stickers — coming soon'), findsOneWidget);
  });

  testWidgets(
      'tapping an emoji adds it to the project and lists it below',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StickersPanel())),
      ),
    );

    await tester.tap(find.text('😀'));
    await tester.pump();

    expect(find.text('Added 😀 to the project'), findsOneWidget);
    expect(container.read(stickerOverlaysProvider).length, 1);
    expect(container.read(stickerOverlaysProvider).first.emoji, '😀');
  });

  testWidgets('searching filters the grid', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Arrows'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pointer');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('shows an "Import image" action', (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('Import image'), findsOneWidget);
  });
}
