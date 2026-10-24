import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/color_filter_presets.dart';
import 'package:mozcut/ui/features/editor/views/filters_panel.dart';

/// Pure tests of the filter-name -> ffmpeg-params map used by both the
/// Filters panel (selection UI) and FfmpegEngine (export). No widgets, no
/// ffmpeg process involved.
void main() {
  test('every non-Adjust preset in the Filters panel catalogue has a '
      'mapped ffmpeg transform', () {
    for (final filter in kFilterCatalogue) {
      if (filter.name == 'Adjust') continue;
      expect(kColorFilterPresets.containsKey(filter.name), isTrue,
          reason: '"${filter.name}" has no entry in kColorFilterPresets');
    }
  });

  test('the Adjust preset is deliberately not in the map (it opens the '
      'manual Adjustment tab instead)', () {
    expect(kColorFilterPresets.containsKey('Adjust'), isFalse);
  });

  test('ffmpegFilterChain renders brightness/contrast/saturation/gamma into '
      'an eq= clause', () {
    const preset = ColorFilterPreset(
      brightness: 0.1,
      contrast: 1.25,
      saturation: 0.5,
      gamma: 1.1,
    );
    expect(preset.ffmpegFilterChain,
        'eq=brightness=0.100:contrast=1.250:saturation=0.500:gamma=1.100');
  });

  test('ffmpegFilterChain appends a colorbalance stage when set', () {
    const preset = ColorFilterPreset(
      contrast: 1.1,
      colorBalance: 'rs=0.1:bs=-0.1',
    );
    expect(
        preset.ffmpegFilterChain,
        'eq=brightness=0.000:contrast=1.100:saturation=1.000:gamma=1.000,'
        'colorbalance=rs=0.1:bs=-0.1');
  });

  test('a default ColorFilterPreset is the neutral eq (no-op) transform', () {
    const preset = ColorFilterPreset();
    expect(preset.ffmpegFilterChain,
        'eq=brightness=0.000:contrast=1.000:saturation=1.000:gamma=1.000');
  });

  test('known presets carry distinct, intentional looks (not all defaults)',
      () {
    final noir = kColorFilterPresets['Noir']!;
    expect(noir.saturation, 0.0); // black & white
    expect(noir.contrast, greaterThan(1.0));

    final tealOrange = kColorFilterPresets['Teal & Orange']!;
    expect(tealOrange.colorBalance, isNotNull);

    final vivid = kColorFilterPresets['Vivid']!;
    expect(vivid.saturation, greaterThan(1.0));
  });

  group('ffmpegFilterChainFor (intensity-scaled)', () {
    test('intensity 1.0 is byte-identical to ffmpegFilterChain, with no '
        'colorbalance', () {
      const preset = ColorFilterPreset(
          brightness: 0.1, contrast: 1.25, saturation: 0.5, gamma: 1.1);
      expect(preset.ffmpegFilterChainFor(1.0), preset.ffmpegFilterChain);
    });

    test('intensity 1.0 is byte-identical to ffmpegFilterChain, with '
        'colorbalance', () {
      final preset = kColorFilterPresets['Teal & Orange']!;
      expect(preset.ffmpegFilterChainFor(1.0), preset.ffmpegFilterChain);
    });

    test('every catalogue preset matches at intensity 1.0', () {
      for (final preset in kColorFilterPresets.values) {
        expect(preset.ffmpegFilterChainFor(1.0), preset.ffmpegFilterChain,
            reason: 'mismatch at intensity 1.0');
      }
    });

    test('intensity 0.0 reduces brightness/contrast/saturation/gamma to '
        'neutral (no-op) values', () {
      const preset = ColorFilterPreset(
          brightness: 0.1, contrast: 1.25, saturation: 0.5, gamma: 1.1);
      expect(preset.ffmpegFilterChainFor(0.0),
          'eq=brightness=0.000:contrast=1.000:saturation=1.000:gamma=1.000');
    });

    test('intensity 0.0 zeroes out every colorbalance component', () {
      const preset =
          ColorFilterPreset(contrast: 1.1, colorBalance: 'rs=0.1:bs=-0.1');
      // -0.1 * 0.0 == -0.0 in IEEE754, which toStringAsFixed renders with a
      // leading sign — numerically zero either way.
      expect(preset.ffmpegFilterChainFor(0.0),
          'eq=brightness=0.000:contrast=1.000:saturation=1.000:gamma=1.000,'
          'colorbalance=rs=0.000:bs=-0.000');
    });

    test('an intermediate intensity linearly interpolates toward neutral',
        () {
      const preset = ColorFilterPreset(brightness: 0.2, contrast: 1.4);
      expect(preset.ffmpegFilterChainFor(0.5),
          'eq=brightness=0.100:contrast=1.200:saturation=1.000:gamma=1.000');
    });

    test('out-of-range intensities are clamped to 0..1', () {
      const preset = ColorFilterPreset(brightness: 0.2);
      expect(
          preset.ffmpegFilterChainFor(-5.0), preset.ffmpegFilterChainFor(0.0));
      expect(
          preset.ffmpegFilterChainFor(5.0), preset.ffmpegFilterChainFor(1.0));
    });
  });
}
