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
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/views/effects_panel.dart';

/// A stand-in engine so UI tests never touch ffmpeg (see
/// test/timeline_widget_test.dart for the same pattern).
class _FakeEngine implements Engine {
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
  testWidgets('effects panel renders an effect name', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    expect(find.text('Gaussian Blur'), findsOneWidget);
  });

  testWidgets('category chip filters the grid', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    await tester.tap(find.text('Blur'));
    await tester.pumpAndSettle();

    expect(find.text('Gaussian Blur'), findsOneWidget);
    expect(find.text('Chroma Key'), findsNothing);
  });

  testWidgets('tapping an effect with no clip selected prompts to select one',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    await tester.tap(find.text('Sharpen'));
    await tester.pump();

    expect(find.text('Select a clip first'), findsOneWidget);
  });

  testWidgets('tapping an effect applies it, tapping again clears it',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    await container.read(editorProvider.notifier).addClip('/a/clip.mp4');
    await tester.pump();

    await tester.tap(find.text('Sharpen'));
    await tester.pump();

    expect(container.read(editorProvider).selected?.effectId, 'Sharpen');
    expect(find.text('Effect: Sharpen'), findsOneWidget);

    // Tapping the already-applied effect again clears it.
    await tester.tap(find.text('Sharpen'));
    await tester.pump();
    expect(container.read(editorProvider).selected?.effectId, isNull);

    // Re-apply, then clear via the "None" button.
    await tester.tap(find.text('Sharpen'));
    await tester.pump();
    await tester.tap(find.text('None'));
    await tester.pump();
    expect(container.read(editorProvider).selected?.effectId, isNull);
  });
}
