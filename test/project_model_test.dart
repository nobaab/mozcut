import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/project.dart';
import 'package:mozcut/domain/models/sticker_overlay.dart';
import 'package:mozcut/domain/models/text_overlay.dart';

void main() {
  test('project survives a manifest round-trip', () {
    final project = Project(
      folderPath: '/tmp/My Project',
      name: 'My Project',
      video: const VideoSettings(width: 1080, height: 1920, fps: 30),
      clips: [
        Clip(sourcePath: '/v/a.mp4', sourceDuration: 20, inPoint: 2, outPoint: 9),
      ],
      textOverlays: [
        TextOverlay(text: 'Title card', start: 0, end: 3, color: '#FF0000'),
      ],
      stickerOverlays: [
        StickerOverlay(emoji: '🔥', start: 1, end: 4, size: 0.15),
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
    expect(restored.textOverlays.length, 1);
    expect(restored.textOverlays.first.text, 'Title card');
    expect(restored.textOverlays.first.color, '#FF0000');
    expect(restored.stickerOverlays.length, 1);
    expect(restored.stickerOverlays.first.emoji, '🔥');
    expect(restored.stickerOverlays.first.size, 0.15);
  });

  test('project defaults to no text/sticker overlays when the keys are '
      'absent (old manifests)', () {
    final project = Project(folderPath: '/tmp/Old Project', name: 'Old');
    final manifest = project.toManifest()
      ..remove('textOverlays')
      ..remove('stickerOverlays');

    final restored = Project.fromManifest(project.folderPath, manifest);

    expect(restored.textOverlays, isEmpty);
    expect(restored.stickerOverlays, isEmpty);
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
