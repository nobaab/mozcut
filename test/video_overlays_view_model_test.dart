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

/// A fake [Engine] that reports a fixed duration, so `VideoOverlays
/// .addFromPath` can be exercised without a real ffmpeg/ffprobe binary — same
/// pattern used by `test/audio_clip_model_test.dart`.
class _FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 9.0;

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
  group('VideoOverlays notifier', () {
    late ProviderContainer container;
    late VideoOverlays notifier;

    setUp(() {
      container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(_FakeEngine())],
      );
      notifier = container.read(videoOverlaysProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(container.read(videoOverlaysProvider), isEmpty);
    });

    test('addFromPath probes duration and appends a new overlay', () async {
      final added = await notifier.addFromPath('/video/pip.mp4');
      final state = container.read(videoOverlaysProvider);

      expect(state.length, 1);
      expect(state.first, added);
      expect(added.sourcePath, '/video/pip.mp4');
      expect(added.sourceDuration, 9.0);
      expect(added.outPoint, 9.0);
      expect(added.startTime, 0);
    });

    test('addFromPath honors a custom startTime', () async {
      final added =
          await notifier.addFromPath('/video/pip.mp4', startTime: 4.5);
      expect(added.startTime, 4.5);
    });

    test('update replaces the overlay at the given index', () async {
      await notifier.addFromPath('/a.mp4');
      await notifier.addFromPath('/b.mp4');
      final second = container.read(videoOverlaysProvider)[1];

      notifier.update(1, second.copyWith(startTime: 9, blendMode: 'screen'));

      final updated = container.read(videoOverlaysProvider)[1];
      expect(updated.startTime, 9);
      expect(updated.blendMode, 'screen');
      expect(container.read(videoOverlaysProvider)[0].startTime, isNot(9));
    });

    test('update ignores an out-of-range index', () async {
      await notifier.addFromPath('/a.mp4');
      final before = container.read(videoOverlaysProvider);
      notifier.update(5, before.first.copyWith(startTime: 99));
      expect(container.read(videoOverlaysProvider), before);
    });

    test('removeAt deletes the overlay at the given index', () async {
      await notifier.addFromPath('/a.mp4');
      await notifier.addFromPath('/b.mp4');
      notifier.removeAt(0);
      expect(container.read(videoOverlaysProvider).length, 1);
    });

    test('removeAt ignores an out-of-range index', () async {
      await notifier.addFromPath('/a.mp4');
      notifier.removeAt(99);
      expect(container.read(videoOverlaysProvider).length, 1);
    });

    test('load replaces the whole list (used when opening a project)', () {
      final fresh = [
        VideoOverlay(sourcePath: '/from/manifest.mp4', sourceDuration: 5),
      ];
      notifier.load(fresh);
      expect(container.read(videoOverlaysProvider), fresh);
    });
  });

  group('SelectedVideoOverlay notifier', () {
    test('starts at null and can be set/cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedVideoOverlayProvider.notifier);

      expect(container.read(selectedVideoOverlayProvider), isNull);
      notifier.set('abc');
      expect(container.read(selectedVideoOverlayProvider), 'abc');
      notifier.set(null);
      expect(container.read(selectedVideoOverlayProvider), isNull);
    });
  });
}
