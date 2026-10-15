import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/project.dart';
import '../engine/engine.dart';
import '../engine/ffmpeg_engine.dart';

part 'project_store.g.dart';

@Riverpod(keepAlive: true)
ProjectStore projectStore(Ref ref) => ProjectStore(ref.read(engineProvider));

/// The machine's recent projects, newest first. Invalidate to refresh.
@riverpod
Future<List<RecentProject>> recents(Ref ref) =>
    ref.read(projectStoreProvider).recents();

/// Reads and writes projects on disk, and the machine's recents list.
///
/// A project is a folder with a `vidkaat.json` manifest. The recents list lives
/// in the app's support directory — it is this machine's history and never
/// travels inside a project folder (same rule as Concat).
class ProjectStore {
  ProjectStore(this._engine);

  final Engine _engine;

  static const _recentsFile = 'recents.json';
  static const _maxRecents = 12;
  static const _posterFile = 'poster.jpg';

  // ── projects ────────────────────────────────────────────────────────────

  /// Creates the project folder and writes its manifest. Refuses to touch a
  /// folder that already holds a project — reusing a name must not clobber an
  /// existing edit.
  Future<Project> create({
    required String location,
    required String name,
    required VideoSettings video,
  }) async {
    final folder = Directory('$location/${_folderName(name)}');
    final manifest = File('${folder.path}/${Project.manifestName}');
    if (manifest.existsSync()) {
      throw const ProjectException('A project with that name already exists here.');
    }
    await folder.create(recursive: true);
    final project = Project(folderPath: folder.path, name: name, video: video);
    await save(project);
    return project;
  }

  /// Opens an existing project folder by reading its manifest.
  Future<Project> open(String folderPath) async {
    final manifest = File('$folderPath/${Project.manifestName}');
    if (!manifest.existsSync()) {
      throw ProjectException('No $folderPath/${Project.manifestName} found.');
    }
    final json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final project = Project.fromManifest(folderPath, json);
    await _touchRecent(project);
    return project;
  }

  /// Writes the manifest, regenerates the poster, and updates the recents list.
  Future<void> save(Project project) async {
    project.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    final manifest = File('${project.folderPath}/${Project.manifestName}');
    await manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert(project.toManifest()));

    // Best-effort poster from the first clip.
    String? posterPath;
    if (project.clips.isNotEmpty) {
      posterPath = '${project.folderPath}/$_posterFile';
      try {
        await _engine.savePoster(clip: project.clips.first, outputPath: posterPath);
      } catch (_) {
        posterPath = File(posterPath).existsSync() ? posterPath : null;
      }
    }
    await _touchRecent(project, posterPath: posterPath);
  }

  // ── recents ─────────────────────────────────────────────────────────────

  Future<List<RecentProject>> recents() async {
    final file = await _recentsPath();
    if (!file.existsSync()) return [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      final recents = list
          .map((e) => RecentProject.fromJson(e as Map<String, dynamic>))
          .where((r) => Directory(r.path).existsSync()) // drop deleted folders
          .toList();
      recents.sort((a, b) => b.openedAt.compareTo(a.openedAt));
      return recents;
    } catch (_) {
      return [];
    }
  }

  Future<void> forget(String path) async {
    final list = await recents();
    list.removeWhere((r) => r.path == path);
    await _writeRecents(list);
  }

  Future<void> _touchRecent(Project project, {String? posterPath}) async {
    final list = await recents();
    final existing = list.where((r) => r.path == project.folderPath).firstOrNull;
    list.removeWhere((r) => r.path == project.folderPath);
    list.insert(
      0,
      RecentProject(
        path: project.folderPath,
        name: project.name,
        video: project.video,
        openedAt: DateTime.now().millisecondsSinceEpoch,
        posterPath: posterPath ?? existing?.posterPath,
      ),
    );
    await _writeRecents(list.take(_maxRecents).toList());
  }

  Future<void> _writeRecents(List<RecentProject> list) async {
    final file = await _recentsPath();
    await file.writeAsString(
        jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  Future<File> _recentsPath() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_recentsFile');
  }

  /// A filesystem-safe folder name from a project name.
  static String _folderName(String name) {
    final clean = name.trim().replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    return clean.isEmpty ? 'Untitled Project' : clean;
  }
}

class ProjectException implements Exception {
  const ProjectException(this.message);
  final String message;
  @override
  String toString() => message;
}
