import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/engine.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/audio_clip.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/export_settings.dart';
import 'package:mozcut/domain/models/sticker_overlay.dart';
import 'package:mozcut/domain/models/text_overlay.dart';
import 'package:mozcut/ui/features/editor/view_models/audio_clips_view_model.dart';

/// A fake [Engine] that reports a fixed duration, so `AudioClips.addFromPath`
/// can be exercised without a real ffmpeg/ffprobe binary — same pattern used
/// by `timeline_widget_test.dart`/`effects_panel_test.dart`.
class _FakeEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 42.0;

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
  group('AudioClip', () {
    test('defaults: start/inPoint 0, outPoint == sourceDuration, volume 1',
        () {
      final clip = AudioClip(sourcePath: '/a.mp3', sourceDuration: 10);
      expect(clip.start, 0);
      expect(clip.inPoint, 0);
      expect(clip.outPoint, 10);
      expect(clip.volume, 1.0);
      expect(clip.fadeIn, 0.0);
      expect(clip.fadeOut, 0.0);
      expect(clip.duration, 10);
    });

    test('survives a JSON round-trip', () {
      final clip = AudioClip(
        sourcePath: '/music/song.mp3',
        sourceDuration: 30,
        start: 5.5,
        inPoint: 1.0,
        outPoint: 20.0,
        volume: 1.5,
        fadeIn: 0.5,
        fadeOut: 1.0,
      );

      final restored = AudioClip.fromJson(clip.toJson());

      expect(restored.id, clip.id);
      expect(restored.sourcePath, '/music/song.mp3');
      expect(restored.sourceDuration, 30);
      expect(restored.start, 5.5);
      expect(restored.inPoint, 1.0);
      expect(restored.outPoint, 20.0);
      expect(restored.volume, 1.5);
      expect(restored.fadeIn, 0.5);
      expect(restored.fadeOut, 1.0);
    });

    test('fromJson fills in defaults for an old/partial manifest', () {
      final restored = AudioClip.fromJson({
        'id': 'x',
        'sourcePath': '/a.mp3',
        'sourceDuration': 10.0,
      });

      expect(restored.start, 0);
      expect(restored.inPoint, 0);
      expect(restored.outPoint, 10);
      expect(restored.volume, 1.0);
      expect(restored.fadeIn, 0.0);
      expect(restored.fadeOut, 0.0);
    });

    test('copyWith only overrides given fields and keeps the id', () {
      final clip = AudioClip(sourcePath: '/a.mp3', sourceDuration: 10);
      final edited = clip.copyWith(start: 3, volume: 0.5);

      expect(edited.id, clip.id);
      expect(edited.start, 3);
      expect(edited.volume, 0.5);
      expect(edited.sourcePath, '/a.mp3');
      expect(edited.outPoint, 10);
    });

    test('duration is outPoint minus inPoint, clamped to source bounds', () {
      final clip =
          AudioClip(sourcePath: '/a.mp3', sourceDuration: 10, outPoint: 10);
      expect(clip.duration, 10);
      final trimmed = clip.copyWith(inPoint: 2, outPoint: 7);
      expect(trimmed.duration, 5);
    });

    test('fileName strips the directory from sourcePath', () {
      expect(AudioClip(sourcePath: '/a/b/song.mp3', sourceDuration: 1).fileName,
          'song.mp3');
    });
  });

  group('AudioClips notifier', () {
    late ProviderContainer container;
    late AudioClips notifier;

    setUp(() {
      container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(_FakeEngine())],
      );
      notifier = container.read(audioClipsProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(container.read(audioClipsProvider), isEmpty);
    });

    test('addFromPath probes duration and appends a new clip', () async {
      final added = await notifier.addFromPath('/music/track.mp3');
      final state = container.read(audioClipsProvider);

      expect(state.length, 1);
      expect(state.first, added);
      expect(added.sourcePath, '/music/track.mp3');
      expect(added.sourceDuration, 42.0);
      expect(added.start, 0);
    });

    test('addFromPath honors a custom start', () async {
      final added =
          await notifier.addFromPath('/music/track.mp3', start: 12.5);
      expect(added.start, 12.5);
    });

    test('update replaces the clip at the given index', () async {
      await notifier.addFromPath('/a.mp3');
      await notifier.addFromPath('/b.mp3');
      final second = container.read(audioClipsProvider)[1];

      notifier.update(1, second.copyWith(start: 9));

      expect(container.read(audioClipsProvider)[1].start, 9);
      expect(container.read(audioClipsProvider)[0].start, isNot(9));
    });

    test('update ignores an out-of-range index', () async {
      await notifier.addFromPath('/a.mp3');
      final before = container.read(audioClipsProvider);
      notifier.update(5, before.first.copyWith(start: 99));
      expect(container.read(audioClipsProvider), before);
    });

    test('removeAt deletes the clip at the given index', () async {
      await notifier.addFromPath('/a.mp3');
      await notifier.addFromPath('/b.mp3');
      notifier.removeAt(0);
      expect(container.read(audioClipsProvider).length, 1);
    });

    test('removeAt ignores an out-of-range index', () async {
      await notifier.addFromPath('/a.mp3');
      notifier.removeAt(99);
      expect(container.read(audioClipsProvider).length, 1);
    });

    test('load replaces the whole list (used when opening a project)', () {
      final fresh = [
        AudioClip(sourcePath: '/from/manifest.mp3', sourceDuration: 5),
      ];
      notifier.load(fresh);
      expect(container.read(audioClipsProvider), fresh);
    });
  });

  group('SelectedAudioClip notifier', () {
    test('starts at null and can be set/cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedAudioClipProvider.notifier);

      expect(container.read(selectedAudioClipProvider), isNull);
      notifier.set('abc');
      expect(container.read(selectedAudioClipProvider), 'abc');
      notifier.set(null);
      expect(container.read(selectedAudioClipProvider), isNull);
    });
  });
}
