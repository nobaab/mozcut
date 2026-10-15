import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/domain/models/clip.dart';
import 'package:vidkaat/ui/features/editor/view_models/editor_view_model.dart';

/// Covers the timeline-interaction additions to the [Editor] notifier:
/// drag-to-reorder and the per-clip trim handles. Pure view-model logic, no
/// widgets or engine involved.
void main() {
  late ProviderContainer container;
  late Editor editor;

  Clip clipAt(int i) => container.read(editorProvider).clips[i];

  setUp(() {
    container = ProviderContainer();
    editor = container.read(editorProvider.notifier);
    editor.loadClips([
      Clip(sourcePath: '/a.mp4', sourceDuration: 10),
      Clip(sourcePath: '/b.mp4', sourceDuration: 10),
      Clip(sourcePath: '/c.mp4', sourceDuration: 10),
    ]);
  });
  tearDown(() => container.dispose());

  group('reorder', () {
    test('moves a clip from the front to the back', () {
      editor.reorder(0, 2);
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['b.mp4', 'c.mp4', 'a.mp4']);
    });

    test('moves a clip from the back to the front', () {
      editor.reorder(2, 0);
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['c.mp4', 'a.mp4', 'b.mp4']);
    });

    test('moving a clip to the middle reorders the others around it', () {
      editor.reorder(0, 1);
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['b.mp4', 'a.mp4', 'c.mp4']);
    });

    test('ignores an out-of-range oldIndex', () {
      editor.reorder(99, 0);
      expect(container.read(editorProvider).clips.length, 3);
      expect(clipAt(0).fileName, 'a.mp4');
    });

    test('clamps an out-of-range newIndex to the end of the list', () {
      editor.reorder(0, 99);
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['b.mp4', 'c.mp4', 'a.mp4']);
    });
  });

  group('setTrim', () {
    test('adjusts inPoint and recomputes duration', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 3);
      expect(clipAt(0).inPoint, 3);
      expect(clipAt(0).duration, closeTo(7, 0.001));
    });

    test('adjusts outPoint and recomputes duration', () {
      final id = clipAt(0).id;
      editor.setTrim(id, outPoint: 4);
      expect(clipAt(0).outPoint, 4);
      expect(clipAt(0).duration, closeTo(4, 0.001));
    });

    test('clamps inPoint/outPoint to the source bounds', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: -5);
      expect(clipAt(0).inPoint, 0);

      editor.setTrim(id, outPoint: 999);
      expect(clipAt(0).outPoint, 10);
    });

    test('keeps at least a 0.1s clip when the left handle overshoots', () {
      final id = clipAt(0).id;
      editor.setTrim(id, outPoint: 2);
      editor.setTrim(id, inPoint: 9); // would cross outPoint (2)
      expect(clipAt(0).duration, closeTo(0.1, 0.001));
      expect(clipAt(0).outPoint - clipAt(0).inPoint, closeTo(0.1, 0.001));
    });

    test('keeps at least a 0.1s clip when the right handle overshoots', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 8);
      editor.setTrim(id, outPoint: 1); // would cross inPoint (8)
      expect(clipAt(0).duration, closeTo(0.1, 0.001));
      expect(clipAt(0).outPoint - clipAt(0).inPoint, closeTo(0.1, 0.001));
    });

    test('does not affect other clips', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 5);
      expect(clipAt(1).duration, 10);
      expect(clipAt(2).duration, 10);
    });

    test('ignores an unknown clip id', () {
      editor.setTrim('does-not-exist', inPoint: 5);
      expect(clipAt(0).inPoint, 0);
      expect(clipAt(0).duration, 10);
    });
  });
}
