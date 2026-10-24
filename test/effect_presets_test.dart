import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/effect_presets.dart';
import 'package:mozcut/ui/features/editor/views/effects_panel.dart';

/// Pure tests of the effect-name -> ffmpeg-filter function map used by both
/// the Effects panel (selection UI) and FfmpegEngine (export). No widgets,
/// no ffmpeg process involved. Mirrors test/color_filter_presets_test.dart.
///
/// Each entry is now a function of intensity (0..1, see
/// `Clip.effectIntensity`) rather than a fixed string — these tests exercise
/// both the "full intensity reproduces the pre-intensity output exactly" and
/// the "lower intensity scales toward a no-op" contracts documented in
/// effect_presets.dart.
void main() {
  test('every effect in the Effects panel catalogue has a mapped ffmpeg '
      'filter function', () {
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

  test('every preset renders a non-empty filter string at full intensity',
      () {
    for (final entry in kEffectPresets.entries) {
      expect(entry.value(1.0).trim(), isNotEmpty,
          reason: '"${entry.key}" maps to an empty filter string');
    }
  });

  test('known effects carry distinct, intentional filters at full intensity',
      () {
    expect(kEffectPresets['Gaussian Blur']!(1.0), contains('gblur'));
    expect(kEffectPresets['Sharpen']!(1.0), contains('unsharp'));
    expect(kEffectPresets['Vignette']!(1.0), contains('vignette'));
    expect(kEffectPresets['Film Grain']!(1.0), contains('noise'));
    expect(kEffectPresets['Pixelate']!(1.0), contains('pixelize'));
  });

  group('intensity 1.0 reproduces the pre-intensity fixed-strength output',
      () {
    const expectedAtFullIntensity = <String, String>{
      'Sharpen': 'unsharp=5:5:1.0:5:5:0.0',
      'Contrast': 'eq=contrast=1.4',
      'Gaussian Blur': 'gblur=sigma=12',
      'Motion Blur': 'tmix=frames=5',
      'Zoom Blur': 'gblur=sigma=18',
      'Color Wheels': 'colorbalance=rm=0.08:gm=0.0:bm=-0.08',
      'Curves': 'curves=preset=increase_contrast',
      'Exposure': 'eq=brightness=0.12',
      'Saturation': 'eq=saturation=1.6',
      'White Balance': 'colorbalance=rs=0.08:bs=-0.08',
      'Chroma Key': 'colorkey=0x00ff00:0.3:0.2',
      'Luma Key': 'lumakey=threshold=0.2:tolerance=0.1',
      'Chromatic Aberration': 'rgbashift=rh=5:bh=-5',
      'Fisheye': 'lenscorrection=k1=0.3:k2=0.1',
      'Pixelate': 'pixelize=w=16:h=16',
      'Bloom Pulse':
          "eq=eval=frame:brightness='0.15*sin(2*PI*t)':contrast=1.05,gblur=sigma=6",
      'Glow': 'gblur=sigma=6,eq=brightness=0.06',
      'Film Grain': 'noise=alls=20:allf=t',
      'Vignette': 'vignette=PI/4',
      'Halftone': 'pixelize=w=10:h=10,eq=saturation=0',
      'Posterize':
          "lutyuv=y='floor(val/32)*32':u='floor(val/32)*32':v='floor(val/32)*32'",
    };

    for (final entry in expectedAtFullIntensity.entries) {
      test('"${entry.key}" at intensity 1.0', () {
        expect(kEffectPresets[entry.key]!(1.0), entry.value);
      });
    }

    test('every catalogue effect is covered by this byte-identical check',
        () {
      expect(expectedAtFullIntensity.keys.toSet(),
          kVideoEffects.map((e) => e.name).toSet());
    });
  });

  group('intensity 0.0 reduces every preset to a no-op (or near-identity)',
      () {
    test('Gaussian/Zoom Blur sigma drops to 0', () {
      expect(kEffectPresets['Gaussian Blur']!(0.0), 'gblur=sigma=0');
      expect(kEffectPresets['Zoom Blur']!(0.0), 'gblur=sigma=0');
    });

    test('Contrast/Saturation/Exposure eq params drop to neutral', () {
      expect(kEffectPresets['Contrast']!(0.0), 'eq=contrast=1');
      expect(kEffectPresets['Saturation']!(0.0), 'eq=saturation=1');
      expect(kEffectPresets['Exposure']!(0.0), 'eq=brightness=0');
    });

    test('Color Wheels/White Balance colorbalance shifts drop to 0', () {
      expect(kEffectPresets['Color Wheels']!(0.0),
          'colorbalance=rm=0:gm=0.0:bm=0');
      expect(kEffectPresets['White Balance']!(0.0), 'colorbalance=rs=0:bs=0');
    });

    test('Posterize quantization step drops to 1 (floor(val/1)*1 == val)',
        () {
      expect(kEffectPresets['Posterize']!(0.0),
          "lutyuv=y='floor(val/1)*1':u='floor(val/1)*1':v='floor(val/1)*1'");
    });

    test('Vignette angle expression drops to 0', () {
      expect(kEffectPresets['Vignette']!(0.0), 'vignette=PI/4*0');
    });

    test('Pixelate/Halftone block size drops to 1', () {
      expect(kEffectPresets['Pixelate']!(0.0), 'pixelize=w=1:h=1');
      expect(kEffectPresets['Halftone']!(0.0),
          'pixelize=w=1:h=1,eq=saturation=1');
    });
  });

  test('intermediate intensities fall strictly between 0 and full strength '
      'for a representative sample', () {
    final half = kEffectPresets['Gaussian Blur']!(0.5);
    expect(half, 'gblur=sigma=6');
  });
}
