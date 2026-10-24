/// One keyframe on an animated [Clip] transform property (see
/// `Clip.keyframes`). [timeSec] is **clip-relative**: 0 is the start of the
/// clip's trimmed-in region, same timeline the playhead uses once you
/// subtract the clip's `inPoint` (see `Editor.addKeyframeAtPlayhead` /
/// `inspector_panel.dart`'s diamond buttons) — not an absolute project
/// timestamp, so a clip keeps its animation if it's moved earlier/later on
/// the timeline (CapCut anchors keyframes to absolute time instead; MozCut
/// deliberately diverges — see docs/CAPCUT-SPEC.md §2.6).
class Keyframe {
  const Keyframe({required this.timeSec, required this.value});

  /// Seconds from the start of the clip's trimmed region. Never negative in
  /// practice (callers clamp), but nothing here enforces that.
  final double timeSec;

  /// The property's value at [timeSec] (same units as the static field it
  /// animates — e.g. degrees for rotation, 0..1 for opacity).
  final double value;

  Keyframe copyWith({double? timeSec, double? value}) => Keyframe(
        timeSec: timeSec ?? this.timeSec,
        value: value ?? this.value,
      );

  Map<String, dynamic> toJson() => {'t': timeSec, 'v': value};

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
        timeSec: (json['t'] as num).toDouble(),
        value: (json['v'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is Keyframe && other.timeSec == timeSec && other.value == value;

  @override
  int get hashCode => Object.hash(timeSec, value);

  @override
  String toString() => 'Keyframe(t: $timeSec, v: $value)';
}

/// Linearly interpolates [keyframes] at clip-relative time [t], in seconds.
///
/// - No keyframes at all: returns [fallback] (the property's static value —
///   this is what makes an unanimated clip behave exactly as before this
///   feature existed).
/// - Before the first keyframe / after the last: clamps to that keyframe's
///   value (no extrapolation).
/// - Between two keyframes: straight linear interpolation.
///
/// [keyframes] need not be pre-sorted by [Keyframe.timeSec] — this sorts a
/// copy before interpolating.
double keyframeValueAt(
  List<Keyframe> keyframes,
  double t, {
  required double fallback,
}) {
  if (keyframes.isEmpty) return fallback;
  if (keyframes.length == 1) return keyframes.single.value;

  final sorted = List<Keyframe>.of(keyframes)
    ..sort((a, b) => a.timeSec.compareTo(b.timeSec));

  if (t <= sorted.first.timeSec) return sorted.first.value;
  if (t >= sorted.last.timeSec) return sorted.last.value;

  for (var i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (t >= a.timeSec && t <= b.timeSec) {
      final span = b.timeSec - a.timeSec;
      if (span.abs() < 1e-9) return b.value;
      final frac = (t - a.timeSec) / span;
      return a.value + (b.value - a.value) * frac;
    }
  }
  return sorted.last.value; // unreachable given the bounds checks above
}
