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
        fadeOut = fadeOut ?? 0.0;

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

  /// Length this clip contributes to the timeline, in seconds: the trimmed
  /// source region (clamped to source bounds) divided by [speed].
  double get duration =>
      (outPoint - inPoint).clamp(0, sourceDuration) / speed;

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  Clip copyWith({
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
  }) =>
      Clip(
        id: id,
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
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
      );
}
