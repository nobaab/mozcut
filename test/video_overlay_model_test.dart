import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/video_overlay.dart';

void main() {
  group('VideoOverlay', () {
    test(
        'defaults: inPoint 0, outPoint == sourceDuration, startTime 0, '
        'scale 0.5, posX/posY 0.5, rotation 0, opacity 1, blendMode normal',
        () {
      final overlay =
          VideoOverlay(sourcePath: '/v/pip.mp4', sourceDuration: 8);
      expect(overlay.inPoint, 0);
      expect(overlay.outPoint, 8);
      expect(overlay.startTime, 0);
      expect(overlay.scale, 0.5);
      expect(overlay.posX, 0.5);
      expect(overlay.posY, 0.5);
      expect(overlay.rotation, 0);
      expect(overlay.opacity, 1.0);
      expect(overlay.blendMode, 'normal');
      expect(overlay.duration, 8);
    });

    test('survives a JSON round-trip', () {
      final overlay = VideoOverlay(
        sourcePath: '/v/pip.mp4',
        sourceDuration: 12,
        inPoint: 1.0,
        outPoint: 6.0,
        startTime: 3.5,
        scale: 0.35,
        posX: 0.75,
        posY: 0.2,
        rotation: 15,
        opacity: 0.6,
        blendMode: 'screen',
      );

      final restored = VideoOverlay.fromJson(overlay.toJson());

      expect(restored.id, overlay.id);
      expect(restored.sourcePath, '/v/pip.mp4');
      expect(restored.sourceDuration, 12);
      expect(restored.inPoint, 1.0);
      expect(restored.outPoint, 6.0);
      expect(restored.startTime, 3.5);
      expect(restored.scale, 0.35);
      expect(restored.posX, 0.75);
      expect(restored.posY, 0.2);
      expect(restored.rotation, 15);
      expect(restored.opacity, 0.6);
      expect(restored.blendMode, 'screen');
      expect(restored, overlay);
    });

    test(
        'fromJson fills in defaults for an old/partial manifest '
        '(backward compatibility with projects saved before this feature)',
        () {
      final restored = VideoOverlay.fromJson({
        'id': 'x',
        'sourcePath': '/v/pip.mp4',
        'sourceDuration': 10.0,
      });

      expect(restored.inPoint, 0);
      expect(restored.outPoint, 10);
      expect(restored.startTime, 0);
      expect(restored.scale, 0.5);
      expect(restored.posX, 0.5);
      expect(restored.posY, 0.5);
      expect(restored.rotation, 0);
      expect(restored.opacity, 1.0);
      expect(restored.blendMode, 'normal');
    });

    test('copyWith only overrides given fields and keeps the id', () {
      final overlay = VideoOverlay(sourcePath: '/v/pip.mp4', sourceDuration: 10);
      final edited =
          overlay.copyWith(startTime: 2, opacity: 0.5, blendMode: 'multiply');

      expect(edited.id, overlay.id);
      expect(edited.startTime, 2);
      expect(edited.opacity, 0.5);
      expect(edited.blendMode, 'multiply');
      expect(edited.sourcePath, '/v/pip.mp4');
      expect(edited.scale, 0.5);
    });

    test('duration is outPoint minus inPoint, clamped to source bounds', () {
      final overlay =
          VideoOverlay(sourcePath: '/v/pip.mp4', sourceDuration: 10, outPoint: 10);
      expect(overlay.duration, 10);
      final trimmed = overlay.copyWith(inPoint: 2, outPoint: 7);
      expect(trimmed.duration, 5);
    });

    test('fileName strips the directory from sourcePath', () {
      expect(
          VideoOverlay(sourcePath: '/a/b/pip.mp4', sourceDuration: 1).fileName,
          'pip.mp4');
    });

    test('== and hashCode compare every field', () {
      final a = VideoOverlay(
        id: 'same',
        sourcePath: '/v/pip.mp4',
        sourceDuration: 10,
        blendMode: 'darken',
      );
      final b = VideoOverlay(
        id: 'same',
        sourcePath: '/v/pip.mp4',
        sourceDuration: 10,
        blendMode: 'darken',
      );
      final c = a.copyWith(blendMode: 'lighten');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('kBlendModes / blendModeLabel', () {
    test('includes normal plus the standard compositing modes', () {
      expect(kBlendModes, contains('normal'));
      expect(kBlendModes, contains('multiply'));
      expect(kBlendModes, contains('screen'));
      expect(kBlendModes, contains('overlay'));
      expect(kBlendModes, contains('darken'));
      expect(kBlendModes, contains('lighten'));
      expect(kBlendModes, contains('difference'));
      expect(kBlendModes, contains('addition'));
    });

    test('title-cases a blend mode id for display', () {
      expect(blendModeLabel('normal'), 'Normal');
      expect(blendModeLabel('difference'), 'Difference');
    });
  });
}
