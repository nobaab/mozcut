import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/project.dart';
import '../core/project/project_store.dart';
import 'editor_state.dart';

/// The project store, built on the app's single engine.
final projectStoreProvider =
    Provider<ProjectStore>((ref) => ProjectStore(ref.read(engineProvider)));

/// The machine's recent projects, newest first. Invalidate to refresh.
final recentsProvider = FutureProvider<List<RecentProject>>(
    (ref) => ref.read(projectStoreProvider).recents());

/// Orchestrates the app's two screens. `state` is the open project, or null
/// for the start screen. Create / open / close all live here because each
/// touches the store, the editor's clips and the recents list together.
class AppController extends Notifier<Project?> {
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

  /// Saves the current edit back to its manifest, then returns to the start
  /// screen and refreshes the recents grid.
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
    await _store.save(project);
  }

  Future<void> forget(String path) async {
    await _store.forget(path);
    ref.invalidate(recentsProvider);
  }

  void _enter(Project project) {
    // Load the project's clips into the editor, then show the editor.
    ref.read(editorProvider.notifier).loadClips(project.clips);
    state = project;
  }
}

final appProvider = NotifierProvider<AppController, Project?>(AppController.new);
