import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Blend-mode ids a [VideoOverlay] can composite with — the standard,
/// decades-old set of image-compositing math modes (Porter-Duff / the modes
/// every photo editor's layers panel has had since the 90s), not derived
/// from any product's UI or source. Mapped by the engine to ffmpeg's
/// `blend=all_mode=<id>` filter, except `'normal'`, which the engine handles
/// specially via a plain `overlay` (straight alpha compositing, with real
/// positioning) rather than `blend` — see
/// `FfmpegEngine._buildFilterGraph`'s video-overlay stage for why.
const kBlendModes = <String>[
  'normal',
  'multiply',
  'screen',
  'overlay',
  'darken',
  'lighten',
  'difference',
  'addition',
];

/// Title-cases a [kBlendModes] id for display, e.g. `'difference'` ->
/// `'Difference'` — used by the inspector's blend-mode dropdown.
String blendModeLabel(String id) =>
    id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';

/// A secondary video (or still image, imported the same way a main-track
/// image clip is) composited on top of the main timeline — CapCut's
/// overlay/PiP track. Unlike a [Clip], an overlay doesn't occupy a slot on
/// the single main track: it floats at its own [startTime], the same way
/// [AudioClip] floats on the audio lane — see that class's doc comment for
/// why project-level overlays exist as their own lane instead of living on a
/// clip. [startTime] is therefore timed on the *final, concatenated
/// timeline*, in seconds, same meaning as [AudioClip.start].
///
/// [inPoint]/[outPoint] trim the source the same way a [Clip]'s do (seconds
/// into [sourcePath], not the timeline). [scale] is a fraction of the output
/// canvas's *width* (so the default, 0.5, renders at half the canvas width —
/// a sensible PiP size out of the box), resolution-independent the same way
/// [StickerOverlay.size] is (via ffmpeg's `scale2ref` at burn-in time, not a
/// literal pixel size computed here). [posX]/[posY] are fractions (0..1) of
/// the canvas giving the overlay's anchor *center*, same convention as
/// [StickerOverlay.x]/[y] and [TextOverlay.x]/[y]. [rotation] is in degrees,
/// clockwise, same as [StickerOverlay.rotation].
///
/// [opacity] (0..1) and [blendMode] (one of [kBlendModes]) control how the
/// overlay composites onto the frame beneath it — see
/// `FfmpegEngine._buildFilterGraph` for the exact ffmpeg mapping and the
/// constraint non-`'normal'` modes accept (full-canvas blending, since
/// ffmpeg's `blend` filter requires both inputs to share one size).
class VideoOverlay {
  VideoOverlay({
    String? id,
    required this.sourcePath,
    required this.sourceDuration,
    double? inPoint,
    double? outPoint,
    this.startTime = 0,
    this.scale = 0.5,
    this.posX = 0.5,
    this.posY = 0.5,
    this.rotation = 0,
    this.opacity = 1.0,
    this.blendMode = 'normal',
  })  : id = id ?? _uuid.v4(),
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration;

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

  /// Where this overlay starts on the final exported timeline, in seconds.
  double startTime;

  /// Fraction of the output canvas's width this overlay renders at. Defaults
  /// to 0.5 (half the canvas) — a sensible picture-in-picture size.
  double scale;

  /// Fraction (0..1) of the output canvas's width — the overlay's anchor x.
  double posX;

  /// Fraction (0..1) of the output canvas's height — the overlay's anchor y.
  double posY;

  /// Clockwise rotation, in degrees. Only applied in `'normal'` blend mode —
  /// see the class doc comment.
  double rotation;

  /// Opacity, 0 (invisible) .. 1 (fully opaque).
  double opacity;

  /// One of [kBlendModes]. Defaults to `'normal'` (plain alpha compositing).
  String blendMode;

  /// Length this overlay plays for, in seconds: the trimmed source region,
  /// clamped to source bounds.
  double get duration => (outPoint - inPoint).clamp(0, sourceDuration);

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  VideoOverlay copyWith({
    String? sourcePath,
    double? sourceDuration,
    double? inPoint,
    double? outPoint,
    double? startTime,
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    double? opacity,
    String? blendMode,
  }) =>
      VideoOverlay(
        id: id,
        sourcePath: sourcePath ?? this.sourcePath,
        sourceDuration: sourceDuration ?? this.sourceDuration,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        startTime: startTime ?? this.startTime,
        scale: scale ?? this.scale,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        blendMode: blendMode ?? this.blendMode,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'startTime': startTime,
        'scale': scale,
        'posX': posX,
        'posY': posY,
        'rotation': rotation,
        'opacity': opacity,
        'blendMode': blendMode,
      };

  factory VideoOverlay.fromJson(Map<String, dynamic> json) => VideoOverlay(
        id: json['id'] as String?,
        sourcePath: json['sourcePath'] as String,
        sourceDuration: (json['sourceDuration'] as num).toDouble(),
        inPoint: (json['inPoint'] as num?)?.toDouble(),
        outPoint: (json['outPoint'] as num?)?.toDouble(),
        startTime: (json['startTime'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 0.5,
        posX: (json['posX'] as num?)?.toDouble() ?? 0.5,
        posY: (json['posY'] as num?)?.toDouble() ?? 0.5,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        blendMode: json['blendMode'] as String? ?? 'normal',
      );

  @override
  String toString() =>
      'VideoOverlay($fileName @ $startTime..${startTime + duration})';

  @override
  bool operator ==(Object other) =>
      other is VideoOverlay &&
      other.id == id &&
      other.sourcePath == sourcePath &&
      other.sourceDuration == sourceDuration &&
      other.inPoint == inPoint &&
      other.outPoint == outPoint &&
      other.startTime == startTime &&
      other.scale == scale &&
      other.posX == posX &&
      other.posY == posY &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(id, sourcePath, sourceDuration, inPoint,
      outPoint, startTime, scale, posX, posY, rotation, opacity, blendMode);
}
