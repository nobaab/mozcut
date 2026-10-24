import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mozcut/ui/features/editor/view_models/editor_ui_state.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';
import 'package:mozcut/ui/features/editor/view_models/player_control.dart';
import 'package:mozcut/ui/features/editor/views/editor_shortcuts.dart';

/// A stand-in engine so these UI tests never touch ffmpeg.
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
  Future<(ProviderContainer, Editor)> pumpWithClips(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: EditorShortcuts(child: Scaffold(body: SizedBox.expand())),
        ),
      ),
    );

    final editor = container.read(editorProvider.notifier);
    await editor.addClip('/a/clip.mp4');
    await editor.addClip('/b/clip.mp4'); // last-added is selected
    await tester.pump();
    return (container, editor);
  }

  testWidgets('Delete key removes the selected clip (no focus needed)',
      (tester) async {
    final (container, _) = await pumpWithClips(tester);
    expect(container.read(editorProvider).clips.length, 2);
    expect(container.read(editorProvider).selected, isNotNull);

    // The whole point of the fix: the shortcut fires via a global keyboard
    // handler, so it works even though nothing in the tree holds focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(container.read(editorProvider).clips.length, 1);
  });

  testWidgets('Backspace also removes the selected clip', (tester) async {
    final (container, _) = await pumpWithClips(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(container.read(editorProvider).clips.length, 1);
  });

  testWidgets('Cmd+D duplicates the selected clip', (tester) async {
    final (container, _) = await pumpWithClips(tester);
    expect(container.read(editorProvider).clips.length, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(container.read(editorProvider).clips.length, 3);
  });

  testWidgets('Ctrl+D also duplicates the selected clip', (tester) async {
    final (container, _) = await pumpWithClips(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(container.read(editorProvider).clips.length, 3);
  });

  testWidgets('Shift+Delete ripple-deletes the selected clip', (tester) async {
    final (container, _) = await pumpWithClips(tester);
    expect(container.read(editorProvider).clips.length, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(container.read(editorProvider).clips.length, 1);
  });

  testWidgets('n toggles the snap-enabled provider (default on)',
      (tester) async {
    final (container, _) = await pumpWithClips(tester);
    expect(container.read(snapEnabledProvider), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(container.read(snapEnabledProvider), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(container.read(snapEnabledProvider), isTrue);
  });

  testWidgets('Ctrl+= zooms the timeline in, Ctrl+- zooms it out',
      (tester) async {
    final (container, _) = await pumpWithClips(tester);
    final initial = container.read(timelineZoomProvider);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final afterZoomIn = container.read(timelineZoomProvider);
    expect(afterZoomIn, greaterThan(initial));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(container.read(timelineZoomProvider), lessThan(afterZoomIn));
  });

  testWidgets(
      'Cmd+Shift+= (the shifted "+" key, reported as LogicalKeyboardKey.add) '
      'also zooms in', (tester) async {
    final (container, _) = await pumpWithClips(tester);
    final initial = container.read(timelineZoomProvider);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // LogicalKeyboardKey.add isn't a distinct physical key on its own — it's
    // what Shift+Equal reports — so the physical key must be specified
    // explicitly for the simulator to find a matching key code.
    await tester.sendKeyEvent(LogicalKeyboardKey.add,
        physicalKey: PhysicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(container.read(timelineZoomProvider), greaterThan(initial));
  });

  testWidgets('Shift+Right/Left seek a full second (not a frame)',
      (tester) async {
    final (container, _) = await pumpWithClips(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    var cmd = container.read(playerControlProvider);
    expect(cmd?.type, PlayerCommandType.seekBy);
    expect(cmd?.seconds, 1.0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    cmd = container.read(playerControlProvider);
    expect(cmd?.seconds, -1.0);
  });

  testWidgets('a plain Right arrow (no Shift) still nudges by one frame',
      (tester) async {
    final (container, _) = await pumpWithClips(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final cmd = container.read(playerControlProvider);
    expect(cmd?.seconds, EditorShortcuts.nudgeSeconds);
  });

  testWidgets('a text field with focus is never hijacked by shortcuts',
      (tester) async {
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(_FakeEngine())],
    );
    addTearDown(container.dispose);

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: EditorShortcuts(
            child: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      ),
    );

    final editor = container.read(editorProvider.notifier);
    await editor.addClip('/a/clip.mp4');
    await editor.addClip('/b/clip.mp4');
    await tester.pump();

    // Focus the text field and type a character that is also a shortcut ('s'
    // = split). It must go to the field, and must NOT split a clip.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 's');
    await tester.pump();

    expect(container.read(editorProvider).clips.length, 2,
        reason: 'typing in a field must not trigger split');
    expect(controller.text, 's');
  });
}
