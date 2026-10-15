import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/transition_presets.dart';
import 'package:mozcut/ui/features/editor/views/transitions_panel.dart';

/// Pure tests of the transition-name -> ffmpeg `xfade` transition-type map
/// used by both the Transitions panel (selection UI) and FfmpegEngine
/// (export). No widgets, no ffmpeg process involved.
void main() {
  test('every transition in the Transitions panel catalogue has a mapped '
      'xfade transition type', () {
    for (final name in kTransitionCatalogue) {
      expect(kTransitionPresets.containsKey(name), isTrue,
          reason: '"$name" has no entry in kTransitionPresets');
    }
  });

  test('every mapped value is a transition type ffmpeg\'s xfade filter '
      'actually accepts', () {
    for (final entry in kTransitionPresets.entries) {
      expect(kXfadeTransitionTypes.contains(entry.value), isTrue,
          reason:
              '"${entry.key}" maps to "${entry.value}", which is not a '
              'known xfade transition type');
    }
  });

  test('xfadeTransitionFor resolves a known id to its mapped type', () {
    expect(xfadeTransitionFor('Dissolve'), 'dissolve');
    expect(xfadeTransitionFor('Push'), 'slideleft');
  });

  test('xfadeTransitionFor falls back to the default for an unknown id', () {
    expect(xfadeTransitionFor('Not A Real Transition'),
        kDefaultXfadeTransition);
  });

  test('kDefaultXfadeTransition is itself a valid xfade transition type', () {
    expect(kXfadeTransitionTypes.contains(kDefaultXfadeTransition), isTrue);
  });
}
