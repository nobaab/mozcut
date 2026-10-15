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
}
