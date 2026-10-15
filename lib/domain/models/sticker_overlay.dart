import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single emoji sticker burned into the final export.
///
/// Mirrors [TextOverlay] in every respect that matters for timing/placement —
/// see its doc comment for the full rationale. Stickers live at the
/// **project level** (see [Project.stickerOverlays]), not on a clip, for the
/// same reason titles do: a sticker is placed on the finished video and
/// should survive clips underneath it being trimmed, reordered or split.
/// [start] / [end] are timed on the *final, concatenated timeline*, in
/// seconds.
///
/// [x] / [y] are fractions (0..1) of the output frame's width/height giving
/// the sticker's anchor point (its center), and [size] is a fraction of the
/// frame height — both normalized so a sticker keeps its relative size and
/// position regardless of the project's export resolution.
class StickerOverlay {
  StickerOverlay({
    String? id,
    required this.emoji,
    required this.start,
    required this.end,
    this.size = 0.12,
    this.x = 0.5,
    this.y = 0.5,
  }) : id = id ?? _uuid.v4();

  final String id;

  /// The emoji glyph to render, e.g. "🔥".
  String emoji;

  /// Start of this sticker, in seconds on the final exported timeline.
  double start;

  /// End of this sticker, in seconds on the final exported timeline.
  double end;

  /// Fraction (0..1) of the output frame height.
  double size;

  /// Fraction (0..1) of the output frame width — the sticker's anchor x.
  double x;

  /// Fraction (0..1) of the output frame height — the sticker's anchor y.
  double y;

  double get duration => (end - start).clamp(0, double.infinity);

  StickerOverlay copyWith({
    String? emoji,
    double? start,
    double? end,
    double? size,
    double? x,
    double? y,
  }) =>
      StickerOverlay(
        id: id,
        emoji: emoji ?? this.emoji,
        start: start ?? this.start,
        end: end ?? this.end,
        size: size ?? this.size,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'start': start,
        'end': end,
        'size': size,
        'x': x,
        'y': y,
      };

  factory StickerOverlay.fromJson(Map<String, dynamic> json) =>
      StickerOverlay(
        id: json['id'] as String?,
        emoji: json['emoji'] as String? ?? '',
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        size: (json['size'] as num?)?.toDouble() ?? 0.12,
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.5,
      );

  @override
  String toString() => 'StickerOverlay($start–$end: "$emoji")';

  @override
  bool operator ==(Object other) =>
      other is StickerOverlay &&
      other.id == id &&
      other.emoji == emoji &&
      other.start == start &&
      other.end == end &&
      other.size == size &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(id, emoji, start, end, size, x, y);
}
