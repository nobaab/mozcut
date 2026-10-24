import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/project/project_store.dart';
import '../../../../domain/models/project.dart';
import '../../editor/view_models/audio_clips_view_model.dart';
import '../../editor/view_models/editor_view_model.dart';
import '../../editor/view_models/sticker_overlays_view_model.dart';
import '../../editor/view_models/text_overlays_view_model.dart';

part 'launcher_view_model.g.dart';

/// Orchestrates the app's two screens. `state` is the open project, or null for
/// the launcher. Create / open / close all live here because each touches the
/// store, the editor's clips and the recents list together.
@Riverpod(keepAlive: true)
class App extends _$App {
  @override
  Project? build() => null;

  ProjectStore get _store => ref.read(projectStoreProvider);

  Future<void> newProject({
    required String location,
    required String name,
    required VideoSettings video,
  }) async {
    final project =
        await _store.create(location: location, name: name, video: video);
    _enter(project);
  }

  Future<void> openRecent(String path) async {
    final project = await _store.open(path);
    _enter(project);
  }

  /// Changes the project's canvas (the Ratio control in the player) to
  /// [width]x[height], keeping the current frame rate. Rebuilds a fresh
  /// [Project] rather than mutating [Project.video] in place — reassigning
  /// the very same instance to `state` wouldn't notify watchers, since
  /// Riverpod skips the update when the new state is identical to the old
  /// one. The new canvas is persisted the next time [saveCurrent] runs (e.g.
  /// on [closeToStart]), same as clips/overlays.
  void setCanvas(int width, int height) {
    final project = state;
    if (project == null) return;
    state = Project(
      folderPath: project.folderPath,
      name: project.name,
      video: VideoSettings(width: width, height: height, fps: project.video.fps),
      clips: project.clips,
      textOverlays: project.textOverlays,
      stickerOverlays: project.stickerOverlays,
      audioClips: project.audioClips,
      createdAt: project.createdAt,
      modifiedAt: project.modifiedAt,
    );
  }

  /// Saves the current edit back to its manifest, then returns to the launcher
  /// and refreshes the recents grid.
  Future<void> closeToStart() async {
    await saveCurrent();
    state = null;
    ref.invalidate(recentsProvider);
  }

  /// Writes the current clips + metadata to the project's manifest.
  Future<void> saveCurrent() async {
    final project = state;
    if (project == null) return;
    project.clips = ref.read(editorProvider).clips;
    project.textOverlays = ref.read(textOverlaysProvider);
    project.stickerOverlays = ref.read(stickerOverlaysProvider);
    project.audioClips = ref.read(audioClipsProvider);
    await _store.save(project);
  }

  Future<void> forget(String path) async {
    await _store.forget(path);
    ref.invalidate(recentsProvider);
  }

  void _enter(Project project) {
    ref.read(editorProvider.notifier).loadClips(project.clips);
    ref.read(textOverlaysProvider.notifier).load(project.textOverlays);
    ref.read(stickerOverlaysProvider.notifier).load(project.stickerOverlays);
    ref.read(audioClipsProvider.notifier).load(project.audioClips);
    state = project;
  }
}
