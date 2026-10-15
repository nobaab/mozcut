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

  test('speed defaults to 1.0 and does not change duration', () {
    final clip = Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10);
    expect(clip.speed, 1.0);
    expect(clip.duration, 10);
  });

  test('duration is the trimmed region divided by speed', () {
    final clip =
        Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10, outPoint: 10);

    final fast = clip.copyWith(speed: 2.0);
    expect(fast.duration, closeTo(5, 0.001));

    final slow = clip.copyWith(speed: 0.5);
    expect(slow.duration, closeTo(20, 0.001));

    final trimmedAndFast =
        clip.copyWith(inPoint: 2, outPoint: 6, speed: 4.0); // 4s trimmed
    expect(trimmedAndFast.duration, closeTo(1, 0.001));
  });

  test('speed round-trips through toJson/fromJson', () {
    final clip =
        Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10, speed: 1.5);
    final restored = Clip.fromJson(clip.toJson());
    expect(restored.speed, 1.5);
  });

  test('fromJson defaults speed to 1.0 when absent (older projects)', () {
    final json = Clip(sourcePath: '/tmp/a.mp4', sourceDuration: 10).toJson()
      ..remove('speed');
    final restored = Clip.fromJson(json);
    expect(restored.speed, 1.0);
  });
}
