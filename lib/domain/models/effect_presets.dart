/// Effect name (from the Effects panel catalogue —
/// `lib/ui/features/editor/views/effects_panel.dart`'s `kVideoEffects`) ->
/// the concrete ffmpeg video filter fragment it renders as on export, as a
/// function of the effect's intensity (`Clip.effectIntensity`, 0..1 — see
/// `EffectsPanel`'s intensity slider). Kept here as the single source of
/// truth so the panel (which only needs the name, for its "selected" state)
/// and the export engine (which needs the real ffmpeg filter) can never
/// drift apart — mirrors `color_filter_presets.dart`'s split for the Filters
/// tab.
///
/// Every entry special-cases intensity >= 1.0 (the default, and the only
/// value that existed before intensity was added) to return the exact same
/// literal string this map used to hold, so an unadjusted effect reproduces
/// today's export output byte for byte. Below 1.0, each preset's own numeric
/// knob(s) are linearly scaled toward a no-op/identity value (sigma -> 0,
/// an `eq` multiplier -> 1, a `colorbalance` shift -> 0, a block size -> 1,
/// etc.) so intensity 0 is indistinguishable from the effect not being
/// applied at all. Three presets have no literal numeric knob to scale:
/// - 'Curves' (a named ffmpeg `curves` preset) falls back to a plain `eq`
///   contrast boost of proportional strength below 1.0.
/// - 'Posterize' re-derives its `lutyuv` quantization step from intensity
///   (step 32 at full strength, step 1 — i.e. no quantization — at zero).
/// - 'Vignette' multiplies its `angle` expression by intensity directly
///   inside the ffmpeg expression (`PI/4*intensity`), since ffmpeg's `eval`
///   parser accepts arithmetic there.
///
/// Every value is a self-contained filter fragment with no surrounding
/// `[in][out]` labels — callers (see `FfmpegEngine._videoFilterChain`) chain
/// it straight into their own linear, comma-separated filter chain, so a
/// fragment may itself contain commas (chaining multiple ffmpeg filters) when
/// one isn't enough to approximate the effect.
///
/// A few entries (Motion Blur, Zoom Blur, Glow, Bloom Pulse, Halftone,
/// Chroma Key, White Balance) are close approximations rather than a
/// dedicated ffmpeg filter, since ffmpeg has no built-in filter for those
/// effects under that exact name, or the real thing needs a parameter (a
/// pick colour, a key colour) [Clip] doesn't carry yet.
typedef EffectPresetFn = String Function(double intensity);

/// Clamps an effect's raw [Clip.effectIntensity] into the valid 0..1 range
/// every preset function below expects.
double _ci(double intensity) => intensity.clamp(0.0, 1.0);

/// Formats a scaled filter parameter: whole numbers render with no decimal
/// point (matching how the original, fixed-strength literals in this file
/// were written, e.g. `sigma=12` not `sigma=12.0`); otherwise up to 3 decimal
/// places with trailing zeros trimmed. Only used below full intensity, where
/// no test depends on a specific literal format, just a reasonable one.
String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

const kEffectPresets = <String, EffectPresetFn>{
  'Sharpen': _sharpen,
  'Contrast': _contrast,
  'Gaussian Blur': _gaussianBlur,
  'Motion Blur': _motionBlur,
  'Zoom Blur': _zoomBlur,
  'Color Wheels': _colorWheels,
  'Curves': _curves,
  'Exposure': _exposure,
  'Saturation': _saturationEffect,
  'White Balance': _whiteBalance,
  'Chroma Key': _chromaKey,
  'Luma Key': _lumaKey,
  'Chromatic Aberration': _chromaticAberration,
  'Fisheye': _fisheye,
  'Pixelate': _pixelate,
  'Bloom Pulse': _bloomPulse,
  'Glow': _glow,
  'Film Grain': _filmGrain,
  'Vignette': _vignette,
  'Halftone': _halftone,
  'Posterize': _posterize,
};

// A short temporal mix across frames approximates a directional smear.
String _sharpen(double intensity) {
  if (intensity >= 1.0) return 'unsharp=5:5:1.0:5:5:0.0';
  final ci = _ci(intensity);
  return 'unsharp=5:5:${_fmt(1.0 * ci)}:5:5:0.0';
}

String _contrast(double intensity) {
  if (intensity >= 1.0) return 'eq=contrast=1.4';
  final ci = _ci(intensity);
  return 'eq=contrast=${_fmt(1.0 + 0.4 * ci)}';
}

String _gaussianBlur(double intensity) {
  if (intensity >= 1.0) return 'gblur=sigma=12';
  final ci = _ci(intensity);
  return 'gblur=sigma=${_fmt(12 * ci)}';
}

String _motionBlur(double intensity) {
  if (intensity >= 1.0) return 'tmix=frames=5';
  final ci = _ci(intensity);
  final frames = (1 + 4 * ci).round().clamp(1, 5);
  return 'tmix=frames=$frames';
}

// A true per-pixel radial zoom blur needs a custom shader; a strong blur
// stands in for the "soft, exploding" look.
String _zoomBlur(double intensity) {
  if (intensity >= 1.0) return 'gblur=sigma=18';
  final ci = _ci(intensity);
  return 'gblur=sigma=${_fmt(18 * ci)}';
}

String _colorWheels(double intensity) {
  if (intensity >= 1.0) return 'colorbalance=rm=0.08:gm=0.0:bm=-0.08';
  final ci = _ci(intensity);
  return 'colorbalance=rm=${_fmt(0.08 * ci)}:gm=0.0:bm=${_fmt(-0.08 * ci)}';
}

// The named `curves` preset has no numeric knob to scale, so below full
// intensity this falls back to a proportionally weaker `eq` contrast boost
// instead — a different (cheaper) filter, but one that fades out the same
// way every other preset here does.
String _curves(double intensity) {
  if (intensity >= 1.0) return 'curves=preset=increase_contrast';
  final ci = _ci(intensity);
  return 'eq=contrast=${_fmt(1.0 + 0.3 * ci)}';
}

String _exposure(double intensity) {
  if (intensity >= 1.0) return 'eq=brightness=0.12';
  final ci = _ci(intensity);
  return 'eq=brightness=${_fmt(0.12 * ci)}';
}

String _saturationEffect(double intensity) {
  if (intensity >= 1.0) return 'eq=saturation=1.6';
  final ci = _ci(intensity);
  return 'eq=saturation=${_fmt(1.0 + 0.6 * ci)}';
}

// A cool->neutral channel shift stands in for a full temperature/tint dial.
String _whiteBalance(double intensity) {
  if (intensity >= 1.0) return 'colorbalance=rs=0.08:bs=-0.08';
  final ci = _ci(intensity);
  return 'colorbalance=rs=${_fmt(0.08 * ci)}:bs=${_fmt(-0.08 * ci)}';
}

// Keys out a fixed green-screen colour; a real implementation would need a
// user-pickable colour, which Clip doesn't carry yet. Scaling `similarity`
// (and `blend`) toward 0 fades the keying out toward "nothing is keyed".
String _chromaKey(double intensity) {
  if (intensity >= 1.0) return 'colorkey=0x00ff00:0.3:0.2';
  final ci = _ci(intensity);
  return 'colorkey=0x00ff00:${_fmt(0.3 * ci)}:${_fmt(0.2 * ci)}';
}

String _lumaKey(double intensity) {
  if (intensity >= 1.0) return 'lumakey=threshold=0.2:tolerance=0.1';
  final ci = _ci(intensity);
  return 'lumakey=threshold=${_fmt(0.2 * ci)}:tolerance=${_fmt(0.1 * ci)}';
}

String _chromaticAberration(double intensity) {
  if (intensity >= 1.0) return 'rgbashift=rh=5:bh=-5';
  final ci = _ci(intensity);
  final shift = (5 * ci).round();
  return 'rgbashift=rh=$shift:bh=${-shift}';
}

String _fisheye(double intensity) {
  if (intensity >= 1.0) return 'lenscorrection=k1=0.3:k2=0.1';
  final ci = _ci(intensity);
  return 'lenscorrection=k1=${_fmt(0.3 * ci)}:k2=${_fmt(0.1 * ci)}';
}

// Block size shrinks toward 1 (no pixelation) as intensity falls.
String _pixelate(double intensity) {
  if (intensity >= 1.0) return 'pixelize=w=16:h=16';
  final ci = _ci(intensity);
  final block = (1 + 15 * ci).round();
  return 'pixelize=w=$block:h=$block';
}

// A slow sinusoidal brightness pulse plus a soft blur; ffmpeg has no
// built-in bloom filter.
String _bloomPulse(double intensity) {
  if (intensity >= 1.0) {
    return "eq=eval=frame:brightness='0.15*sin(2*PI*t)':contrast=1.05,"
        'gblur=sigma=6';
  }
  final ci = _ci(intensity);
  return "eq=eval=frame:brightness='${_fmt(0.15 * ci)}*sin(2*PI*t)':"
      'contrast=${_fmt(1.0 + 0.05 * ci)},gblur=sigma=${_fmt(6 * ci)}';
}

String _glow(double intensity) {
  if (intensity >= 1.0) return 'gblur=sigma=6,eq=brightness=0.06';
  final ci = _ci(intensity);
  return 'gblur=sigma=${_fmt(6 * ci)},eq=brightness=${_fmt(0.06 * ci)}';
}

String _filmGrain(double intensity) {
  if (intensity >= 1.0) return 'noise=alls=20:allf=t';
  final ci = _ci(intensity);
  return 'noise=alls=${(20 * ci).round()}:allf=t';
}

// `PI/4*<intensity>` multiplies ffmpeg's own `angle` expression directly —
// its `eval` parser accepts arithmetic, and angle 0 is no vignette at all.
String _vignette(double intensity) {
  if (intensity >= 1.0) return 'vignette=PI/4';
  final ci = _ci(intensity);
  return 'vignette=PI/4*${_fmt(ci)}';
}

// A blocky pixelize + desaturation approximates a halftone/dither look;
// ffmpeg has no dedicated halftone filter. Both the block size and the
// desaturation fade back toward identity as intensity falls.
String _halftone(double intensity) {
  if (intensity >= 1.0) return 'pixelize=w=10:h=10,eq=saturation=0';
  final ci = _ci(intensity);
  final block = (1 + 9 * ci).round();
  return 'pixelize=w=$block:h=$block,eq=saturation=${_fmt(1.0 - ci)}';
}

// The quantization step shrinks from 32 (strong posterization) toward 1
// (floor(val/1)*1 == val, i.e. no-op) as intensity falls.
String _posterize(double intensity) {
  if (intensity >= 1.0) {
    return "lutyuv=y='floor(val/32)*32':u='floor(val/32)*32':"
        "v='floor(val/32)*32'";
  }
  final ci = _ci(intensity);
  final n = (1 + 31 * ci).round();
  return "lutyuv=y='floor(val/$n)*$n':u='floor(val/$n)*$n':"
      "v='floor(val/$n)*$n'";
}
