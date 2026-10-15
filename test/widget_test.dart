import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/domain/models/clip.dart';

void main() {
  test('Clip duration is the trimmed region', () {
    final clip = Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10);
    expect(clip.duration, 10);

    final trimmed = clip.copyWith(inPoint: 2, outPoint: 7);
    expect(trimmed.duration, 5);
  });

  test('fileName is the last path segment', () {
    final clip = Clip(sourcePath: '/Users/x/My Videos/clip one.mp4', sourceDuration: 3);
    expect(clip.fileName, 'clip one.mp4');
  });

  test('transform defaults to identity', () {
    final clip = Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10);
    expect(clip.scale, 1.0);
    expect(clip.posX, 0.0);
    expect(clip.posY, 0.0);
    expect(clip.rotation, 0.0);
    expect(clip.flipH, isFalse);
  });

  test('transform round-trips through toJson/fromJson', () {
    final clip = Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10).copyWith(
      scale: 1.5,
      posX: -0.25,
      posY: 0.75,
      rotation: 90,
      flipH: true,
    );

    final restored = Clip.fromJson(clip.toJson());

    expect(restored.scale, 1.5);
    expect(restored.posX, -0.25);
    expect(restored.posY, 0.75);
    expect(restored.rotation, 90);
    expect(restored.flipH, isTrue);
  });

  test('fromJson falls back to identity transform when keys are missing', () {
    // Simulates a project saved before transform support existed.
    final json = {
      'id': 'abc',
      'sourcePath': '/tmp/a.mp4',
      'sourceDuration': 10.0,
      'inPoint': 0.0,
      'outPoint': 10.0,
    };

    final clip = Clip.fromJson(json);

    expect(clip.scale, 1.0);
    expect(clip.posX, 0.0);
    expect(clip.posY, 0.0);
    expect(clip.rotation, 0.0);
    expect(clip.flipH, isFalse);
  });
}
