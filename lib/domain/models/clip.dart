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
  })  : id = id ?? _uuid.v4(),
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        captions = captions ?? const [];

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

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
    List<Caption>? captions,
  }) =>
      Clip(
        id: id,
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        captions: captions ?? this.captions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'captions': captions.map((c) => c.toJson()).toList(),
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
      );
}
