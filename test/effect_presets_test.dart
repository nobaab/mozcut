import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/effect_presets.dart';
import 'package:mozcut/ui/features/editor/views/effects_panel.dart';

/// Pure tests of the effect-name -> ffmpeg-filter map used by both the
/// Effects panel (selection UI) and FfmpegEngine (export). No widgets, no
/// ffmpeg process involved. Mirrors test/color_filter_presets_test.dart.
void main() {
  test('every effect in the Effects panel catalogue has a mapped ffmpeg '
      'filter', () {
    for (final effect in kVideoEffects) {
      expect(kEffectPresets.containsKey(effect.name), isTrue,
          reason: '"${effect.name}" has no entry in kEffectPresets');
    }
  });

  test('kEffectPresets has no stray entries beyond the panel catalogue', () {
    final catalogueNames = kVideoEffects.map((e) => e.name).toSet();
    for (final name in kEffectPresets.keys) {
      expect(catalogueNames.contains(name), isTrue,
          reason: '"$name" is in kEffectPresets but not in kVideoEffects');
    }
  });

  test('every mapped filter string is non-empty', () {
    for (final entry in kEffectPresets.entries) {
      expect(entry.value.trim(), isNotEmpty,
          reason: '"${entry.key}" maps to an empty filter string');
    }
  });

  test('known effects carry distinct, intentional filters', () {
    expect(kEffectPresets['Gaussian Blur'], contains('gblur'));
    expect(kEffectPresets['Sharpen'], contains('unsharp'));
    expect(kEffectPresets['Vignette'], contains('vignette'));
    expect(kEffectPresets['Film Grain'], contains('noise'));
    expect(kEffectPresets['Pixelate'], contains('pixelize'));
  });
}
