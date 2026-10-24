/// A concrete colour transform for one named filter preset shown in the
/// Filters panel (`lib/ui/features/editor/views/filters_panel.dart`'s
/// `_kFilters` catalogue). Expressed directly in ffmpeg's own units so
/// [ffmpegFilterChain] can be dropped straight into a filtergraph:
/// - [brightness]/[contrast]/[saturation]/[gamma] feed ffmpeg's `eq` filter.
/// - [colorBalance], when set, is the argument string for ffmpeg's
///   `colorbalance` filter (e.g. `'rs=0.1:bs=-0.1'`), applied after `eq` to
///   give the look a colour cast (teal shadows, warm highlights, etc.).
class ColorFilterPreset {
  const ColorFilterPreset({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.gamma = 1.0,
    this.colorBalance,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double gamma;
  final String? colorBalance;

  /// The `eq=...[,colorbalance=...]` filtergraph fragment for this preset —
  /// no surrounding brackets/labels; callers chain it into their own graph.
  String get ffmpegFilterChain {
    final eq = 'eq=brightness=${_n(brightness)}:contrast=${_n(contrast)}:'
        'saturation=${_n(saturation)}:gamma=${_n(gamma)}';
    return colorBalance == null ? eq : '$eq,colorbalance=$colorBalance';
  }

  /// [ffmpegFilterChain] scaled by [intensity] (0..1 — see
  /// `Clip.filterIntensity`): at 1.0 (the default, and the only value that
  /// existed before intensity was added) this returns exactly
  /// [ffmpegFilterChain]'s output, byte for byte. Below that,
  /// brightness/contrast/saturation/gamma are linearly interpolated toward
  /// their neutral (no-op) values — 0 for brightness, 1.0 for the
  /// multipliers — and every numeric component of [colorBalance] is scaled
  /// toward 0, so intensity 0 reproduces the untouched source exactly.
  String ffmpegFilterChainFor(double intensity) {
    final i = intensity.clamp(0.0, 1.0);
    if (i >= 1.0) return ffmpegFilterChain;
    final eq = 'eq=brightness=${_n(brightness * i)}:'
        'contrast=${_n(1.0 + (contrast - 1.0) * i)}:'
        'saturation=${_n(1.0 + (saturation - 1.0) * i)}:'
        'gamma=${_n(1.0 + (gamma - 1.0) * i)}';
    if (colorBalance == null) return eq;
    return '$eq,colorbalance=${_scaleColorBalance(colorBalance!, i)}';
  }

  static String _n(double v) => v.toStringAsFixed(3);

  /// Scales every `key=value` component of a `colorbalance` argument string
  /// (e.g. `'rs=0.1:bs=-0.1'`) by [i], reformatting each value with [_n] —
  /// only reached below full intensity, where no test depends on matching
  /// the original (hand-written, variable-precision) literal formatting.
  static String _scaleColorBalance(String spec, double i) {
    return spec.split(':').map((pair) {
      final eq = pair.indexOf('=');
      final key = pair.substring(0, eq);
      final value = double.parse(pair.substring(eq + 1));
      return '$key=${_n(value * i)}';
    }).join(':');
  }
}

/// Preset name -> concrete transform, for every entry in the Filters panel
/// catalogue except `'Adjust'` (which opens the manual Adjustment inspector
/// tab instead of applying a canned look — see filters_panel.dart). Kept here
/// as the single source of truth so the panel (which only needs the name, for
/// its "selected" state) and the export engine (which needs the real ffmpeg
/// params) can never drift apart.
const kColorFilterPresets = <String, ColorFilterPreset>{
  // ── Cinematic ──
  'Bleach Bypass': ColorFilterPreset(
      contrast: 1.35, saturation: 0.25, colorBalance: 'rs=0.05:gs=0.05:bs=0.05'),
  'Cool Blue': ColorFilterPreset(
      contrast: 1.1, saturation: 0.9, colorBalance: 'bs=0.18:bm=0.12:bh=0.06'),
  'Cyberpunk': ColorFilterPreset(
      contrast: 1.25,
      saturation: 1.45,
      colorBalance: 'rs=-0.15:bs=0.25:rh=0.1:bh=0.2'),
  'Daydream': ColorFilterPreset(
      brightness: 0.04,
      contrast: 0.9,
      saturation: 1.1,
      colorBalance: 'rh=0.08:gh=0.04:bs=0.06'),
  'Film': ColorFilterPreset(
      contrast: 1.08, saturation: 0.85, gamma: 1.05, colorBalance: 'rm=0.04:bm=-0.03'),
  'Midnight': ColorFilterPreset(
      brightness: -0.08,
      contrast: 1.15,
      saturation: 0.8,
      colorBalance: 'bs=0.15:bm=0.08'),
  'Moody': ColorFilterPreset(
      brightness: -0.04,
      contrast: 1.2,
      saturation: 0.7,
      colorBalance: 'rs=-0.05:bs=0.08'),
  'Night': ColorFilterPreset(
      brightness: -0.12,
      contrast: 1.2,
      saturation: 0.75,
      colorBalance: 'bs=0.2:bm=0.1'),
  'Noir': ColorFilterPreset(contrast: 1.4, saturation: 0.0, gamma: 1.1),
  'Rain': ColorFilterPreset(
      contrast: 1.05,
      saturation: 0.6,
      colorBalance: 'bs=0.1:gm=0.04:bm=0.06'),
  'Sage': ColorFilterPreset(
      contrast: 1.05,
      saturation: 0.75,
      colorBalance: 'gs=0.08:gm=0.08:rh=-0.03'),
  'Sci-Fi': ColorFilterPreset(
      contrast: 1.3,
      saturation: 1.1,
      colorBalance: 'bs=0.22:gs=0.08:rh=-0.08'),
  'Teal & Orange': ColorFilterPreset(
      contrast: 1.15,
      saturation: 1.15,
      colorBalance: 'bs=0.18:gs=0.06:rh=0.18:gh=0.06'),

  // ── Everyday ──
  'Clean': ColorFilterPreset(contrast: 1.05, saturation: 1.0),
  'Cloudless Sky': ColorFilterPreset(
      contrast: 1.1, saturation: 1.2, colorBalance: 'bh=0.12:bm=0.06'),
  'Fresh': ColorFilterPreset(brightness: 0.03, contrast: 1.05, saturation: 1.15),
  'Golden Hour': ColorFilterPreset(
      brightness: 0.04,
      contrast: 1.05,
      saturation: 1.2,
      colorBalance: 'rh=0.16:gh=0.08:bh=-0.08'),
  'Ivory': ColorFilterPreset(
      brightness: 0.05, contrast: 0.95, saturation: 0.85, gamma: 1.05),
  'Lagoon': ColorFilterPreset(
      contrast: 1.1, saturation: 1.2, colorBalance: 'bs=0.1:bm=0.14:gh=0.04'),
  'Milk': ColorFilterPreset(
      brightness: 0.08, contrast: 0.85, saturation: 0.8, gamma: 1.1),
  'Soft Light': ColorFilterPreset(
      brightness: 0.03, contrast: 0.9, saturation: 0.95, gamma: 1.05),
  'Umber': ColorFilterPreset(
      contrast: 1.05,
      saturation: 0.9,
      colorBalance: 'rm=0.08:gm=0.03:bm=-0.06'),
  'Vivid': ColorFilterPreset(contrast: 1.2, saturation: 1.5),

  // ── Color ──
  'Contrast Pop': ColorFilterPreset(contrast: 1.35, saturation: 1.1),
  'Cool': ColorFilterPreset(saturation: 1.05, colorBalance: 'bs=0.12:bm=0.1:bh=0.08'),
  'Vibrance': ColorFilterPreset(contrast: 1.1, saturation: 1.6),
  'Warm': ColorFilterPreset(
      saturation: 1.1, colorBalance: 'rh=0.14:rm=0.08:bh=-0.08'),

  // ── B&W ──
  'High-Contrast Mono': ColorFilterPreset(contrast: 1.5, saturation: 0.0),
  'Silver': ColorFilterPreset(contrast: 1.15, saturation: 0.05, gamma: 1.05),

  // ── Film ──
  'Classic Chrome': ColorFilterPreset(
      contrast: 1.15,
      saturation: 0.75,
      colorBalance: 'gm=0.04:bm=-0.04'),
  'Retro 70s': ColorFilterPreset(
      brightness: 0.03,
      contrast: 0.95,
      saturation: 0.85,
      colorBalance: 'rh=0.1:gh=0.06:bs=-0.04'),
  'Super 8': ColorFilterPreset(
      contrast: 1.1,
      saturation: 0.8,
      gamma: 1.08,
      colorBalance: 'rm=0.06:gm=0.02:bh=-0.06'),

  // ── Retro ──
  'Bronze': ColorFilterPreset(
      contrast: 1.1,
      saturation: 0.9,
      colorBalance: 'rh=0.14:gm=0.05:bh=-0.1'),
  'Digicam': ColorFilterPreset(
      brightness: 0.02, contrast: 1.2, saturation: 1.25, gamma: 0.95),
  'Falling Dust': ColorFilterPreset(
      brightness: 0.04,
      contrast: 0.9,
      saturation: 0.7,
      colorBalance: 'rh=0.08:gh=0.05'),
  'Mono': ColorFilterPreset(contrast: 1.1, saturation: 0.0),
  'Polaroid': ColorFilterPreset(
      brightness: 0.05,
      contrast: 0.9,
      saturation: 0.85,
      colorBalance: 'rh=0.06:bs=0.05'),
  'VHS': ColorFilterPreset(
      contrast: 0.95,
      saturation: 1.1,
      colorBalance: 'rs=0.06:bs=0.08:gh=-0.03'),
  'Vintage': ColorFilterPreset(
      brightness: 0.03,
      contrast: 0.9,
      saturation: 0.65,
      gamma: 1.05,
      colorBalance: 'rh=0.1:bm=-0.05'),

  // ── Portrait ──
  'Fair': ColorFilterPreset(brightness: 0.06, contrast: 0.95, saturation: 0.95),
  'Natural': ColorFilterPreset(contrast: 1.02, saturation: 1.05),
  'Peach': ColorFilterPreset(
      brightness: 0.03,
      saturation: 1.05,
      colorBalance: 'rh=0.1:gm=0.03:bs=-0.03'),
  'Rosy': ColorFilterPreset(
      brightness: 0.02,
      saturation: 1.1,
      colorBalance: 'rh=0.12:rm=0.05'),

  // ── Scenery ──
  'Autumn': ColorFilterPreset(
      contrast: 1.1,
      saturation: 1.2,
      colorBalance: 'rh=0.14:gh=0.04:bh=-0.1'),
  'Tropical': ColorFilterPreset(contrast: 1.15, saturation: 1.4,
      colorBalance: 'gh=0.08:bh=0.1'),
  'Vivid Landscape': ColorFilterPreset(contrast: 1.25, saturation: 1.45),
  'Winter Cool': ColorFilterPreset(
      contrast: 1.05,
      saturation: 0.85,
      colorBalance: 'bs=0.14:bm=0.1:rh=-0.05'),

  // ── Stylised ──
  'Marquee': ColorFilterPreset(contrast: 1.3, saturation: 1.3,
      colorBalance: 'rh=0.1:bh=0.1'),
  'Matcha': ColorFilterPreset(
      contrast: 1.05,
      saturation: 1.1,
      colorBalance: 'gs=0.1:gm=0.1:rh=-0.04'),
  'Neon': ColorFilterPreset(
      contrast: 1.35,
      saturation: 1.6,
      colorBalance: 'rh=0.12:bh=0.18:gs=-0.05'),
  'Pink Fuzz': ColorFilterPreset(
      brightness: 0.03,
      saturation: 1.15,
      colorBalance: 'rh=0.16:bh=0.08'),
  'Retro Cartoon': ColorFilterPreset(contrast: 1.4, saturation: 1.5, gamma: 0.95),
  'Spooky': ColorFilterPreset(
      brightness: -0.08,
      contrast: 1.25,
      saturation: 0.55,
      colorBalance: 'gs=0.06:bs=0.1'),

  // ── Vibe ──
  'Dreamy': ColorFilterPreset(
      brightness: 0.05, contrast: 0.85, saturation: 1.05, gamma: 1.08),
  'Vaporwave': ColorFilterPreset(
      contrast: 1.1,
      saturation: 1.35,
      colorBalance: 'rh=0.14:bh=0.2:gs=-0.06'),

  // ── Food ──
  'Delicious': ColorFilterPreset(
      contrast: 1.15,
      saturation: 1.35,
      colorBalance: 'rh=0.1:gh=0.04'),
};
