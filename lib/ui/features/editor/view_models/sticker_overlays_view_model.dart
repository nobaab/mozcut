import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../domain/models/sticker_overlay.dart';

part 'sticker_overlays_view_model.g.dart';

/// The project's emoji sticker overlays.
///
/// Mirrors [TextOverlays] exactly — stickers are project-scoped (see
/// [StickerOverlay]), not tied to any one clip, so they get their own
/// notifier rather than living inside the per-clip editor state. `App` (the
/// launcher view model) loads this from the manifest on open and copies it
/// back on save, the same pattern it already uses for text overlays.
@Riverpod(keepAlive: true)
class StickerOverlays extends _$StickerOverlays {
  @override
  List<StickerOverlay> build() => const [];

  /// Replaces the whole list (used when opening a project).
  void load(List<StickerOverlay> overlays) => state = List.of(overlays);

  /// Adds a new emoji sticker with sensible defaults and returns it.
  StickerOverlay add(String emoji) {
    final overlay = StickerOverlay(emoji: emoji, start: 0, end: 3);
    state = [...state, overlay];
    return overlay;
  }

  /// Adds a new image sticker (a user-imported file or a generated shape) at
  /// [start]..[end] (defaulting to a 3-second window, same as [add]),
  /// centered by default, and returns it.
  StickerOverlay addImage(
    String imagePath, {
    double start = 0,
    double end = 3,
    double size = 0.3,
    double x = 0.5,
    double y = 0.5,
  }) {
    final overlay = StickerOverlay(
      imagePath: imagePath,
      start: start,
      end: end,
      size: size,
      x: x,
      y: y,
    );
    state = [...state, overlay];
    return overlay;
  }

  /// Replaces the sticker at [index] (e.g. after editing its position/time).
  void update(int index, StickerOverlay overlay) {
    if (index < 0 || index >= state.length) return;
    final list = [...state];
    list[index] = overlay;
    state = list;
  }

  /// Removes the sticker at [index].
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
  }
}
