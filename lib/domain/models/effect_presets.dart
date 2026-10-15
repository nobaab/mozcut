/// Effect name (from the Effects panel catalogue —
/// `lib/ui/features/editor/views/effects_panel.dart`'s `kVideoEffects`) ->
/// the concrete ffmpeg video filter fragment it renders as on export. Kept
/// here as the single source of truth so the panel (which only needs the
/// name, for its "selected" state) and the export engine (which needs the
/// real ffmpeg filter) can never drift apart — mirrors
/// `color_filter_presets.dart`'s split for the Filters tab.
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
const kEffectPresets = <String, String>{
  'Sharpen': 'unsharp=5:5:1.0:5:5:0.0',
  'Contrast': 'eq=contrast=1.4',
  'Gaussian Blur': 'gblur=sigma=12',
  // A short temporal mix across frames approximates a directional smear.
  'Motion Blur': 'tmix=frames=5',
  // A true per-pixel radial zoom blur needs a custom shader; a strong blur
  // stands in for the "soft, exploding" look.
  'Zoom Blur': 'gblur=sigma=18',
  'Color Wheels': 'colorbalance=rm=0.08:gm=0.0:bm=-0.08',
  'Curves': 'curves=preset=increase_contrast',
  'Exposure': 'eq=brightness=0.12',
  'Saturation': 'eq=saturation=1.6',
  // A cool->neutral channel shift stands in for a full temperature/tint dial.
  'White Balance': 'colorbalance=rs=0.08:bs=-0.08',
  // Keys out a fixed green-screen colour; a real implementation would need a
  // user-pickable colour, which Clip doesn't carry yet.
  'Chroma Key': 'colorkey=0x00ff00:0.3:0.2',
  'Luma Key': 'lumakey=threshold=0.2:tolerance=0.1',
  'Chromatic Aberration': 'rgbashift=rh=5:bh=-5',
  'Fisheye': 'lenscorrection=k1=0.3:k2=0.1',
  'Pixelate': 'pixelize=w=16:h=16',
  // A slow sinusoidal brightness pulse plus a soft blur; ffmpeg has no
  // built-in bloom filter.
  'Bloom Pulse':
      "eq=eval=frame:brightness='0.15*sin(2*PI*t)':contrast=1.05,gblur=sigma=6",
  'Glow': 'gblur=sigma=6,eq=brightness=0.06',
  'Film Grain': 'noise=alls=20:allf=t',
  'Vignette': 'vignette=PI/4',
  // A blocky pixelize + desaturation approximates a halftone/dither look;
  // ffmpeg has no dedicated halftone filter.
  'Halftone': 'pixelize=w=10:h=10,eq=saturation=0',
  'Posterize':
      "lutyuv=y='floor(val/32)*32':u='floor(val/32)*32':v='floor(val/32)*32'",
};
