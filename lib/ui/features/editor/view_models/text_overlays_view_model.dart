import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../domain/models/text_overlay.dart';

part 'text_overlays_view_model.g.dart';

/// The project's text/title overlays.
///
/// Overlays are project-scoped (see [TextOverlay]), not tied to any one clip,
/// so — like [Project.clips] vs. `Editor` — they get their own notifier
/// rather than living inside the per-clip editor state. `App` (the launcher
/// view model) loads this from the manifest on open and copies it back on
/// save, the same pattern it already uses for clips.
@Riverpod(keepAlive: true)
class TextOverlays extends _$TextOverlays {
  @override
  List<TextOverlay> build() => const [];

  /// Replaces the whole list (used when opening a project).
  void load(List<TextOverlay> overlays) => state = List.of(overlays);

  /// Adds a new overlay with sensible defaults and returns it.
  TextOverlay add() {
    final overlay = TextOverlay(text: 'Sample text', start: 0, end: 5);
    state = [...state, overlay];
    return overlay;
  }

  /// Replaces the overlay at [index] (e.g. after editing its text).
  void update(int index, TextOverlay overlay) {
    if (index < 0 || index >= state.length) return;
    final list = [...state];
    list[index] = overlay;
    state = list;
  }

  /// Removes the overlay at [index].
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
  }
}
