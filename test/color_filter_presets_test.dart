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
}
