import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Horizontal placement of a [TextOverlay]'s anchor point relative to its own
/// text box — mirrors CapCut's text-alignment control (left/center/right).
enum TextOverlayAlignment {
  left,
  center,
  right;

  String toJson() => name;

  static TextOverlayAlignment fromJson(String? value) =>
      TextOverlayAlignment.values.firstWhere((a) => a.name == value,
          orElse: () => TextOverlayAlignment.center);
}

/// A single text/title overlay burned into the final export.
///
/// Overlays live at the **project level** (see [Project.textOverlays]), not
/// on a clip — a title card is a thing you place on the finished video, and
/// it should survive clips being trimmed, reordered or split underneath it.
/// [start] / [end] are therefore timed on the *final, concatenated timeline*
/// (the same seconds the export's progress and the player's total duration
/// use), in seconds.
///
/// [x] / [y] are fractions (0..1) of the output frame's width/height giving
/// the overlay's anchor point, and [fontSize] is a fraction of the frame
/// height — both normalized so a title keeps its relative size and position
/// regardless of the project's export resolution.
class TextOverlay {
  TextOverlay({
    String? id,
    required this.text,
    required this.start,
    required this.end,
    this.fontSize = 0.08,
    this.color = '#FFFFFF',
    this.alignment = TextOverlayAlignment.center,
    this.x = 0.5,
    this.y = 0.85,
  }) : id = id ?? _uuid.v4();

  final String id;

  String text;

  /// Start of this overlay, in seconds on the final exported timeline.
  double start;

  /// End of this overlay, in seconds on the final exported timeline.
  double end;

  /// Fraction (0..1) of the output frame height.
  double fontSize;

  /// Hex colour, e.g. `#FFFFFF`.
  String color;

  TextOverlayAlignment alignment;

  /// Fraction (0..1) of the output frame width — the overlay's anchor x.
  double x;

  /// Fraction (0..1) of the output frame height — the overlay's anchor y.
  double y;

  double get duration => (end - start).clamp(0, double.infinity);

  TextOverlay copyWith({
    String? text,
    double? start,
    double? end,
    double? fontSize,
    String? color,
    TextOverlayAlignment? alignment,
    double? x,
    double? y,
  }) =>
      TextOverlay(
        id: id,
        text: text ?? this.text,
        start: start ?? this.start,
        end: end ?? this.end,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        alignment: alignment ?? this.alignment,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'start': start,
        'end': end,
        'fontSize': fontSize,
        'color': color,
        'alignment': alignment.toJson(),
        'x': x,
        'y': y,
      };

  factory TextOverlay.fromJson(Map<String, dynamic> json) => TextOverlay(
        id: json['id'] as String?,
        text: json['text'] as String? ?? '',
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.08,
        color: json['color'] as String? ?? '#FFFFFF',
        alignment: TextOverlayAlignment.fromJson(json['alignment'] as String?),
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.85,
      );

  @override
  String toString() => 'TextOverlay($start–$end: "$text")';

  @override
  bool operator ==(Object other) =>
      other is TextOverlay &&
      other.id == id &&
      other.text == text &&
      other.start == start &&
      other.end == end &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.alignment == alignment &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(
      id, text, start, end, fontSize, color, alignment, x, y);
}
