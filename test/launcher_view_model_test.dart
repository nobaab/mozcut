import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/project.dart';
import 'package:mozcut/ui/features/launcher/view_models/launcher_view_model.dart';

/// Covers `App.setCanvas` — the Ratio control's write path. Pure view-model
/// logic: no engine or project-store calls are involved, so these set the
/// notifier's `state` directly rather than going through `newProject`.
void main() {
  late ProviderContainer container;
  late App app;

  setUp(() {
    container = ProviderContainer();
    app = container.read(appProvider.notifier);
    app.state = Project(
      folderPath: '/tmp/Ratio Test',
      name: 'Ratio Test',
      video: const VideoSettings(width: 1920, height: 1080, fps: 30),
      clips: [Clip(sourcePath: '/a.mp4', sourceDuration: 10)],
    );
  });
  tearDown(() => container.dispose());

  test('setCanvas updates width/height and keeps the existing fps', () {
    app.setCanvas(1080, 1920);
    final video = container.read(appProvider)!.video;
    expect(video.width, 1080);
    expect(video.height, 1920);
    expect(video.fps, 30);
  });

  test('setCanvas preserves the rest of the project', () {
    app.setCanvas(1080, 1080);
    final project = container.read(appProvider)!;
    expect(project.folderPath, '/tmp/Ratio Test');
    expect(project.name, 'Ratio Test');
    expect(project.clips.length, 1);
    expect(project.clips.first.sourcePath, '/a.mp4');
  });

  test('setCanvas notifies watchers of appProvider', () {
    var notifications = 0;
    final sub = container.listen(appProvider, (prev, next) => notifications++);
    addTearDown(sub.close);

    app.setCanvas(1080, 1920);

    expect(notifications, 1);
  });

  test('setCanvas is a no-op when there is no open project', () {
    final empty = ProviderContainer();
    addTearDown(empty.dispose);
    empty.read(appProvider.notifier).setCanvas(1080, 1920);
    expect(empty.read(appProvider), isNull);
  });
}
