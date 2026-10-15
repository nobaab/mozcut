/// One timed caption segment — a line of speech-to-text output, with the
/// window (in seconds, relative to the clip it was generated from) that it
/// covers.
class Caption {
  const Caption({required this.start, required this.end, required this.text});

  /// Start of this segment, in seconds from the start of the clip's trimmed
  /// region (i.e. 0 is the clip's in-point, not the source file's start).
  final double start;

  /// End of this segment, in the same clip-relative seconds.
  final double end;

  final String text;

  double get duration => (end - start).clamp(0, double.infinity);

  Caption copyWith({double? start, double? end, String? text}) => Caption(
        start: start ?? this.start,
        end: end ?? this.end,
        text: text ?? this.text,
      );

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'text': text,
      };

  factory Caption.fromJson(Map<String, dynamic> json) => Caption(
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        text: json['text'] as String,
      );

  @override
  String toString() => 'Caption($start–$end: "$text")';

  @override
  bool operator ==(Object other) =>
      other is Caption &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

/// Formats [seconds] as an SRT timestamp, e.g. `00:01:02,345`.
String formatSrtTimestamp(double seconds) {
  final totalMs = (seconds.clamp(0, double.infinity) * 1000).round();
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs % 3600000) ~/ 60000;
  final secs = (totalMs % 60000) ~/ 1000;
  final millis = totalMs % 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(hours)}:${two(minutes)}:${two(secs)},${three(millis)}';
}
