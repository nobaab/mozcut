import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/media_type.dart';

/// Covers the transition fields on [Clip]: defaults, copyWith, and the
/// toJson/fromJson round-trip (including old-manifest back-compat, matching
/// the pattern every other Clip field follows).
void main() {
  group('Clip transition fields', () {
    test('default to no transition and a 0.5s duration', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.transitionId, isNull);
      expect(clip.transitionDuration, 0.5);
    });

    test('copyWith sets transitionId and transitionDuration', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final updated =
          clip.copyWith(transitionId: 'Dissolve', transitionDuration: 1.2);
      expect(updated.transitionId, 'Dissolve');
      expect(updated.transitionDuration, 1.2);
    });

    test('copyWith clearTransitionId clears it back to null', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(transitionId: 'Push');
      final cleared = clip.copyWith(clearTransitionId: true);
      expect(cleared.transitionId, isNull);
    });

    test('toJson/fromJson round-trips transitionId and transitionDuration',
        () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(transitionId: 'Zoom', transitionDuration: 0.8);
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.transitionId, 'Zoom');
      expect(restored.transitionDuration, 0.8);
    });

    test('fromJson defaults to no transition when keys are absent '
        '(old manifests)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson()
        ..remove('transitionId')
        ..remove('transitionDuration');
      final restored = Clip.fromJson(json);
      expect(restored.transitionId, isNull);
      expect(restored.transitionDuration, 0.5);
    });
  });

  group('Clip AI upscale fields', () {
    test('originalSourcePath defaults to null', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.originalSourcePath, isNull);
    });

    test('copyWith can swap sourcePath/sourceDuration and record '
        'originalSourcePath (what Editor.applyUpscale does)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final upscaled = clip.copyWith(
        sourcePath: '/upscaled.mp4',
        sourceDuration: 20,
        inPoint: 0,
        outPoint: 20,
        originalSourcePath: clip.originalSourcePath ?? clip.sourcePath,
      );
      expect(upscaled.sourcePath, '/upscaled.mp4');
      expect(upscaled.sourceDuration, 20);
      expect(upscaled.inPoint, 0);
      expect(upscaled.outPoint, 20);
      expect(upscaled.originalSourcePath, '/a.mp4');
      // id is preserved across the swap, same as every other copyWith.
      expect(upscaled.id, clip.id);
    });

    test('a second upscale does not overwrite the true original', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final onceUpscaled = clip.copyWith(
        sourcePath: '/upscaled1.mp4',
        originalSourcePath: clip.originalSourcePath ?? clip.sourcePath,
      );
      final twiceUpscaled = onceUpscaled.copyWith(
        sourcePath: '/upscaled2.mp4',
        originalSourcePath:
            onceUpscaled.originalSourcePath ?? onceUpscaled.sourcePath,
      );
      expect(twiceUpscaled.originalSourcePath, '/a.mp4');
    });

    test('copyWith clearOriginalSourcePath clears it back to null', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(originalSourcePath: '/original.mp4');
      final cleared = clip.copyWith(clearOriginalSourcePath: true);
      expect(cleared.originalSourcePath, isNull);
    });

    test('toJson/fromJson round-trips originalSourcePath', () {
      final clip = Clip(sourcePath: '/upscaled.mp4', sourceDuration: 10)
          .copyWith(originalSourcePath: '/original.mp4');
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.originalSourcePath, '/original.mp4');
    });

    test('fromJson defaults originalSourcePath to null when the key is '
        'absent (old manifests)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson()..remove('originalSourcePath');
      final restored = Clip.fromJson(json);
      expect(restored.originalSourcePath, isNull);
    });
  });

  group('Clip mediaType field', () {
    test('defaults to video', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.mediaType, MediaType.video);
      expect(clip.isImage, isFalse);
    });

    test('can be constructed as an image clip', () {
      final clip = Clip(
        sourcePath: '/a.jpg',
        sourceDuration: kImageSourceDurationCap,
        outPoint: kImageDefaultDuration,
        mediaType: MediaType.image,
      );
      expect(clip.mediaType, MediaType.image);
      expect(clip.isImage, isTrue);
      expect(clip.duration, kImageDefaultDuration);
    });

    test('copyWith preserves mediaType by default and can override it', () {
      final clip = Clip(
          sourcePath: '/a.jpg', sourceDuration: 10, mediaType: MediaType.image);
      final unchanged = clip.copyWith(scale: 2.0);
      expect(unchanged.mediaType, MediaType.image);

      final changed = clip.copyWith(mediaType: MediaType.video);
      expect(changed.mediaType, MediaType.video);
    });

    test('toJson/fromJson round-trips mediaType', () {
      final clip = Clip(
          sourcePath: '/a.jpg', sourceDuration: 10, mediaType: MediaType.image);
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.mediaType, MediaType.image);
    });

    test('fromJson defaults mediaType to video when the key is absent '
        '(old manifests)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson()..remove('mediaType');
      final restored = Clip.fromJson(json);
      expect(restored.mediaType, MediaType.video);
    });
  });

  group('Clip animation fields', () {
    test('default to no animation and a 0.5s duration', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.animationIn, isNull);
      expect(clip.animationOut, isNull);
      expect(clip.animationInDuration, kAnimationDefaultDuration);
      expect(clip.animationOutDuration, kAnimationDefaultDuration);
    });

    test('copyWith sets animationIn/Out and their durations', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10).copyWith(
        animationIn: kAnimFade,
        animationInDuration: 1.0,
        animationOut: kAnimZoomOut,
        animationOutDuration: 0.3,
      );
      expect(clip.animationIn, kAnimFade);
      expect(clip.animationInDuration, 1.0);
      expect(clip.animationOut, kAnimZoomOut);
      expect(clip.animationOutDuration, 0.3);
    });

    test('copyWith clearAnimationIn/Out clear them back to null', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10).copyWith(
        animationIn: kAnimFade,
        animationOut: kAnimFade,
      );
      final cleared =
          clip.copyWith(clearAnimationIn: true, clearAnimationOut: true);
      expect(cleared.animationIn, isNull);
      expect(cleared.animationOut, isNull);
    });

    test('toJson/fromJson round-trips animationIn/Out and their durations',
        () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10).copyWith(
        animationIn: kAnimSlideLeft,
        animationInDuration: 0.8,
        animationOut: kAnimFade,
        animationOutDuration: 1.5,
      );
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.animationIn, kAnimSlideLeft);
      expect(restored.animationInDuration, 0.8);
      expect(restored.animationOut, kAnimFade);
      expect(restored.animationOutDuration, 1.5);
    });

    test('an unanimated clip omits animation keys from its JSON '
        '(byte-for-byte pre-feature output)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson();
      expect(json.containsKey('animationIn'), isFalse);
      expect(json.containsKey('animationInDuration'), isFalse);
      expect(json.containsKey('animationOut'), isFalse);
      expect(json.containsKey('animationOutDuration'), isFalse);
    });

    test('fromJson defaults to no animation when keys are absent '
        '(old manifests)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(animationIn: kAnimFade);
      final json = clip.toJson()
        ..remove('animationIn')
        ..remove('animationInDuration');
      final restored = Clip.fromJson(json);
      expect(restored.animationIn, isNull);
      expect(restored.animationInDuration, kAnimationDefaultDuration);
    });
  });
}
