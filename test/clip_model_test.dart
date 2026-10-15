import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';

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
}
