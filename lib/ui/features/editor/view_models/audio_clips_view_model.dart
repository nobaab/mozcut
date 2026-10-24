import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/audio_clip.dart';

part 'audio_clips_view_model.g.dart';

/// The project's audio lane.
///
/// Audio clips are project-scoped (see [AudioClip]), not tied to any one
/// clip on the main track — like [Project.textOverlays]/[stickerOverlays],
/// they get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for
/// overlays.
@Riverpod(keepAlive: true)
class AudioClips extends _$AudioClips {
  @override
  List<AudioClip> build() => const [];

  /// Replaces the whole list (used when opening a project).
  void load(List<AudioClip> clips) => state = List.of(clips);

  /// Probes [path]'s duration and appends a new [AudioClip] for it, starting
  /// at [start] on the timeline (defaults to the very start). Returns the
  /// added clip.
  Future<AudioClip> addFromPath(String path, {double start = 0}) async {
    final duration = await ref.read(engineProvider).probeDuration(path);
    final clip = AudioClip(
      sourcePath: path,
      sourceDuration: duration,
      start: start,
    );
    state = [...state, clip];
    return clip;
  }

  /// Replaces the clip at [index] (e.g. after dragging/trimming it).
  void update(int index, AudioClip clip) {
    if (index < 0 || index >= state.length) return;
    final list = [...state];
    list[index] = clip;
    state = list;
  }

  /// Removes the clip at [index].
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
  }
}

/// The audio lane's selected clip id, or null for none. Separate from the
/// list state above so selecting a clip doesn't itself count as an edit to
/// save/undo — same treatment as `Editor`'s own `selectedId`/`Playhead`.
@Riverpod(keepAlive: true)
class SelectedAudioClip extends _$SelectedAudioClip {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}
