import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/shape_presets.dart';

/// Pure tests of the Stickers panel's built-in shape catalogue and its
/// id -> ffmpeg-command mapping. No widgets, no ffmpeg process involved —
/// mirrors test/sfx_presets_test.dart's split for the Audio panel.
void main() {
  test('every preset has a unique, non-empty id', () {
    final ids = kShapePresets.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: 'duplicate id in kShapePresets: $ids');
    for (final id in ids) {
      expect(id.trim(), isNotEmpty);
    }
  });

  test('every preset has a non-empty -vf filter chain', () {
    for (final preset in kShapePresets) {
      expect(preset.vfFilter.trim(), isNotEmpty,
          reason: '"${preset.id}" has an empty vfFilter');
    }
  });

  test('buildArgs produces a valid lavfi ffmpeg argv', () {
    const preset = ShapePreset(
      id: 'test-shape',
      label: 'Test shape',
      vfFilter: "format=rgba,drawbox=x=0:y=0:w=10:h=10:color=white@1.0",
    );
    final args = preset.buildArgs('/tmp/out.png');
    expect(args, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=black@0.0:s=${kShapeCanvasSize}x$kShapeCanvasSize:d=1',
      '-vf',
      'format=rgba,drawbox=x=0:y=0:w=10:h=10:color=white@1.0',
      '-frames:v',
      '1',
      '-update',
      '1',
      '/tmp/out.png',
    ]);
  });

  test('the catalogue covers rectangle, circle, arrow and speech bubble', () {
    final ids = kShapePresets.map((p) => p.id).toSet();
    expect(ids, containsAll(['rectangle', 'circle', 'arrow', 'speech_bubble']));
  });

  test('never draws a copyrighted character/logo — every shape is a plain '
      'geometric fill, not text/emoji/drawtext', () {
    for (final preset in kShapePresets) {
      expect(preset.vfFilter, isNot(contains('drawtext')));
      expect(preset.vfFilter, anyOf(contains('drawbox'), contains('geq')));
    }
  });

  test('geq-based shapes only use eval registers 0-9 (ffmpeg\'s st()/ld() '
      'scratch-register range)', () {
    final registerPattern = RegExp(r'(?:st|ld)\((\d+)');
    for (final preset in kShapePresets) {
      for (final match in registerPattern.allMatches(preset.vfFilter)) {
        final index = int.parse(match.group(1)!);
        expect(index, inInclusiveRange(0, 9),
            reason:
                '"${preset.id}" uses out-of-range register $index, which '
                'silently aliases another register in real ffmpeg builds');
      }
    }
  });
}
