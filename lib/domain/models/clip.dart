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
    double? volume,
    double? fadeIn,
    double? fadeOut,
    List<Caption>? captions,
  })  : id = id ?? _uuid.v4(),
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        volume = volume ?? 1.0,
        fadeIn = fadeIn ?? 0,
        fadeOut = fadeOut ?? 0,
        captions = captions ?? const [];

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

  /// Audio gain multiplier applied on export. `1.0` is unchanged (the UI
  /// shows this as 100%), `2.0` is +100% gain (200%), `0.0` is muted. Kept as
  /// a plain multiplier (rather than dB) so it maps directly onto ffmpeg's
  /// `volume` filter and onto the 0–200% slider in the inspector.
  double volume;

  /// Audio fade-in length from the clip's in-point, in seconds. `0` means no
  /// fade.
  double fadeIn;

  /// Audio fade-out length ending at the clip's out-point, in seconds. `0`
  /// means no fade.
  double fadeOut;

  /// Auto-generated (or hand-edited) captions for this clip, timed relative
  /// to [inPoint] (i.e. a caption's own `start` of 0 means "right at the
  /// clip's in-point"). Re-trimming the clip after generating captions does
  /// not re-time them — regenerate if the trim changes materially.
  final List<Caption> captions;

  /// Length this clip contributes to the timeline, in seconds.
  double get duration => (outPoint - inPoint).clamp(0, sourceDuration);

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  Clip copyWith({
    double? inPoint,
    double? outPoint,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    List<Caption>? captions,
  }) =>
      Clip(
        id: id,
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        captions: captions ?? this.captions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'captions': captions.map((c) => c.toJson()).toList(),
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String?,
        sourcePath: json['sourcePath'] as String,
        sourceDuration: (json['sourceDuration'] as num).toDouble(),
        inPoint: (json['inPoint'] as num?)?.toDouble(),
        outPoint: (json['outPoint'] as num?)?.toDouble(),
        volume: (json['volume'] as num?)?.toDouble(),
        fadeIn: (json['fadeIn'] as num?)?.toDouble(),
        fadeOut: (json['fadeOut'] as num?)?.toDouble(),
        captions: (json['captions'] as List?)
            ?.map((e) => Caption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
