import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/domain/models/clip.dart';
import 'package:vidkaat/domain/models/project.dart';

void main() {
  test('project survives a manifest round-trip', () {
    final project = Project(
      folderPath: '/tmp/My Project',
      name: 'My Project',
      video: const VideoSettings(width: 1080, height: 1920, fps: 30),
      clips: [
        Clip(sourcePath: '/v/a.mp4', sourceDuration: 20, inPoint: 2, outPoint: 9),
      ],
    );

    final restored =
        Project.fromManifest(project.folderPath, project.toManifest());

    expect(restored.name, 'My Project');
    expect(restored.video.width, 1080);
    expect(restored.video.height, 1920);
    expect(restored.video.fps, 30);
    expect(restored.clips.length, 1);
    expect(restored.clips.first.duration, 7);
    expect(restored.clips.first.sourcePath, '/v/a.mp4');
  });

  test('VideoSettings label formats whole and fractional fps', () {
    expect(const VideoSettings(width: 1920, height: 1080, fps: 30).label,
        '1920 × 1080 · 30 fps');
    expect(const VideoSettings(width: 1920, height: 1080, fps: 29.97).label,
        '1920 × 1080 · 29.97 fps');
  });

  test('RecentProject "when" is relative', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = RecentProject(
      path: '/p',
      name: 'P',
      video: const VideoSettings(),
      openedAt: now,
    );
    expect(r.when, 'just now');
  });
}
