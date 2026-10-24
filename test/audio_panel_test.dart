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
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/views/audio_panel.dart';

/// A stand-in engine so these UI tests never touch ffmpeg — same pattern as
/// test/timeline_widget_test.dart / test/effects_panel_test.dart.
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
  Future<String> generateSfx(String id) async => '/tmp/sfx_$id.wav';

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
  testWidgets('empty state shows import hint under "My audio"',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AudioPanel())),
      ),
    );

    expect(find.text('Import audio'), findsOneWidget);
    expect(find.textContaining('No audio imported yet'), findsOneWidget);
  });

  testWidgets('Sound effects chip shows the built-in catalogue',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AudioPanel())),
      ),
    );

    await tester.tap(find.text('Sound effects'));
    await tester.pumpAndSettle();

    expect(find.text('Beep'), findsOneWidget);
    expect(find.text('Whoosh'), findsOneWidget);
  });

  testWidgets('tapping a sound effect adds it to the audio lane',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AudioPanel())),
      ),
    );

    await tester.tap(find.text('Sound effects'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beep'));
    await tester.pumpAndSettle();

    final clips = container.read(audioClipsProvider);
    expect(clips, hasLength(1));
    expect(clips.single.sourcePath, '/tmp/sfx_beep.wav');
    expect(clips.single.start, 0);
    expect(find.textContaining('Added "Beep"'), findsOneWidget);
  });

  testWidgets('Extract tab prompts for a selection, then extracts once one '
      'is made', (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AudioPanel())),
      ),
    );

    await tester.tap(find.text('Extract'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Select a video clip'), findsOneWidget);

    await container.read(editorProvider.notifier).addClip('/a/clip.mp4');
    await tester.pump();

    expect(find.text('Extract to the audio lane'), findsOneWidget);
    await tester.tap(find.text('Extract to the audio lane'));
    await tester.pumpAndSettle();

    final clips = container.read(audioClipsProvider);
    expect(clips, hasLength(1));
    expect(clips.single.fileName, startsWith('clip_'));
  });

  testWidgets('My audio lists a previously-added source for re-use',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AudioPanel())),
      ),
    );

    await container
        .read(audioClipsProvider.notifier)
        .addFromPath('/music/track.mp3');
    await tester.pump();

    expect(find.text('track.mp3'), findsOneWidget);

    await tester.tap(find.text('track.mp3'));
    await tester.pumpAndSettle();

    expect(container.read(audioClipsProvider), hasLength(2));
  });
}
