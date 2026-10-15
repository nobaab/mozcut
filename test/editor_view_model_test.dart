import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_view_model.dart';

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

  group('setSelectedSpeed', () {
    test('sets the speed of the selected clip and recomputes duration', () {
      editor.select(clipAt(0).id);
      editor.setSelectedSpeed(2.0);
      expect(clipAt(0).speed, 2.0);
      expect(clipAt(0).duration, closeTo(5, 0.001));
    });

    test('clamps below the minimum to 0.1', () {
      editor.select(clipAt(0).id);
      editor.setSelectedSpeed(0.0001);
      expect(clipAt(0).speed, 0.1);
    });

    test('clamps above the maximum to 100', () {
      editor.select(clipAt(0).id);
      editor.setSelectedSpeed(1000);
      expect(clipAt(0).speed, 100.0);
    });

    test('does not affect other clips', () {
      editor.select(clipAt(0).id);
      editor.setSelectedSpeed(2.0);
      expect(clipAt(1).speed, 1.0);
      expect(clipAt(2).speed, 1.0);
    });

    test('does nothing when there is no selection', () {
      editor.select('does-not-exist');
      editor.setSelectedSpeed(2.0);
      expect(clipAt(0).speed, 1.0);
    });
  });

  group('updateSelectedAudio', () {
    test('sets volume on the selected clip', () {
      editor.updateSelectedAudio(volume: 1.5);
      expect(clipAt(0).volume, 1.5);
    });

    test('sets fadeIn and fadeOut independently', () {
      editor.updateSelectedAudio(fadeIn: 0.5);
      editor.updateSelectedAudio(fadeOut: 2);
      expect(clipAt(0).fadeIn, 0.5);
      expect(clipAt(0).fadeOut, 2);
    });

    test('omitted parameters are left unchanged', () {
      editor.updateSelectedAudio(volume: 1.2, fadeIn: 1, fadeOut: 1);
      editor.updateSelectedAudio(volume: 0.8);
      expect(clipAt(0).volume, 0.8);
      expect(clipAt(0).fadeIn, 1);
      expect(clipAt(0).fadeOut, 1);
    });

    test('clamps volume to 0..2', () {
      editor.updateSelectedAudio(volume: 5);
      expect(clipAt(0).volume, 2);
      editor.updateSelectedAudio(volume: -1);
      expect(clipAt(0).volume, 0);
    });

    test('clamps fades to non-negative', () {
      editor.updateSelectedAudio(fadeIn: -3, fadeOut: -3);
      expect(clipAt(0).fadeIn, 0);
      expect(clipAt(0).fadeOut, 0);
    });

    test('does not affect other clips', () {
      editor.updateSelectedAudio(volume: 1.8);
      expect(clipAt(1).volume, 1.0);
      expect(clipAt(2).volume, 1.0);
    });

    test('does nothing when no clip is selected', () {
      editor.removeSelected();
      editor.removeSelected();
      editor.removeSelected();
      expect(() => editor.updateSelectedAudio(volume: 1.5), returnsNormally);
    });
  });

  group('updateSelectedColor', () {
    test('sets brightness/contrast/saturation on the selected clip', () {
      editor.updateSelectedColor(brightness: 0.3, contrast: 1.4, saturation: 0.6);
      expect(clipAt(0).brightness, 0.3);
      expect(clipAt(0).contrast, 1.4);
      expect(clipAt(0).saturation, 0.6);
    });

    test('omitted parameters are left unchanged', () {
      editor.updateSelectedColor(brightness: 0.2, contrast: 1.2, saturation: 1.2);
      editor.updateSelectedColor(brightness: 0.5);
      expect(clipAt(0).brightness, 0.5);
      expect(clipAt(0).contrast, 1.2);
      expect(clipAt(0).saturation, 1.2);
    });

    test('clamps brightness to -1..1', () {
      editor.updateSelectedColor(brightness: 5);
      expect(clipAt(0).brightness, 1.0);
      editor.updateSelectedColor(brightness: -5);
      expect(clipAt(0).brightness, -1.0);
    });

    test('clamps contrast and saturation to 0..3', () {
      editor.updateSelectedColor(contrast: 10, saturation: 10);
      expect(clipAt(0).contrast, 3.0);
      expect(clipAt(0).saturation, 3.0);
      editor.updateSelectedColor(contrast: -10, saturation: -10);
      expect(clipAt(0).contrast, 0.0);
      expect(clipAt(0).saturation, 0.0);
    });

    test('does not affect other clips', () {
      editor.updateSelectedColor(brightness: 0.4);
      expect(clipAt(1).brightness, 0.0);
      expect(clipAt(2).brightness, 0.0);
    });

    test('does nothing when no clip is selected', () {
      editor.removeSelected();
      editor.removeSelected();
      editor.removeSelected();
      expect(() => editor.updateSelectedColor(brightness: 0.5), returnsNormally);
    });
  });

  group('resetColor', () {
    test('resets brightness/contrast/saturation to neutral', () {
      editor.updateSelectedColor(brightness: 0.4, contrast: 1.5, saturation: 0.3);
      editor.resetColor();
      expect(clipAt(0).brightness, 0.0);
      expect(clipAt(0).contrast, 1.0);
      expect(clipAt(0).saturation, 1.0);
    });

    test('leaves the applied filter preset untouched', () {
      editor.setSelectedFilter('Noir');
      editor.resetColor();
      expect(clipAt(0).filterId, 'Noir');
    });
  });

  group('setSelectedFilter', () {
    test('sets the filter preset on the selected clip', () {
      editor.setSelectedFilter('Noir');
      expect(clipAt(0).filterId, 'Noir');
    });

    test('clears the filter preset when passed null', () {
      editor.setSelectedFilter('Noir');
      editor.setSelectedFilter(null);
      expect(clipAt(0).filterId, isNull);
    });

    test('does not affect other clips', () {
      editor.setSelectedFilter('Vivid');
      expect(clipAt(1).filterId, isNull);
      expect(clipAt(2).filterId, isNull);
    });

    test('does nothing when no clip is selected', () {
      editor.removeSelected();
      editor.removeSelected();
      editor.removeSelected();
      expect(() => editor.setSelectedFilter('Noir'), returnsNormally);
    });
  });
}
