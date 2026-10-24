import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/sfx_presets.dart';

/// Pure tests of the Audio panel's built-in sound-effect catalogue and its
/// id -> ffmpeg-command mapping. No widgets, no ffmpeg process involved —
/// mirrors test/effect_presets_test.dart's split for the Effects panel.
void main() {
  test('every preset has a unique, non-empty id', () {
    final ids = kSfxPresets.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: 'duplicate id in kSfxPresets: $ids');
    for (final id in ids) {
      expect(id.trim(), isNotEmpty);
    }
  });

  test('every preset has a positive duration and a non-empty lavfi source',
      () {
    for (final preset in kSfxPresets) {
      expect(preset.duration, greaterThan(0),
          reason: '"${preset.id}" has a non-positive duration');
      expect(preset.lavfiSource.trim(), isNotEmpty,
          reason: '"${preset.id}" has an empty lavfi source');
    }
  });

  test('buildArgs produces a valid lavfi ffmpeg argv with no -af when unset',
      () {
    const preset = SfxPreset(
      id: 'test-tone',
      label: 'Test tone',
      category: SfxCategory.tone,
      duration: 1.5,
      lavfiSource: 'sine=frequency=440:duration=1.5',
    );
    final args = preset.buildArgs('/tmp/out.wav');
    expect(args, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=1.5',
      '-t',
      '1.500',
      '/tmp/out.wav',
    ]);
  });

  test('buildArgs threads an -af filter chain when the preset has one', () {
    const preset = SfxPreset(
      id: 'test-sfx',
      label: 'Test sfx',
      category: SfxCategory.sfx,
      duration: 0.2,
      lavfiSource: 'anoisesrc=duration=0.2:color=pink',
      audioFilter: 'afade=t=out:st=0.1:d=0.1',
    );
    final args = preset.buildArgs('/tmp/out.wav');
    expect(args, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anoisesrc=duration=0.2:color=pink',
      '-af',
      'afade=t=out:st=0.1:d=0.1',
      '-t',
      '0.200',
      '/tmp/out.wav',
    ]);
  });

  test('catalogue covers both tones and shaped effects', () {
    expect(kSfxPresets.any((p) => p.category == SfxCategory.tone), isTrue);
    expect(kSfxPresets.any((p) => p.category == SfxCategory.sfx), isTrue);
  });

  test('known builtin ids are present with their expected source family', () {
    SfxPreset byId(String id) => kSfxPresets.firstWhere((p) => p.id == id);

    expect(byId('beep').lavfiSource, contains('sine'));
    expect(byId('tick').lavfiSource, contains('sine'));
    expect(byId('click').lavfiSource, contains('sine'));
    expect(byId('pop').lavfiSource, contains('sine'));
    expect(byId('boom').lavfiSource, contains('sine'));
    expect(byId('whoosh').lavfiSource, contains('anoisesrc'));
  });
}
