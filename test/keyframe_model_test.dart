import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/keyframe.dart';

/// Covers [Keyframe] itself, the [keyframeValueAt] interpolation helper, and
/// [Clip.valueAt]/[Clip.staticValue] — the pieces the UI and the export
/// engine both build on (see docs/CAPCUT-SPEC.md §2.6).
void main() {
  group('Keyframe', () {
    test('toJson/fromJson round-trips time and value', () {
      const kf = Keyframe(timeSec: 1.5, value: 2.0);
      final restored = Keyframe.fromJson(kf.toJson());
      expect(restored.timeSec, 1.5);
      expect(restored.value, 2.0);
    });

    test('copyWith overrides only the given field', () {
      const kf = Keyframe(timeSec: 1.0, value: 2.0);
      final moved = kf.copyWith(timeSec: 3.0);
      expect(moved.timeSec, 3.0);
      expect(moved.value, 2.0);
    });

    test('equality is value-based', () {
      expect(const Keyframe(timeSec: 1.0, value: 2.0),
          const Keyframe(timeSec: 1.0, value: 2.0));
      expect(const Keyframe(timeSec: 1.0, value: 2.0) == const Keyframe(timeSec: 1.0, value: 3.0),
          isFalse);
    });
  });

  group('keyframeValueAt', () {
    test('returns the fallback when there are no keyframes', () {
      expect(keyframeValueAt(const [], 5.0, fallback: 42.0), 42.0);
    });

    test('a single keyframe pins a constant value regardless of t', () {
      const kfs = [Keyframe(timeSec: 2.0, value: 10.0)];
      expect(keyframeValueAt(kfs, 0.0, fallback: 0.0), 10.0);
      expect(keyframeValueAt(kfs, 2.0, fallback: 0.0), 10.0);
      expect(keyframeValueAt(kfs, 100.0, fallback: 0.0), 10.0);
    });

    test('clamps to the first keyframe before it', () {
      const kfs = [
        Keyframe(timeSec: 1.0, value: 10.0),
        Keyframe(timeSec: 3.0, value: 30.0),
      ];
      expect(keyframeValueAt(kfs, 0.0, fallback: 0.0), 10.0);
      expect(keyframeValueAt(kfs, -5.0, fallback: 0.0), 10.0);
    });

    test('clamps to the last keyframe after it', () {
      const kfs = [
        Keyframe(timeSec: 1.0, value: 10.0),
        Keyframe(timeSec: 3.0, value: 30.0),
      ];
      expect(keyframeValueAt(kfs, 3.0, fallback: 0.0), 30.0);
      expect(keyframeValueAt(kfs, 99.0, fallback: 0.0), 30.0);
    });

    test('linearly interpolates between two keyframes', () {
      const kfs = [
        Keyframe(timeSec: 0.0, value: 0.0),
        Keyframe(timeSec: 2.0, value: 10.0),
      ];
      expect(keyframeValueAt(kfs, 1.0, fallback: 0.0), closeTo(5.0, 1e-9));
      expect(keyframeValueAt(kfs, 0.5, fallback: 0.0), closeTo(2.5, 1e-9));
    });

    test('interpolates across the correct segment with 3+ keyframes', () {
      const kfs = [
        Keyframe(timeSec: 0.0, value: 0.0),
        Keyframe(timeSec: 1.0, value: 100.0),
        Keyframe(timeSec: 2.0, value: 0.0),
      ];
      expect(keyframeValueAt(kfs, 0.5, fallback: 0.0), closeTo(50.0, 1e-9));
      expect(keyframeValueAt(kfs, 1.5, fallback: 0.0), closeTo(50.0, 1e-9));
      expect(keyframeValueAt(kfs, 1.0, fallback: 0.0), closeTo(100.0, 1e-9));
    });

    test('works when given keyframes out of time order', () {
      const kfs = [
        Keyframe(timeSec: 2.0, value: 10.0),
        Keyframe(timeSec: 0.0, value: 0.0),
      ];
      expect(keyframeValueAt(kfs, 1.0, fallback: 0.0), closeTo(5.0, 1e-9));
    });
  });

  group('Clip.valueAt / Clip.staticValue', () {
    test('falls back to the static field when there are no keyframes', () {
      final clip =
          Clip(sourcePath: '/a.mp4', sourceDuration: 10, scale: 2.0);
      expect(clip.valueAt(kKeyframeScale, 5.0), 2.0);
      expect(clip.staticValue(kKeyframeScale), 2.0);
    });

    test('interpolates when the property has keyframes', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10).copyWith(
        keyframes: {
          kKeyframeOpacity: const [
            Keyframe(timeSec: 0.0, value: 0.0),
            Keyframe(timeSec: 2.0, value: 1.0),
          ],
        },
      );
      expect(clip.valueAt(kKeyframeOpacity, 1.0), closeTo(0.5, 1e-9));
      // The static field is untouched — only the keyframe list drives
      // valueAt once a property is animated.
      expect(clip.opacity, 1.0);
    });

    test('an unrecognized property falls back to 0', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.staticValue('nonsense'), 0.0);
      expect(clip.valueAt('nonsense', 1.0), 0.0);
    });
  });

  group('Clip.opacity', () {
    test('defaults to 1.0 (fully opaque)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.opacity, 1.0);
    });

    test('copyWith sets it', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(opacity: 0.4);
      expect(clip.opacity, 0.4);
    });

    test('toJson/fromJson round-trips it', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10)
          .copyWith(opacity: 0.4);
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.opacity, 0.4);
    });

    test('fromJson defaults opacity to 1.0 when the key is absent '
        '(old manifests)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson()..remove('opacity');
      final restored = Clip.fromJson(json);
      expect(restored.opacity, 1.0);
    });
  });

  group('Clip.keyframes', () {
    test('defaults to empty', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.keyframes, isEmpty);
    });

    test('toJson omits the key entirely when there are no keyframes '
        '(fully additive export)', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      expect(clip.toJson().containsKey('keyframes'), isFalse);
    });

    test('toJson/fromJson round-trips a populated keyframe map', () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10).copyWith(
        keyframes: {
          kKeyframeScale: const [
            Keyframe(timeSec: 0.0, value: 1.0),
            Keyframe(timeSec: 1.0, value: 2.0),
          ],
          kKeyframeRotation: const [Keyframe(timeSec: 0.5, value: 90.0)],
        },
      );
      final restored = Clip.fromJson(clip.toJson());
      expect(restored.keyframes[kKeyframeScale], [
        const Keyframe(timeSec: 0.0, value: 1.0),
        const Keyframe(timeSec: 1.0, value: 2.0),
      ]);
      expect(restored.keyframes[kKeyframeRotation],
          [const Keyframe(timeSec: 0.5, value: 90.0)]);
    });

    test('fromJson defaults to empty when the key is absent (old manifests)',
        () {
      final clip = Clip(sourcePath: '/a.mp4', sourceDuration: 10);
      final json = clip.toJson()..remove('keyframes');
      final restored = Clip.fromJson(json);
      expect(restored.keyframes, isEmpty);
    });
  });
}
