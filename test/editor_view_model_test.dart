import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/keyframe.dart';
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

  group('undo/redo', () {
    test('starts with nothing to undo or redo', () {
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isFalse);
    });

    test('undo restores the state from before a mutation', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 3);
      expect(clipAt(0).inPoint, 3);

      expect(editor.canUndo, isTrue);
      editor.undo();

      expect(clipAt(0).inPoint, 0);
      expect(container.read(editorProvider).clips.length, 3);
    });

    test('redo re-applies a mutation that was undone', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 3);
      editor.undo();
      expect(clipAt(0).inPoint, 0);

      expect(editor.canRedo, isTrue);
      editor.redo();
      expect(clipAt(0).inPoint, 3);
    });

    test('undo on removeSelected restores the removed clip', () {
      editor.select(clipAt(0).id);
      editor.removeSelected();
      expect(container.read(editorProvider).clips.length, 2);

      editor.undo();
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['a.mp4', 'b.mp4', 'c.mp4']);
    });

    test('a new mutation after undo clears the redo stack', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 3);
      editor.undo();
      expect(editor.canRedo, isTrue);

      editor.setTrim(id, inPoint: 5);
      expect(editor.canRedo, isFalse);
    });

    test('undo is a no-op when there is nothing to undo', () {
      expect(editor.canUndo, isFalse);
      editor.undo();
      final names = container
          .read(editorProvider)
          .clips
          .map((c) => c.fileName)
          .toList();
      expect(names, ['a.mp4', 'b.mp4', 'c.mp4']);
    });

    test('redo is a no-op when there is nothing to redo', () {
      editor.setTrim(clipAt(0).id, inPoint: 3);
      editor.redo();
      expect(clipAt(0).inPoint, 3);
    });

    test('a no-op mutation (invalid id/index) does not push undo history',
        () {
      editor.setTrim('does-not-exist', inPoint: 5);
      expect(editor.canUndo, isFalse);

      editor.reorder(99, 0);
      expect(editor.canUndo, isFalse);
    });

    test('selecting a clip is not itself undoable', () {
      editor.select(clipAt(1).id);
      expect(editor.canUndo, isFalse);
    });

    test('later mutation does not corrupt an earlier undo snapshot', () {
      final id = clipAt(0).id;
      editor.setTrim(id, inPoint: 1);
      editor.setTrim(id, inPoint: 2);
      editor.setTrim(id, inPoint: 3);
      expect(clipAt(0).inPoint, 3);

      editor.undo(); // back to inPoint 2
      editor.undo(); // back to inPoint 1
      expect(clipAt(0).inPoint, 1);

      editor.redo(); // forward to inPoint 2
      expect(clipAt(0).inPoint, 2);
    });

    test('undo stack is capped so it cannot grow without bound', () {
      final id = clipAt(0).id;
      // One more than the cap (100): every call is a distinct, valid trim so
      // each one pushes history.
      for (var i = 0; i < 150; i++) {
        editor.setTrim(id, inPoint: (i % 9) * 0.5 + 0.1);
      }
      for (var i = 0; i < 150; i++) {
        editor.undo();
      }
      // The stack was capped at 100 entries, so after undoing far more than
      // that there's nothing left to undo.
      expect(editor.canUndo, isFalse);
    });

    test('loadClips resets undo/redo history', () {
      editor.setTrim(clipAt(0).id, inPoint: 3);
      expect(editor.canUndo, isTrue);

      editor.loadClips([Clip(sourcePath: '/d.mp4', sourceDuration: 5)]);
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isFalse);

      // And undo() afterwards is a no-op — it must not resurrect the
      // previous project's clips.
      editor.undo();
      expect(container.read(editorProvider).clips.length, 1);
      expect(clipAt(0).fileName, 'd.mp4');
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

  group('setSelectedEffect', () {
    test('sets the effect on the selected clip', () {
      editor.setSelectedEffect('Gaussian Blur');
      expect(clipAt(0).effectId, 'Gaussian Blur');
    });

    test('clears the effect when passed null', () {
      editor.setSelectedEffect('Gaussian Blur');
      editor.setSelectedEffect(null);
      expect(clipAt(0).effectId, isNull);
    });

    test('does not affect other clips', () {
      editor.setSelectedEffect('Vignette');
      expect(clipAt(1).effectId, isNull);
      expect(clipAt(2).effectId, isNull);
    });

    test('is independent of the filter preset', () {
      editor.setSelectedFilter('Noir');
      editor.setSelectedEffect('Film Grain');
      expect(clipAt(0).filterId, 'Noir');
      expect(clipAt(0).effectId, 'Film Grain');
    });

    test('does nothing when no clip is selected', () {
      editor.removeSelected();
      editor.removeSelected();
      editor.removeSelected();
      expect(() => editor.setSelectedEffect('Vignette'), returnsNormally);
    });

    test('is undoable', () {
      editor.setSelectedEffect('Vignette');
      expect(clipAt(0).effectId, 'Vignette');
      editor.undo();
      expect(clipAt(0).effectId, isNull);
    });
  });

  group('setSelectedTransition', () {
    test('sets the transition on the selected clip', () {
      editor.setSelectedTransition('Dissolve');
      expect(clipAt(0).transitionId, 'Dissolve');
    });

    test('leaves transitionDuration at its default when none is given', () {
      editor.setSelectedTransition('Dissolve');
      expect(clipAt(0).transitionDuration, 0.5);
    });

    test('sets the duration alongside the transition when given', () {
      editor.setSelectedTransition('Push', duration: 1.5);
      expect(clipAt(0).transitionId, 'Push');
      expect(clipAt(0).transitionDuration, 1.5);
    });

    test('clamps an out-of-range duration', () {
      editor.setSelectedTransition('Push', duration: 50.0);
      expect(clipAt(0).transitionDuration, 5.0);
      editor.setSelectedTransition('Push', duration: -1.0);
      expect(clipAt(0).transitionDuration, 0.05);
    });

    test('clears the transition when passed null', () {
      editor.setSelectedTransition('Dissolve');
      editor.setSelectedTransition(null);
      expect(clipAt(0).transitionId, isNull);
    });

    test('does not affect other clips', () {
      editor.setSelectedTransition('Zoom');
      expect(clipAt(1).transitionId, isNull);
      expect(clipAt(2).transitionId, isNull);
    });

    test('does nothing when no clip is selected', () {
      editor.removeSelected();
      editor.removeSelected();
      editor.removeSelected();
      expect(() => editor.setSelectedTransition('Dissolve'), returnsNormally);
    });
  });

  group('keyframes', () {
    test('addKeyframe records a keyframe on the selected clip', () {
      editor.addKeyframe(kKeyframeScale, 1.0, 2.0);
      expect(clipAt(0).keyframes[kKeyframeScale],
          [const Keyframe(timeSec: 1.0, value: 2.0)]);
    });

    test('addKeyframe at an existing time replaces it instead of '
        'duplicating', () {
      editor.addKeyframe(kKeyframeScale, 1.0, 2.0);
      editor.addKeyframe(kKeyframeScale, 1.0, 5.0);
      expect(clipAt(0).keyframes[kKeyframeScale],
          [const Keyframe(timeSec: 1.0, value: 5.0)]);
    });

    test('addKeyframe keeps the list sorted by time regardless of '
        'insertion order', () {
      editor.addKeyframe(kKeyframeRotation, 2.0, 90.0);
      editor.addKeyframe(kKeyframeRotation, 0.0, 0.0);
      editor.addKeyframe(kKeyframeRotation, 1.0, 45.0);
      final times =
          clipAt(0).keyframes[kKeyframeRotation]!.map((k) => k.timeSec);
      expect(times, [0.0, 1.0, 2.0]);
    });

    test('does not affect other clips', () {
      editor.addKeyframe(kKeyframeScale, 1.0, 2.0);
      expect(clipAt(1).keyframes[kKeyframeScale], isNull);
    });

    test('is undoable', () {
      editor.addKeyframe(kKeyframeScale, 1.0, 2.0);
      editor.undo();
      expect(clipAt(0).keyframes[kKeyframeScale] ?? const [], isEmpty);
    });

    test('removeKeyframe drops the keyframe nearest the given time', () {
      editor.addKeyframe(kKeyframePosX, 0.0, 0.1);
      editor.addKeyframe(kKeyframePosX, 1.0, 0.5);
      editor.removeKeyframe(kKeyframePosX, 0.0);
      expect(clipAt(0).keyframes[kKeyframePosX],
          [const Keyframe(timeSec: 1.0, value: 0.5)]);
    });

    test('removeKeyframe on an unknown time is a no-op', () {
      editor.addKeyframe(kKeyframePosX, 0.0, 0.1);
      editor.removeKeyframe(kKeyframePosX, 99.0);
      expect(clipAt(0).keyframes[kKeyframePosX]!.length, 1);
    });

    test('removeKeyframe drops the map entry once the list is empty', () {
      editor.addKeyframe(kKeyframePosX, 0.0, 0.1);
      editor.removeKeyframe(kKeyframePosX, 0.0);
      expect(clipAt(0).keyframes.containsKey(kKeyframePosX), isFalse);
    });

    test('clearKeyframes removes every keyframe for the property', () {
      editor.addKeyframe(kKeyframeOpacity, 0.0, 0.0);
      editor.addKeyframe(kKeyframeOpacity, 1.0, 1.0);
      editor.clearKeyframes(kKeyframeOpacity);
      expect(clipAt(0).keyframes.containsKey(kKeyframeOpacity), isFalse);
    });

    test('clearKeyframes leaves other properties untouched', () {
      editor.addKeyframe(kKeyframeOpacity, 0.0, 0.0);
      editor.addKeyframe(kKeyframeScale, 0.0, 1.5);
      editor.clearKeyframes(kKeyframeOpacity);
      expect(clipAt(0).keyframes.containsKey(kKeyframeScale), isTrue);
    });

    test('addKeyframeAtPlayhead records the clip-relative playhead time '
        'and current static value', () {
      editor.setTrim(clipAt(0).id, inPoint: 2);
      container.read(playheadProvider.notifier).set(5); // source seconds
      editor.updateTransform(scale: 3.0);
      editor.addKeyframeAtPlayhead(kKeyframeScale);
      // clip-relative = playhead(5) - inPoint(2) = 3
      expect(clipAt(0).keyframes[kKeyframeScale],
          [const Keyframe(timeSec: 3.0, value: 3.0)]);
    });

    test('updateTransform writes into keyframes instead of the static '
        'field once a property is animated', () {
      editor.addKeyframe(kKeyframeScale, 0.0, 1.0);
      container.read(playheadProvider.notifier).set(2); // clip-relative 2
      editor.updateTransform(scale: 4.0);

      final clip = clipAt(0);
      // The static field is untouched...
      expect(clip.scale, 1.0);
      // ...but a new keyframe appeared at the playhead with the new value.
      expect(clip.keyframes[kKeyframeScale], [
        const Keyframe(timeSec: 0.0, value: 1.0),
        const Keyframe(timeSec: 2.0, value: 4.0),
      ]);
    });

    test('updateTransform still writes the static field for a property '
        'with no keyframes', () {
      editor.addKeyframe(kKeyframeScale, 0.0, 1.0);
      editor.updateTransform(scale: 4.0, rotation: 30.0);

      expect(clipAt(0).rotation, 30.0);
      expect(clipAt(0).keyframes.containsKey(kKeyframeRotation), isFalse);
    });
  });

  group('applyAnimation', () {
    test('Fade-In writes opacity 0 -> 1 over duration and records the '
        'preset', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframeOpacity], [
        const Keyframe(timeSec: 0.0, value: 0.0),
        const Keyframe(timeSec: 0.5, value: 1.0),
      ]);
      expect(clipAt(0).animationIn, kAnimFade);
      expect(clipAt(0).animationInDuration, 0.5);
    });

    test('Fade-Out writes opacity 1 -> 0 over the last duration seconds',
        () {
      // clipAt(0).duration == 10 (default sourceDuration, untrimmed).
      editor.applyAnimation(isIn: false, preset: kAnimFade, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframeOpacity], [
        const Keyframe(timeSec: 9.5, value: 1.0),
        const Keyframe(timeSec: 10.0, value: 0.0),
      ]);
      expect(clipAt(0).animationOut, kAnimFade);
      expect(clipAt(0).animationOutDuration, 0.5);
    });

    test('Zoom In writes scale 1.2 -> 1.0 (In) / 1.0 -> 1.2 (Out)', () {
      editor.applyAnimation(isIn: true, preset: kAnimZoomIn, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframeScale], [
        const Keyframe(timeSec: 0.0, value: 1.2),
        const Keyframe(timeSec: 0.5, value: 1.0),
      ]);

      editor.applyAnimation(isIn: false, preset: kAnimZoomIn, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframeScale], [
        const Keyframe(timeSec: 0.0, value: 1.2),
        const Keyframe(timeSec: 0.5, value: 1.0),
        const Keyframe(timeSec: 9.5, value: 1.0),
        const Keyframe(timeSec: 10.0, value: 1.2),
      ]);
    });

    test('Slide Left comes in from the right and exits further left', () {
      editor.applyAnimation(
          isIn: true, preset: kAnimSlideLeft, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframePosX], [
        const Keyframe(timeSec: 0.0, value: 1.0),
        const Keyframe(timeSec: 0.5, value: 0.0),
      ]);

      editor.applyAnimation(
          isIn: false, preset: kAnimSlideLeft, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframePosX], [
        const Keyframe(timeSec: 0.0, value: 1.0),
        const Keyframe(timeSec: 0.5, value: 0.0),
        const Keyframe(timeSec: 9.5, value: 0.0),
        const Keyframe(timeSec: 10.0, value: -1.0),
      ]);
    });

    test('applying kAnimNone clears the edge\'s keyframes', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      editor.applyAnimation(isIn: true, preset: kAnimNone, duration: 0.5);
      expect(clipAt(0).keyframes.containsKey(kKeyframeOpacity), isFalse);
      expect(clipAt(0).animationIn, isNull);
    });

    test('switching preset on the same edge removes the previous preset\'s '
        'keyframes instead of leaving them behind', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      editor.applyAnimation(isIn: true, preset: kAnimZoomIn, duration: 0.5);
      expect(clipAt(0).keyframes.containsKey(kKeyframeOpacity), isFalse);
      expect(clipAt(0).keyframes[kKeyframeScale], [
        const Keyframe(timeSec: 0.0, value: 1.2),
        const Keyframe(timeSec: 0.5, value: 1.0),
      ]);
    });

    test('changing duration on the same preset moves its keyframes rather '
        'than adding new ones', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 1.0);
      expect(clipAt(0).keyframes[kKeyframeOpacity], [
        const Keyframe(timeSec: 0.0, value: 0.0),
        const Keyframe(timeSec: 1.0, value: 1.0),
      ]);
    });

    test('applying Fade to the In edge does not touch the Out edge, even '
        'when both animate the same property', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      editor.applyAnimation(isIn: false, preset: kAnimFade, duration: 0.3);
      editor.applyAnimation(isIn: true, preset: kAnimNone, duration: 0.5);
      expect(clipAt(0).keyframes[kKeyframeOpacity], [
        const Keyframe(timeSec: 9.7, value: 1.0),
        const Keyframe(timeSec: 10.0, value: 0.0),
      ]);
      expect(clipAt(0).animationOut, kAnimFade);
    });

    test('duration is clamped to 0.1..3s', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 10.0);
      expect(clipAt(0).animationInDuration, 3.0);
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.0);
      expect(clipAt(0).animationInDuration, 0.1);
    });

    test('does not affect other clips', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      expect(clipAt(1).animationIn, isNull);
      expect(clipAt(1).keyframes.containsKey(kKeyframeOpacity), isFalse);
    });

    test('is undoable', () {
      editor.applyAnimation(isIn: true, preset: kAnimFade, duration: 0.5);
      editor.undo();
      expect(clipAt(0).animationIn, isNull);
      expect(clipAt(0).keyframes.containsKey(kKeyframeOpacity), isFalse);
    });
  });

  group('applyComboAnimation', () {
    test('applies the same preset/duration to both edges in one undo step',
        () {
      editor.applyComboAnimation(preset: kAnimFade, duration: 0.5);
      expect(clipAt(0).animationIn, kAnimFade);
      expect(clipAt(0).animationOut, kAnimFade);
      expect(clipAt(0).keyframes[kKeyframeOpacity], [
        const Keyframe(timeSec: 0.0, value: 0.0),
        const Keyframe(timeSec: 0.5, value: 1.0),
        const Keyframe(timeSec: 9.5, value: 1.0),
        const Keyframe(timeSec: 10.0, value: 0.0),
      ]);

      editor.undo();
      expect(clipAt(0).animationIn, isNull);
      expect(clipAt(0).animationOut, isNull);
      expect(clipAt(0).keyframes.containsKey(kKeyframeOpacity), isFalse);
    });
  });
}
