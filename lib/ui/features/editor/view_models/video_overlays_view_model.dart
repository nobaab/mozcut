import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/video_overlay.dart';

part 'video_overlays_view_model.g.dart';

/// The project's picture-in-picture lane.
///
/// Mirrors [AudioClips]/[StickerOverlays] — video overlays are project-scoped
/// (see [VideoOverlay]), not tied to any one clip on the main track, so they
/// get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for the
/// other overlays.
@Riverpod(keepAlive: true)
class VideoOverlays extends _$VideoOverlays {
  @override
  List<VideoOverlay> build() => const [];

  /// Replaces the whole list (used when opening a project).
  void load(List<VideoOverlay> overlays) => state = List.of(overlays);

  /// Probes [path]'s duration and appends a new [VideoOverlay] for it,
  /// starting at [startTime] on the timeline (defaults to the very start).
  /// Returns the added overlay.
  Future<VideoOverlay> addFromPath(String path, {double startTime = 0}) async {
    final duration = await ref.read(engineProvider).probeDuration(path);
    final overlay = VideoOverlay(
      sourcePath: path,
      sourceDuration: duration,
      startTime: startTime,
    );
    state = [...state, overlay];
    return overlay;
  }

  /// Replaces the overlay at [index] (e.g. after editing its scale/position/
  /// rotation/opacity/blend mode/timing).
  void update(int index, VideoOverlay overlay) {
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

/// The overlay lane's selected overlay id, or null for none. Separate from
/// the list state above, same treatment as [SelectedAudioClip].
@Riverpod(keepAlive: true)
class SelectedVideoOverlay extends _$SelectedVideoOverlay {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}
