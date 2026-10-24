import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/video_overlay.dart';

/// Exercises `FfmpegEngine.export`'s video-overlay (picture-in-picture)
/// burn-in — the `-ss`/`-to`/`-i` input, the `scale2ref`/`overlay`(or
/// `blend`) chain [_buildFilterGraph] adds for a [VideoOverlay] — without
/// touching real media or a real `ffmpeg` binary. Same fake-ffmpeg-script
/// approach as test/ffmpeg_engine_image_sticker_test.dart.
///
/// The fake binary doubles as `ffprobe`: real export/renderPreview probes
/// each overlay's source for an audio stream (`_probeHasAudio`) before
/// deciding whether to wire it into the amix. The fake script recognizes
/// that specific probe invocation (it passes `-select_streams a`) and prints
/// a controllable response on stdout *without* touching the shared capture
/// file — only non-probe (i.e. real ffmpeg render) invocations overwrite it,
/// so `capturedArgs()` always reflects the final render call regardless of
/// how many probes ran first.
void main() {
  late Directory tmp;
  late File captureFile;
  late String fakeFfmpeg;

  /// [hasAudio] controls what the fake's `-select_streams a` branch prints:
  /// non-empty stdout (`hasAudio: true`) means "this source has audio",
  /// nothing (`false`) means it doesn't — matching real ffprobe's behaviour
  /// for an audio-less file.
  void writeFake({required bool hasAudio}) {
    File(fakeFfmpeg).writeAsStringSync('''
#!/bin/sh
case "\$*" in
  *"-select_streams a"*)
    ${hasAudio ? "echo 0" : ":"}
    exit 0
    ;;
esac
printf '%s\\n' "\$@" > "${captureFile.path}"
exit 0
''');
    Process.runSync('chmod', ['+x', fakeFfmpeg]);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_fake_ffmpeg_vo_');
    captureFile = File('${tmp.path}/args.txt');
    fakeFfmpeg = '${tmp.path}/fake_ffmpeg.sh';
    writeFake(hasAudio: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Clip clip() =>
      Clip(sourcePath: '/dev/null', sourceDuration: 5, inPoint: 0, outPoint: 5);

  List<String> capturedArgs() => captureFile.readAsLinesSync();

  /// The `-filter_complex` argument value ffmpeg was invoked with.
  String capturedFilter(List<String> args) {
    final i = args.indexOf('-filter_complex');
    expect(i, greaterThanOrEqualTo(0), reason: '-filter_complex not found in $args');
    return args[i + 1];
  }

  test('a video overlay adds a trimmed -ss/-to/-i input and an overlay stage',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(
          sourcePath: '/tmp/pip.mp4',
          sourceDuration: 10,
          inPoint: 1.5,
          outPoint: 4.0,
          startTime: 2.0,
          scale: 0.4,
          posX: 0.75,
          posY: 0.3,
        ),
      ],
    );

    final args = capturedArgs();
    // The overlay's source is fed in as its own trimmed `-ss`/`-to`/`-i`
    // input, in addition to the one clip's own input.
    expect(
        args,
        containsAllInOrder(
            ['-ss', '1.500', '-to', '4.000', '-i', '/tmp/pip.mp4']));

    final filter = capturedFilter(args);
    // Reset to pts 0, then shifted to appear at `startTime` on the output
    // timeline.
    expect(filter, contains('setpts=PTS-STARTPTS+2.000000/TB'));
    // Scaled with a plain `scale` to absolute pixels: a fraction (0.4) of the
    // canvas width (1920) = 768, aspect preserved via `-2`. (Plain `scale`,
    // not `scale2ref`, to avoid the chained-scale2ref dead-lock.)
    expect(filter, contains('scale=768:-2'));
    expect(filter, isNot(contains('scale2ref=')));
    // The overlay's own `overlay` stage — distinct from the per-clip
    // bg/fg compositing `overlay` every export already has (which never
    // references `overlay_w`/`overlay_h`, only this stage does).
    expect(filter, contains('overlay_w/2'));
    expect(filter, contains('overlay_h/2'));
    // Positioned at its own posX/posY anchor.
    expect(filter, contains('main_w*0.750000'));
    expect(filter, contains('main_h*0.300000'));
    // Timed on the final timeline: startTime .. startTime+duration (2.5s).
    expect(filter, contains("enable='between(t,2.000,4.500)'"));
    // 'normal' blend mode never uses the `blend` filter.
    expect(filter, isNot(contains('blend=')));
  });

  test('input-index correctness: the overlay lands on its own input, after '
      'every clip', () async {
    // Two real-video clips occupy inputs 0 and 1 — the overlay's video must
    // land on input 2, not collide with either clip's input.
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip(), clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, contains('[2:v:0]format=rgba'));
  });

  test('opacity below 1.0 adds a colorchannelmixer stage in normal mode',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5, opacity: 0.4),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, contains('colorchannelmixer=aa=0.400000'));
  });

  test('full opacity (the default) never adds colorchannelmixer', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, isNot(contains('colorchannelmixer')));
  });

  test('rotation emits a rotate filter with its angle in radians (normal mode)',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5, rotation: 90),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    // 90 degrees == pi/2 radians == ~1.570796.
    expect(filter, contains('rotate=1.570796'));
    expect(filter, contains('c=none'));
  });

  test('a non-normal blend mode uses ffmpeg\'s blend filter at full canvas '
      'size instead of overlay', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(
          sourcePath: '/tmp/pip.mp4',
          sourceDuration: 5,
          blendMode: 'screen',
          opacity: 0.8,
          startTime: 1.0,
        ),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, contains('blend=all_mode=screen:all_opacity=0.800000'));
    // Scaled to the full canvas (1920x1080), not the overlay's own `scale` —
    // `blend` requires both inputs to be the same size.
    expect(filter, contains('scale=1920:1080'));
    // Still windowed on the final timeline, same as the normal path.
    expect(filter, contains("enable='between(t,1.000,"));
    // A blend-mode overlay is never composited with the plain `overlay`
    // filter (it would require the mismatched PiP-sized frame).
    expect(filter, isNot(contains('overlay_w/2')));
  });

  test('a video overlay with audio is mixed into the amix via adelay',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5, startTime: 1.5),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, contains('[1:a:0]adelay=1500:all=1'));
    expect(filter, contains('amix=inputs=2'));
  });

  test('a video overlay with no audio stream is never referenced in the '
      'amix (and never breaks the graph)', () async {
    writeFake(hasAudio: false);
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, isNot(contains('adelay')));
    expect(filter, isNot(contains('amix')));
  });

  test(
      'no video overlays at all reproduces the pre-feature graph byte for '
      'byte (parity)', () async {
    final withoutOverlay =
        FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await withoutOverlay.export(clips: [clip()], outputPath: '${tmp.path}/a.mp4');
    final baseline = capturedFilter(capturedArgs());

    // Same call, but with an explicit empty list — must be identical, since
    // that's what every existing call site (pre-feature) effectively passes.
    final explicit =
        FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await explicit.export(
        clips: [clip()], outputPath: '${tmp.path}/b.mp4', videoOverlays: const []);
    final withExplicitEmpty = capturedFilter(capturedArgs());

    expect(withExplicitEmpty, baseline);
    expect(baseline, isNot(contains('scale2ref=')));
    expect(baseline, isNot(contains('setpts=PTS-STARTPTS')));
    expect(baseline, isNot(contains('overlay_w/2')));
    expect(baseline, isNot(contains('blend=')));
  });

  test('renderPreview threads videoOverlays through the same filtergraph',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.renderPreview(
      clips: [clip()],
      videoOverlays: [
        VideoOverlay(sourcePath: '/tmp/pip.mp4', sourceDuration: 5),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    // The overlay composites at canvas size (0.5 * 1920 = 960) and the preview
    // proxy downscale (`scale=640:-2`) runs LAST, after the overlay — so a PiP
    // appears in the preview at the same relative size it will in the export.
    expect(filter, contains('scale=960:-2'));
    expect(filter, contains('[vsfinal]'));
    expect(filter.indexOf('overlay='), lessThan(filter.indexOf('[vsfinal]')));
  });
}
