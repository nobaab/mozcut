import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/keyframe.dart';

/// Exercises `FfmpegEngine.export`'s filtergraph building for animated
/// (keyframed) clips, same fake-`ffmpeg` harness as
/// `ffmpeg_engine_canvas_test.dart` — no real media or `ffmpeg` binary
/// needed, so this runs anywhere `/bin/sh` exists.
///
/// The core guarantee under test: a clip with **no** keyframes produces
/// exactly the filtergraph it always has (no `t`/`T`-dependent expressions
/// anywhere), while a clip with 2+ keyframes on a property emits a
/// time-based ffmpeg expression for it.
void main() {
  late Directory tmp;
  late File captureFile;
  late String fakeFfmpeg;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_fake_ffmpeg_kf_');
    captureFile = File('${tmp.path}/args.txt');
    fakeFfmpeg = '${tmp.path}/fake_ffmpeg.sh';
    File(fakeFfmpeg).writeAsStringSync(
        '#!/bin/sh\nprintf \'%s\\n\' "\$@" > "${captureFile.path}"\nexit 0\n');
    Process.runSync('chmod', ['+x', fakeFfmpeg]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Clip staticClip() =>
      Clip(sourcePath: '/dev/null', sourceDuration: 5, inPoint: 0, outPoint: 5);

  String capturedFilter() {
    final args = captureFile.readAsLinesSync();
    final i = args.indexOf('-filter_complex');
    expect(i, greaterThanOrEqualTo(0), reason: '-filter_complex not found in $args');
    return args[i + 1];
  }

  Future<String> exportAndCapture(Clip clip) async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [clip], outputPath: '${tmp.path}/out.mp4');
    return capturedFilter();
  }

  group('an unanimated clip (no keyframes)', () {
    test('emits no t/T-dependent expression anywhere', () async {
      final filter = await exportAndCapture(staticClip());
      expect(filter, isNot(contains('lt(t,')));
      expect(filter, isNot(contains('lt(T,')));
      expect(filter, isNot(contains('eval=frame')));
      expect(filter, isNot(contains('geq=')));
    });

    test('is byte-identical whether or not the new opacity/keyframes '
        'fields are touched at their defaults', () async {
      final plain = await exportAndCapture(staticClip());
      final explicit = await exportAndCapture(
          staticClip().copyWith(opacity: 1.0, keyframes: const {}));
      expect(explicit, plain);
    });

    test('a single keyframe (no real animation) still produces a static '
        'filtergraph, pinned to that keyframe value', () async {
      final clip = staticClip().copyWith(keyframes: {
        kKeyframeScale: const [Keyframe(timeSec: 1.0, value: 2.0)],
      });
      final filter = await exportAndCapture(clip);
      expect(filter, isNot(contains('lt(t,')));
      expect(filter, contains('iw*2.0/2'));
    });
  });

  group('an animated clip (2+ keyframes)', () {
    test('position keyframes produce a t-dependent overlay x expression',
        () async {
      final clip = staticClip().copyWith(keyframes: {
        kKeyframePosX: const [
          Keyframe(timeSec: 0.0, value: 0.0),
          Keyframe(timeSec: 1.0, value: 1.0),
        ],
      });
      final filter = await exportAndCapture(clip);
      expect(filter, contains("overlay=x='(W-w)/2+("));
      expect(filter, contains('lt(t,'));
    });

    test('opacity keyframes produce a geq alpha expression keyed on '
        'uppercase T', () async {
      final clip = staticClip().copyWith(keyframes: {
        kKeyframeOpacity: const [
          Keyframe(timeSec: 0.0, value: 0.0),
          Keyframe(timeSec: 1.0, value: 1.0),
        ],
      });
      final filter = await exportAndCapture(clip);
      expect(filter, contains('format=yuva420p'));
      expect(filter, contains('geq='));
      expect(filter, contains('lt(T,'));
    });

    test('scale keyframes produce an eval=frame scale expression', () async {
      final clip = staticClip().copyWith(keyframes: {
        kKeyframeScale: const [
          Keyframe(timeSec: 0.0, value: 1.0),
          Keyframe(timeSec: 1.0, value: 2.0),
        ],
      });
      final filter = await exportAndCapture(clip);
      expect(filter, contains('eval=frame'));
      expect(filter, contains('lt(t,'));
    });

    test('rotation keyframes produce a t-dependent rotate angle with a '
        'fixed (hypot) bounding box', () async {
      final clip = staticClip().copyWith(keyframes: {
        kKeyframeRotation: const [
          Keyframe(timeSec: 0.0, value: 0.0),
          Keyframe(timeSec: 1.0, value: 90.0),
        ],
      });
      final filter = await exportAndCapture(clip);
      expect(filter, contains("rotate=a='("));
      expect(filter, contains('lt(t,'));
      expect(filter, contains('hypot(iw,ih)'));
    });

    test('an unrelated clip with no keyframes in the same export is '
        'unaffected by another clip being animated', () async {
      final animated = staticClip().copyWith(keyframes: {
        kKeyframeOpacity: const [
          Keyframe(timeSec: 0.0, value: 0.0),
          Keyframe(timeSec: 1.0, value: 1.0),
        ],
      });
      final plain = staticClip();
      final engine =
          FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
      await engine.export(
          clips: [plain, animated], outputPath: '${tmp.path}/out.mp4');
      final filter = capturedFilter();
      // Both clips' chains are present; only one carries geq/alpha.
      expect('geq='.allMatches(filter).length, 1);
    });
  });
}
