/// Named aspect-ratio presets for the player/project "Ratio" control — maps a
/// ratio label to the standard, even pixel dimensions CapCut's Ratio dropdown
/// offers. See docs/CAPCUT-SPEC.md §11.3.
///
/// "Original" (match the first clip's probed aspect) and "Custom" (free W×H)
/// aren't fixed sizes, so they aren't represented here — the Ratio UI handles
/// them separately and calls [evenClamp] on whatever size it resolves.
class AspectPreset {
  const AspectPreset(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

/// The eight standard ratios offered by the Ratio control, in display order.
const kAspectPresets = [
  AspectPreset('16:9', 1920, 1080),
  AspectPreset('9:16', 1080, 1920),
  AspectPreset('1:1', 1080, 1080),
  AspectPreset('4:5', 1080, 1350),
  AspectPreset('5:4', 1350, 1080),
  AspectPreset('4:3', 1440, 1080),
  AspectPreset('3:4', 1080, 1440),
  AspectPreset('21:9', 2560, 1080),
];

/// Clamps [value] to [min]..[max], then rounds down to the nearest even
/// number — libx264 requires even frame dimensions, and this is the one
/// place every canvas-dimension input (presets, the "Original" probe, Custom
/// fields) funnels through before it reaches a [VideoSettings].
int evenClamp(int value, {int min = 16, int max = 7680}) {
  final clamped = value.clamp(min, max);
  return clamped.isEven ? clamped : clamped - 1;
}

/// The ratio label to show for a given canvas size: the matching preset's
/// name if [width]x[height] is exactly one of [kAspectPresets], otherwise the
/// reduced W:H fraction (e.g. a probed "Original" canvas, or a Custom size
/// that doesn't happen to match a preset).
String ratioLabelFor(int width, int height) {
  for (final p in kAspectPresets) {
    if (p.width == width && p.height == height) return p.label;
  }
  if (width <= 0 || height <= 0) return '$width:$height';
  final g = _gcd(width, height);
  return '${width ~/ g}:${height ~/ g}';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
