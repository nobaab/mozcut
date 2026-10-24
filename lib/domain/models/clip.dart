import 'package:uuid/uuid.dart';

import 'caption.dart';

const _uuid = Uuid();

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
    bool? flipH,
    double? speed,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    double? brightness,
    double? contrast,
    double? saturation,
    this.filterId,
    this.effectId,
    this.transitionId,
    double? transitionDuration,
    this.originalSourcePath,
  })  : id = id ?? _uuid.v4(),
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        captions = captions ?? const [],
        scale = scale ?? 1.0,
        posX = posX ?? 0.0,
        posY = posY ?? 0.0,
        rotation = rotation ?? 0.0,
        flipH = flipH ?? false,
        speed = speed ?? 1.0,
        volume = volume ?? 1.0,
        fadeIn = fadeIn ?? 0.0,
        fadeOut = fadeOut ?? 0.0,
        brightness = brightness ?? 0.0,
        contrast = contrast ?? 1.0,
        saturation = saturation ?? 1.0,
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

  /// Mirrors the clip horizontally.
  bool flipH;

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

  /// Length this clip contributes to the timeline, in seconds: the trimmed
  /// source region (clamped to source bounds) divided by [speed].
  double get duration =>
      (outPoint - inPoint).clamp(0, sourceDuration) / speed;

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

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
    String? effectId,
    bool clearEffectId = false,
    String? transitionId,
    bool clearTransitionId = false,
    double? transitionDuration,
    String? originalSourcePath,
    bool clearOriginalSourcePath = false,
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
        flipH: flipH ?? this.flipH,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        filterId: clearFilterId ? null : (filterId ?? this.filterId),
        effectId: clearEffectId ? null : (effectId ?? this.effectId),
        transitionId: clearTransitionId
            ? null
            : (transitionId ?? this.transitionId),
        transitionDuration: transitionDuration ?? this.transitionDuration,
        originalSourcePath: clearOriginalSourcePath
            ? null
            : (originalSourcePath ?? this.originalSourcePath),
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
        'flipH': flipH,
        'speed': speed,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'filterId': filterId,
        'effectId': effectId,
        'transitionId': transitionId,
        'transitionDuration': transitionDuration,
        'originalSourcePath': originalSourcePath,
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
        flipH: json['flipH'] as bool?,
        speed: (json['speed'] as num?)?.toDouble(),
        volume: (json['volume'] as num?)?.toDouble(),
        fadeIn: (json['fadeIn'] as num?)?.toDouble(),
        fadeOut: (json['fadeOut'] as num?)?.toDouble(),
        brightness: (json['brightness'] as num?)?.toDouble(),
        contrast: (json['contrast'] as num?)?.toDouble(),
        saturation: (json['saturation'] as num?)?.toDouble(),
        filterId: json['filterId'] as String?,
        effectId: json['effectId'] as String?,
        transitionId: json['transitionId'] as String?,
        transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
        originalSourcePath: json['originalSourcePath'] as String?,
      );
}
