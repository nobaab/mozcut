import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/aspect_presets.dart';

void main() {
  test('kAspectPresets maps each standard ratio to its spec\'d even dimensions', () {
    const expected = {
      '16:9': (1920, 1080),
      '9:16': (1080, 1920),
      '1:1': (1080, 1080),
      '4:5': (1080, 1350),
      '5:4': (1350, 1080),
      '4:3': (1440, 1080),
      '3:4': (1080, 1440),
      '21:9': (2560, 1080),
    };
    expect(kAspectPresets.length, expected.length);
    for (final p in kAspectPresets) {
      final dims = expected[p.label];
      expect(dims, isNotNull, reason: 'unexpected preset "${p.label}"');
      expect(p.width, dims!.$1, reason: '${p.label} width');
      expect(p.height, dims.$2, reason: '${p.label} height');
      expect(p.width.isEven, isTrue, reason: '${p.label} width must be even');
      expect(p.height.isEven, isTrue, reason: '${p.label} height must be even');
    }
  });

  test('evenClamp rounds an odd value down to even', () {
    expect(evenClamp(1921), 1920);
    expect(evenClamp(1920), 1920);
  });

  test('evenClamp clamps to the min/max range', () {
    expect(evenClamp(5), 16);
    expect(evenClamp(10000), 7680);
    expect(evenClamp(7679), 7678); // clamped to max (odd), then snapped even
  });

  test('ratioLabelFor names an exact preset match', () {
    expect(ratioLabelFor(1920, 1080), '16:9');
    expect(ratioLabelFor(1080, 1920), '9:16');
    expect(ratioLabelFor(1080, 1080), '1:1');
    expect(ratioLabelFor(2560, 1080), '21:9');
  });

  test('ratioLabelFor reduces a non-preset size to its fraction', () {
    expect(ratioLabelFor(1280, 720), '16:9');
    expect(ratioLabelFor(640, 480), '4:3');
    expect(ratioLabelFor(100, 100), '1:1');
  });
}
