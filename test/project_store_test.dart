import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mozcut/data/engine/engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/export_settings.dart';
import 'package:mozcut/domain/models/project.dart';
import 'package:mozcut/domain/models/text_overlay.dart';
import 'package:mozcut/data/project/project_store.dart';

/// Points path_provider at a temp dir so the recents file lands somewhere real.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.support);
  final String support;
  @override
  Future<String?> getApplicationSupportPath() async => support;
}

/// No-op engine: the store's poster step must not need a real video here.
class _NoEngine implements Engine {
  @override
  Future<double> probeDuration(String path) async => 10;
  @override
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    void Function(double)? onProgress,
  }) async {}
  @override
  Future<void> savePoster({
    required Clip clip,
    required String outputPath,
    int width = 480,
  }) async {}
  @override
  Future<void> extractAudio({
    required Clip clip,
    required String outputPath,
  }) async {}
}

void main() {
  late Directory tmp;
  late ProjectStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_store_');
    PathProviderPlatform.instance = _FakePathProvider('${tmp.path}/support');
    Directory('${tmp.path}/support').createSync(recursive: true);
    store = ProjectStore(_NoEngine());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('create → recents → open → forget full cycle', () async {
    final location = '${tmp.path}/Projects';

    // CREATE
    final project = await store.create(
      location: location,
      name: 'My First Edit',
      video: const VideoSettings(width: 1080, height: 1920, fps: 30),
    );
    expect(Directory(project.folderPath).existsSync(), isTrue);
    expect(File('${project.folderPath}/${Project.manifestName}').existsSync(),
        isTrue);

    // RECENTS lists it
    var recents = await store.recents();
    expect(recents.length, 1);
    expect(recents.first.name, 'My First Edit');
    expect(recents.first.video.height, 1920);

    // SAVE some clips
    project.clips = [
      Clip(sourcePath: '/v/a.mp4', sourceDuration: 20, inPoint: 1, outPoint: 6),
    ];
    await store.save(project);

    // OPEN reads them back
    final reopened = await store.open(project.folderPath);
    expect(reopened.clips.length, 1);
    expect(reopened.clips.first.duration, 5);
    expect(reopened.name, 'My First Edit');

    // Creating the same name again must refuse (no clobber)
    expect(
      () => store.create(
          location: location,
          name: 'My First Edit',
          video: const VideoSettings()),
      throwsA(isA<ProjectException>()),
    );

    // FORGET removes it from recents (folder stays on disk)
    await store.forget(project.folderPath);
    recents = await store.recents();
    expect(recents, isEmpty);
    expect(Directory(project.folderPath).existsSync(), isTrue);
  });

  test('recents prunes folders that no longer exist', () async {
    final project = await store.create(
      location: '${tmp.path}/Projects',
      name: 'Doomed',
      video: const VideoSettings(),
    );
    expect((await store.recents()).length, 1);

    Directory(project.folderPath).deleteSync(recursive: true);
    expect((await store.recents()), isEmpty); // pruned on read
  });
}
