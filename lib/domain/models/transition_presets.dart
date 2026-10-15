/// Transitions-panel preset name (`lib/ui/features/editor/views/
/// transitions_panel.dart`'s catalogue, and `Clip.transitionId`) -> ffmpeg's
/// `xfade` filter `transition=` value (see
/// https://ffmpeg.org/ffmpeg-filters.html#xfade-1 for the full built-in
/// list). `xfade` doesn't have bespoke equivalents for every stylised look in
/// the panel (film grain, light leaks, RGB split, a spinning 3D cube, a
/// glitch/warp effect, …) — those map to the closest available built-in
/// transition type, and more than one preset name may map to the same
/// `xfade` type. This is the single source of truth both the panel
/// (selection UI) and `FfmpegEngine` (export) use, so they can never drift
/// apart — see test/transition_presets_test.dart.
const kTransitionPresets = <String, String>{
  // ── Dissolve ──
  'Dissolve': 'dissolve',
  'Blur Dissolve': 'hblur',
  // ── Light ──
  'Film Burn': 'fadewhite',
  'Light Leak': 'fadewhite',
  'Light Leak Flash': 'fadegrays',
  // ── Glitch ──
  'Glitch': 'pixelize',
  'Glitch Warp': 'distance',
  'RGB Split': 'squeezeh',
  // ── Slide ──
  'Push': 'slideleft',
  'Slide': 'slideright',
  'Whip Pan': 'smoothleft',
  // ── Spin ──
  'Cube': 'rectcrop',
  'Spin': 'circleopen',
  'Swirl': 'circlecrop',
  // ── Wipe ──
  'Clock Wipe': 'radial',
  'Iris': 'circleclose',
  'Linear Wipe': 'wipeleft',
  'Shape Wipe': 'rectcrop',
  // ── Zoom ──
  'Zoom': 'zoomin',
  'Zoom Blur': 'zoomin',
};

/// Every `transition` value ffmpeg's `xfade` filter accepts, used to validate
/// [kTransitionPresets] (see test/transition_presets_test.dart) — a typo'd
/// mapping that isn't one of these would be silently rejected by ffmpeg (or
/// fall back to its own default) at export time instead of failing a test.
const kXfadeTransitionTypes = <String>{
  'fade', 'fadeblack', 'fadewhite', 'distance',
  'wipeleft', 'wiperight', 'wipeup', 'wipedown',
  'slideleft', 'slideright', 'slideup', 'slidedown',
  'smoothleft', 'smoothright', 'smoothup', 'smoothdown',
  'circlecrop', 'rectcrop', 'circleclose', 'circleopen',
  'horzclose', 'horzopen', 'vertclose', 'vertopen',
  'diagbl', 'diagbr', 'diagtl', 'diagtr',
  'hlslice', 'hrslice', 'vuslice', 'vdslice',
  'pixelize', 'dissolve', 'radial', 'hblur',
  'wipetl', 'wipetr', 'wipebl', 'wipebr',
  'fadegrays', 'squeezev', 'squeezeh', 'zoomin',
  'hlwind', 'hrwind', 'vuwind', 'vdwind',
  'coverleft', 'coverright', 'coverup', 'coverdown',
  'revealleft', 'revealright', 'revealup', 'revealdown',
};

/// Fallback `xfade` type for a [kTransitionPresets] miss (e.g. a project
/// saved with a since-renamed/removed preset name) — a plain crossfade is
/// always a safe, valid choice.
const kDefaultXfadeTransition = 'fade';

/// Resolves a `Clip.transitionId` to the ffmpeg `xfade` `transition=` value
/// to use on export, falling back to [kDefaultXfadeTransition] for an
/// unrecognised id.
String xfadeTransitionFor(String transitionId) =>
    kTransitionPresets[transitionId] ?? kDefaultXfadeTransition;
