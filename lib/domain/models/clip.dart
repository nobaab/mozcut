import 'package:uuid/uuid.dart';

import 'caption.dart';
import 'keyframe.dart';
import 'media_type.dart';

/// Property names [Clip.keyframes] may be keyed by — one per animatable
/// transform property (see docs/CAPCUT-SPEC.md §2.6). Kept as plain string
/// constants (rather than an enum) because they're also used as JSON map
/// keys and as the `property` argument threaded through the UI/Editor.
const kKeyframeScale = 'scale';
const kKeyframePosX = 'posX';
const kKeyframePosY = 'posY';
const kKeyframeRotation = 'rotation';
const kKeyframeOpacity = 'opacity';

/// Clip-animation preset ids (the Animation tab's In/Out/Combo presets — see
/// docs/CAPCUT-SPEC.md §5.5 and `Editor.applyAnimation`). Applying one
/// generates keyframes over the first/last [Clip.animationInDuration] /
/// [Clip.animationOutDuration] seconds of the clip on whichever transform
/// property the preset animates; `kAnimNone` clears it. Plain string
/// constants (not an enum) for the same reason as the `kKeyframe*` ids above
/// — they're stored on [Clip] and threaded through the UI/Editor as values.
const kAnimNone = 'none';
const kAnimFade = 'fade';
const kAnimZoomIn = 'zoomIn';
const kAnimZoomOut = 'zoomOut';
const kAnimSlideLeft = 'slideLeft';
const kAnimSlideRight = 'slideRight';
const kAnimSlideUp = 'slideUp';
const kAnimSlideDown = 'slideDown';

/// Every selectable preset (excluding [kAnimNone], which the UI renders as
/// its own leading chip) in display order.
const kAnimationPresets = <String>[
  kAnimFade,
  kAnimZoomIn,
  kAnimZoomOut,
  kAnimSlideLeft,
  kAnimSlideRight,
  kAnimSlideUp,
  kAnimSlideDown,
];

/// Human-readable label for an animation preset id (including [kAnimNone]).
const kAnimationPresetLabels = <String, String>{
  kAnimNone: 'None',
  kAnimFade: 'Fade',
  kAnimZoomIn: 'Zoom In',
  kAnimZoomOut: 'Zoom Out',
  kAnimSlideLeft: 'Slide Left',
  kAnimSlideRight: 'Slide Right',
  kAnimSlideUp: 'Slide Up',
  kAnimSlideDown: 'Slide Down',
};

/// Default/minimum/maximum length of a clip-in/out animation, in seconds
/// (see docs/CAPCUT-SPEC.md §5.5: "default 0.5s").
const kAnimationDefaultDuration = 0.5;
const kAnimationMinDuration = 0.1;
const kAnimationMaxDuration = 3.0;

const _uuid = Uuid();

/// Default timeline length given to a freshly-imported image clip — an image
/// has no intrinsic duration, so this is the trimmable starting point (see
/// [Clip.mediaType]).
const kImageDefaultDuration = 5.0;

/// The `sourceDuration` recorded for an image clip: a large cap rather than a
/// real media length (images have none), so [Clip.outPoint] can be trimmed
/// out to a full day without ever hitting the clamp.
const kImageSourceDurationCap = 86400.0;

/// One piece of media on the timeline.
///
/// [sourcePath] is the original file on disk. [inPoint] / [outPoint] are the
/// trimmed region (in seconds) we actually use from the source. The engine
/// never mutates the source file — it only reads this region.
class Clip {
  Clip({
    String? id,
    required this.sourcePath,
    required this.sourceDuration,
    double? inPoint,
    double? outPoint,
    List<Caption>? captions,
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    double? opacity,
    bool? flipH,
    double? speed,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    double? brightness,
    double? contrast,
    double? saturation,
    this.filterId,
    double? filterIntensity,
    this.effectId,
    double? effectIntensity,
    this.transitionId,
    double? transitionDuration,
    this.originalSourcePath,
    MediaType? mediaType,
    Map<String, List<Keyframe>>? keyframes,
    this.animationIn,
    double? animationInDuration,
    this.animationOut,
    double? animationOutDuration,
  })  : id = id ?? _uuid.v4(),
        mediaType = mediaType ?? MediaType.video,
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        captions = captions ?? const [],
        scale = scale ?? 1.0,
        posX = posX ?? 0.0,
        posY = posY ?? 0.0,
        rotation = rotation ?? 0.0,
        opacity = opacity ?? 1.0,
        keyframes = keyframes == null
            ? const <String, List<Keyframe>>{}
            : Map.unmodifiable(keyframes),
        animationInDuration = animationInDuration ?? kAnimationDefaultDuration,
        animationOutDuration =
            animationOutDuration ?? kAnimationDefaultDuration,
        flipH = flipH ?? false,
        speed = speed ?? 1.0,
        volume = volume ?? 1.0,
        fadeIn = fadeIn ?? 0.0,
        fadeOut = fadeOut ?? 0.0,
        brightness = brightness ?? 0.0,
        contrast = contrast ?? 1.0,
        saturation = saturation ?? 1.0,
        filterIntensity = filterIntensity ?? 1.0,
        effectIntensity = effectIntensity ?? 1.0,
        transitionDuration = transitionDuration ?? 0.5;

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

  /// Auto-generated (or hand-edited) captions for this clip, timed relative
  /// to [inPoint]. Re-trimming after generating captions does not re-time them.
  final List<Caption> captions;

  // ── Transform ──
  // The clip is fit ("contain") into the project's output canvas preserving its
  // aspect ratio, then these are applied on top. Identity values = untransformed.

  /// Uniform scale on top of the "fit to canvas" size. 1.0 = 100%.
  double scale;

  /// Horizontal center offset as a fraction of half the canvas width
  /// (0 = centered, ±1 = flush with an edge).
  double posX;

  /// Vertical center offset as a fraction of half the canvas height.
  double posY;

  /// Rotation in degrees, clockwise.
  double rotation;

  /// Overall opacity, 0 (fully transparent) .. 1 (fully opaque, the
  /// default). Only meaningfully visible when something else shows through
  /// (an overlay track, or this clip faded to the black canvas) — see
  /// FfmpegEngine's `_videoFilterChain`.
  double opacity;

  /// Mirrors the clip horizontally.
  bool flipH;

  // ── keyframes ──
  // Per-property animation of the transform fields above — see
  // docs/CAPCUT-SPEC.md §2.6 and lib/domain/models/keyframe.dart. Keyed by
  // one of the kKeyframe* constants above; an absent key (or an empty list)
  // means that property is static, using its own field value as today.
  // Deliberately **clip-relative** (0 = start of the trimmed region) rather
  // than anchored to an absolute project timestamp, so a clip's animation
  // survives being moved/reordered on the timeline.

  /// Per-property keyframe lists. Empty (the default) for every clip created
  /// before this feature existed, and for any clip with no animation —
  /// `Clip.valueAt` falls back to the static field in that case, so export
  /// produces the exact same filtergraph as before this feature existed.
  Map<String, List<Keyframe>> keyframes;

  // ── clip animation (In/Out) ──
  // The Animation tab's presets (see docs/CAPCUT-SPEC.md §5.5) are
  // implemented as generated keyframes on the property above — these two
  // fields exist purely so the UI knows which preset (if any) is currently
  // applied to each edge and at what length, since that can't be reliably
  // inferred back out of the keyframe lists alone. Set (and cleared) only by
  // `Editor.applyAnimation`. Null means that edge has no animation, the
  // default for every clip.

  /// The preset id (a `kAnim*` constant from this file) applied to the first
  /// [animationInDuration] seconds of the clip, or null for none.
  String? animationIn;

  /// Length of [animationIn], in seconds. Meaningful only when [animationIn]
  /// is non-null, but keeps its last value (default
  /// [kAnimationDefaultDuration]) so the UI's duration slider has something
  /// sensible to show even before a preset is picked.
  double animationInDuration;

  /// The preset id applied to the last [animationOutDuration] seconds of the
  /// clip, or null for none.
  String? animationOut;

  /// Length of [animationOut], in seconds. See [animationInDuration].
  double animationOutDuration;

  // ── Speed & audio ──

  /// Playback rate of the trimmed region on the timeline. 1.0 = no-op; 2.0 is
  /// twice as fast (half the timeline length); 0.5 is half speed.
  final double speed;

  /// Audio gain. 1.0 = 100% (unchanged), 2.0 = doubled, 0 = muted.
  final double volume;

  /// Audio fade-in length from the in-point, in seconds (0 = none).
  final double fadeIn;

  /// Audio fade-out length ending at the out-point, in seconds (0 = none).
  final double fadeOut;

  // ── color / filter ──
  // Manual colour correction plus an optional named preset look (see
  // lib/domain/models/color_filter_presets.dart for the filterId -> ffmpeg
  // mapping). Neutral values (brightness 0, contrast/saturation 1.0,
  // filterId null) reproduce the pre-feature export output exactly.

  /// Manual brightness offset fed to ffmpeg's `eq` filter. 0 = unchanged;
  /// roughly -1..1.
  double brightness;

  /// Manual contrast multiplier fed to ffmpeg's `eq` filter. 1.0 = unchanged.
  double contrast;

  /// Manual saturation multiplier fed to ffmpeg's `eq` filter. 1.0 = unchanged.
  double saturation;

  /// Name of the applied filter preset (a key into [kColorFilterPresets]), or
  /// null for none. Independent of brightness/contrast/saturation above —
  /// both a preset and manual tweaks can be applied at once.
  String? filterId;

  /// Strength of [filterId], 0 (no visible effect — the untouched source) to
  /// 1 (the preset's full, nominal strength — the default, and the only
  /// value that existed before this field was added). Meaningless when
  /// [filterId] is null. See `ColorFilterPreset.ffmpegFilterChainFor`, which
  /// this is fed into on export, for how intermediate values are rendered.
  double filterIntensity;

  // ── effects ──
  // A single stylised video effect (blur, distort, grain, etc.) picked from
  // the Effects panel (`lib/ui/features/editor/views/effects_panel.dart`'s
  // `kVideoEffects` catalogue). See
  // lib/domain/models/effect_presets.dart for the effectId -> ffmpeg
  // mapping. Independent of filterId/color above — both can be applied at
  // once. Null (the default) reproduces the pre-feature export output
  // exactly.

  /// Name of the applied effect (a key into [kEffectPresets]), or null for
  /// none.
  String? effectId;

  /// Strength of [effectId], 0 (no visible effect — the untouched source) to
  /// 1 (the preset's full, nominal strength — the default, and the only
  /// value that existed before this field was added). Meaningless when
  /// [effectId] is null. [kEffectPresets] entries are functions of this
  /// value (see `effect_presets.dart`), fed in on export.
  double effectIntensity;

  // ── transition ──
  // Describes the transition that plays entering THIS clip FROM the previous
  // one — i.e. it lives on the "into" side of the cut, not the "out of" side.
  // The first clip on the timeline has no previous clip, so its transitionId
  // is simply ignored by the engine even if set. See
  // lib/domain/models/transition_presets.dart for the transitionId -> ffmpeg
  // `xfade` mapping used on export.

  /// Name of the applied transition preset (a key into
  /// [kTransitionPresets]/the Transitions panel catalogue), or null for a
  /// plain cut (the pre-feature default — export produces the exact same
  /// output as before this feature existed).
  String? transitionId;

  /// Length of the transition, in seconds. Only meaningful when
  /// [transitionId] is non-null. Defaults to 0.5s.
  double transitionDuration;

  // ── AI upscale ──
  // See lib/data/upscale/upscale_service.dart. When an AI upscale is applied,
  // [sourcePath]/[sourceDuration] are swapped to the upscaled file (with
  // [inPoint]/[outPoint] reset to cover it in full) and the clip's
  // pre-upscale source is recorded here so the user can revert. Null (the
  // default) means this clip has never been upscaled — every clip created
  // before this feature existed reproduces the exact same behaviour.

  /// The clip's source file before an AI upscale was applied, or null if it
  /// has never been upscaled. Only ever set once per upscale — a second
  /// upscale on top of an already-upscaled clip still records the *original*
  /// source, not the intermediate upscaled one, so "Revert to original"
  /// always goes all the way back.
  String? originalSourcePath;

  // ── media type ──

  /// What kind of source file [sourcePath] is. Video is the default (and the
  /// only value every clip created before this feature existed has) —
  /// [MediaType.image] marks a still image placed as a timed clip on the
  /// main track (see [kImageDefaultDuration]/[kImageSourceDurationCap] and
  /// `FfmpegEngine._buildFilterGraph`'s `-loop 1` input handling).
  /// [MediaType.audio] never appears here — imported audio becomes an
  /// `AudioClip` on the project's audio lane instead.
  final MediaType mediaType;

  bool get isImage => mediaType == MediaType.image;

  /// Length this clip contributes to the timeline, in seconds: the trimmed
  /// source region (clamped to source bounds) divided by [speed].
  double get duration =>
      (outPoint - inPoint).clamp(0, sourceDuration) / speed;

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  /// The static value of transform [property] (one of the `kKeyframe*`
  /// constants) — what [valueAt] falls back to when the property has no
  /// keyframes, and what the inspector's diamond button records when a
  /// keyframe is added. Returns 0 for an unrecognized property.
  double staticValue(String property) => switch (property) {
        kKeyframeScale => scale,
        kKeyframePosX => posX,
        kKeyframePosY => posY,
        kKeyframeRotation => rotation,
        kKeyframeOpacity => opacity,
        _ => 0.0,
      };

  /// The effective value of transform [property] at clip-relative time
  /// [t] (seconds from the start of the trimmed region): interpolated
  /// between its keyframes if it has any, otherwise [staticValue].
  double valueAt(String property, double t) => keyframeValueAt(
        keyframes[property] ?? const [],
        t,
        fallback: staticValue(property),
      );

  Clip copyWith({
    String? sourcePath,
    double? sourceDuration,
    double? inPoint,
    double? outPoint,
    List<Caption>? captions,
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    double? opacity,
    bool? flipH,
    double? speed,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    double? brightness,
    double? contrast,
    double? saturation,
    String? filterId,
    bool clearFilterId = false,
    double? filterIntensity,
    String? effectId,
    bool clearEffectId = false,
    double? effectIntensity,
    String? transitionId,
    bool clearTransitionId = false,
    double? transitionDuration,
    String? originalSourcePath,
    bool clearOriginalSourcePath = false,
    MediaType? mediaType,
    Map<String, List<Keyframe>>? keyframes,
    String? animationIn,
    bool clearAnimationIn = false,
    double? animationInDuration,
    String? animationOut,
    bool clearAnimationOut = false,
    double? animationOutDuration,
  }) =>
      Clip(
        id: id,
        sourcePath: sourcePath ?? this.sourcePath,
        sourceDuration: sourceDuration ?? this.sourceDuration,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        captions: captions ?? this.captions,
        scale: scale ?? this.scale,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        flipH: flipH ?? this.flipH,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        filterId: clearFilterId ? null : (filterId ?? this.filterId),
        filterIntensity: filterIntensity ?? this.filterIntensity,
        effectId: clearEffectId ? null : (effectId ?? this.effectId),
        effectIntensity: effectIntensity ?? this.effectIntensity,
        transitionId: clearTransitionId
            ? null
            : (transitionId ?? this.transitionId),
        transitionDuration: transitionDuration ?? this.transitionDuration,
        originalSourcePath: clearOriginalSourcePath
            ? null
            : (originalSourcePath ?? this.originalSourcePath),
        mediaType: mediaType ?? this.mediaType,
        keyframes: keyframes ?? this.keyframes,
        animationIn:
            clearAnimationIn ? null : (animationIn ?? this.animationIn),
        animationInDuration: animationInDuration ?? this.animationInDuration,
        animationOut:
            clearAnimationOut ? null : (animationOut ?? this.animationOut),
        animationOutDuration:
            animationOutDuration ?? this.animationOutDuration,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'captions': captions.map((c) => c.toJson()).toList(),
        'scale': scale,
        'posX': posX,
        'posY': posY,
        'rotation': rotation,
        'opacity': opacity,
        'flipH': flipH,
        'speed': speed,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'effectId': effectId,
        'effectIntensity': effectIntensity,
        'transitionId': transitionId,
        'transitionDuration': transitionDuration,
        'originalSourcePath': originalSourcePath,
        'mediaType': mediaType.toJson(),
        // Only written when at least one property is actually animated, so
        // an unanimated clip's JSON is byte-for-byte what it was before this
        // feature existed.
        if (keyframes.isNotEmpty)
          'keyframes': keyframes.map(
            (property, kfs) =>
                MapEntry(property, kfs.map((k) => k.toJson()).toList()),
          ),
        // Same reasoning as keyframes above: only written when an animation
        // is actually applied, so a clip with neither matches pre-feature
        // JSON exactly.
        if (animationIn != null) 'animationIn': animationIn,
        if (animationIn != null) 'animationInDuration': animationInDuration,
        if (animationOut != null) 'animationOut': animationOut,
        if (animationOut != null) 'animationOutDuration': animationOutDuration,
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String?,
        sourcePath: json['sourcePath'] as String,
        sourceDuration: (json['sourceDuration'] as num).toDouble(),
        inPoint: (json['inPoint'] as num?)?.toDouble(),
        outPoint: (json['outPoint'] as num?)?.toDouble(),
        captions: (json['captions'] as List?)
            ?.map((e) => Caption.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Missing keys (projects saved before a feature existed) fall back to
        // identity defaults via the constructor.
        scale: (json['scale'] as num?)?.toDouble(),
        posX: (json['posX'] as num?)?.toDouble(),
        posY: (json['posY'] as num?)?.toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble(),
        opacity: (json['opacity'] as num?)?.toDouble(),
        flipH: json['flipH'] as bool?,
        speed: (json['speed'] as num?)?.toDouble(),
        volume: (json['volume'] as num?)?.toDouble(),
        fadeIn: (json['fadeIn'] as num?)?.toDouble(),
        fadeOut: (json['fadeOut'] as num?)?.toDouble(),
        brightness: (json['brightness'] as num?)?.toDouble(),
        contrast: (json['contrast'] as num?)?.toDouble(),
        saturation: (json['saturation'] as num?)?.toDouble(),
        filterId: json['filterId'] as String?,
        filterIntensity: (json['filterIntensity'] as num?)?.toDouble(),
        effectId: json['effectId'] as String?,
        effectIntensity: (json['effectIntensity'] as num?)?.toDouble(),
        transitionId: json['transitionId'] as String?,
        transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
        originalSourcePath: json['originalSourcePath'] as String?,
        mediaType: MediaType.fromJson(json['mediaType'] as String?),
        keyframes: (json['keyframes'] as Map?)?.map(
          (property, kfs) => MapEntry(
            property as String,
            (kfs as List)
                .map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
                .toList(),
          ),
        ),
        animationIn: json['animationIn'] as String?,
        animationInDuration: (json['animationInDuration'] as num?)?.toDouble(),
        animationOut: json['animationOut'] as String?,
        animationOutDuration:
            (json['animationOutDuration'] as num?)?.toDouble(),
      );
}
