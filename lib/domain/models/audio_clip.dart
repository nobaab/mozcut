import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single audio file placed on the project's audio lane.
///
/// Mirrors [TextOverlay]/[StickerOverlay] in living at the **project level**
/// (see `Project.audioClips`), not on a [Clip] — an audio track is a separate
/// lane that plays alongside the main video track and should survive clips
/// underneath it being trimmed, reordered or split.
///
/// [start] is where this clip begins on the *final, concatenated timeline*,
/// in seconds — the same seconds `Clip.duration` sums to and the player's
/// total duration uses. [inPoint]/[outPoint] are the trimmed region (in
/// seconds) of [sourcePath] actually used, same meaning as on [Clip].
class AudioClip {
  AudioClip({
    String? id,
    required this.sourcePath,
    required this.sourceDuration,
    double? start,
    double? inPoint,
    double? outPoint,
    double? volume,
    double? fadeIn,
    double? fadeOut,
  })  : id = id ?? _uuid.v4(),
        start = start ?? 0,
        inPoint = inPoint ?? 0,
        outPoint = outPoint ?? sourceDuration,
        volume = volume ?? 1.0,
        fadeIn = fadeIn ?? 0.0,
        fadeOut = fadeOut ?? 0.0;

  final String id;
  final String sourcePath;

  /// Full length of the source file, in seconds.
  final double sourceDuration;

  /// Where this clip starts on the final exported timeline, in seconds.
  double start;

  /// Start of the used region, in seconds from the source start.
  double inPoint;

  /// End of the used region, in seconds from the source start.
  double outPoint;

  /// Audio gain. 1.0 = 100% (unchanged), 2.0 = doubled, 0 = muted.
  double volume;

  /// Fade-in length from the in-point, in seconds (0 = none).
  double fadeIn;

  /// Fade-out length ending at the out-point, in seconds (0 = none).
  double fadeOut;

  /// Length this clip contributes to the timeline, in seconds: the trimmed
  /// source region, clamped to source bounds.
  double get duration => (outPoint - inPoint).clamp(0, sourceDuration);

  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  AudioClip copyWith({
    String? sourcePath,
    double? sourceDuration,
    double? start,
    double? inPoint,
    double? outPoint,
    double? volume,
    double? fadeIn,
    double? fadeOut,
  }) =>
      AudioClip(
        id: id,
        sourcePath: sourcePath ?? this.sourcePath,
        sourceDuration: sourceDuration ?? this.sourceDuration,
        start: start ?? this.start,
        inPoint: inPoint ?? this.inPoint,
        outPoint: outPoint ?? this.outPoint,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDuration': sourceDuration,
        'start': start,
        'inPoint': inPoint,
        'outPoint': outPoint,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
      };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        id: json['id'] as String?,
        sourcePath: json['sourcePath'] as String,
        sourceDuration: (json['sourceDuration'] as num).toDouble(),
        start: (json['start'] as num?)?.toDouble(),
        inPoint: (json['inPoint'] as num?)?.toDouble(),
        outPoint: (json['outPoint'] as num?)?.toDouble(),
        volume: (json['volume'] as num?)?.toDouble(),
        fadeIn: (json['fadeIn'] as num?)?.toDouble(),
        fadeOut: (json['fadeOut'] as num?)?.toDouble(),
      );

  @override
  String toString() => 'AudioClip($fileName @ $start..${start + duration})';
}
