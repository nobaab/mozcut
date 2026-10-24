import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single sticker burned into the final export — either an emoji glyph
/// (rendered via `drawtext`, the original and still default kind) or a
/// user-imported/generated image (rendered via `overlay`, see
/// [FfmpegEngine._buildFilterGraph]). Which one a given overlay is depends
/// purely on [imagePath]: non-null means "this is an image sticker, ignore
/// [emoji]"; null means "this is an emoji sticker, same as before this field
/// existed".
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
/// position regardless of the project's export resolution. [rotation] is in
/// degrees, clockwise; it only affects image stickers today (`drawtext` has
/// no clean rotation story, so an emoji sticker's rotation is accepted/stored
/// but not yet burned in).
class StickerOverlay {
  StickerOverlay({
    String? id,
    this.emoji,
    this.imagePath,
    required this.start,
    required this.end,
    this.size = 0.12,
    this.x = 0.5,
    this.y = 0.5,
    this.rotation = 0,
  }) : id = id ?? _uuid.v4();

  final String id;

  /// The emoji glyph to render, e.g. "🔥". Only meaningful when [imagePath]
  /// is null.
  String? emoji;

  /// Path to a user-imported or generated (e.g. a built-in shape) image file.
  /// When non-null, this sticker is an *image* sticker instead of an emoji
  /// one — see the class doc comment.
  String? imagePath;

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

  /// Clockwise rotation, in degrees. Defaults to 0 (unrotated), which keeps
  /// every sticker saved before this field existed unchanged.
  double rotation;

  /// Whether this is an image sticker (as opposed to an emoji one).
  bool get isImage => imagePath != null;

  double get duration => (end - start).clamp(0, double.infinity);

  StickerOverlay copyWith({
    String? emoji,
    String? imagePath,
    double? start,
    double? end,
    double? size,
    double? x,
    double? y,
    double? rotation,
  }) =>
      StickerOverlay(
        id: id,
        emoji: emoji ?? this.emoji,
        imagePath: imagePath ?? this.imagePath,
        start: start ?? this.start,
        end: end ?? this.end,
        size: size ?? this.size,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'imagePath': imagePath,
        'start': start,
        'end': end,
        'size': size,
        'x': x,
        'y': y,
        'rotation': rotation,
      };

  factory StickerOverlay.fromJson(Map<String, dynamic> json) =>
      StickerOverlay(
        id: json['id'] as String?,
        emoji: json['emoji'] as String?,
        imagePath: json['imagePath'] as String?,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        size: (json['size'] as num?)?.toDouble() ?? 0.12,
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.5,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() => isImage
      ? 'StickerOverlay($start–$end: image "$imagePath")'
      : 'StickerOverlay($start–$end: "$emoji")';

  @override
  bool operator ==(Object other) =>
      other is StickerOverlay &&
      other.id == id &&
      other.emoji == emoji &&
      other.imagePath == imagePath &&
      other.start == start &&
      other.end == end &&
      other.size == size &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(
      id, emoji, imagePath, start, end, size, x, y, rotation);
}
