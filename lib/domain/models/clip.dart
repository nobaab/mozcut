import 'package:uuid/uuid.dart';

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
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    bool? flipH,
  })  : id = id ?? _uuid.v4(),
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        scale = scale ?? 1.0,
        posX = posX ?? 0.0,
        posY = posY ?? 0.0,
        rotation = rotation ?? 0.0,
        flipH = flipH ?? false;

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

  // ── Transform ──
  //
  // The clip is first fit ("contain") into the project's output canvas
  // preserving its own aspect ratio, then these are applied on top of that
  // fitted frame. Identity values reproduce the untransformed clip.

  /// Uniform scale factor applied on top of the "fit to canvas" size.
  /// 1.0 = 100% (no extra scaling).
  double scale;

  /// Horizontal offset of the clip's center from the canvas center, as a
  /// fraction of half the canvas width. 0 = centered, -1 = flush with the
  /// left edge, 1 = flush with the right edge. (Values outside -1..1 push
  /// the clip partially or fully off-screen, which is allowed.)
  double posX;

  /// Vertical offset of the clip's center from the canvas center, as a
  /// fraction of half the canvas height. 0 = centered, -1 = top edge,
  /// 1 = bottom edge. Same convention as [posX].
  double posY;

  /// Rotation in degrees, clockwise. 0 = unrotated.
  double rotation;

  /// Mirrors the clip horizontally when true.
  bool flipH;

  /// Length this clip contributes to the timeline, in seconds.
  double get duration => (outPoint - inPoint).clamp(0, sourceDuration);

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  Clip copyWith({
    double? inPoint,
    double? outPoint,
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    bool? flipH,
  }) =>
      Clip(
        id: id,
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        scale: scale ?? this.scale,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
        rotation: rotation ?? this.rotation,
        flipH: flipH ?? this.flipH,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'scale': scale,
        'posX': posX,
        'posY': posY,
        'rotation': rotation,
        'flipH': flipH,
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String?,
        sourcePath: json['sourcePath'] as String,
        sourceDuration: (json['sourceDuration'] as num).toDouble(),
        inPoint: (json['inPoint'] as num?)?.toDouble(),
        outPoint: (json['outPoint'] as num?)?.toDouble(),
        // Missing keys (projects saved before transform support) fall back
        // to the identity transform via the constructor's defaults.
        scale: (json['scale'] as num?)?.toDouble(),
        posX: (json['posX'] as num?)?.toDouble(),
        posY: (json['posY'] as num?)?.toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble(),
        flipH: json['flipH'] as bool?,
      );
}
