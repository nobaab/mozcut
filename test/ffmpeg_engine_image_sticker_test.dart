import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/sticker_overlay.dart';

/// Exercises `FfmpegEngine.export`'s image-sticker burn-in (the `-i` input +
/// `overlay` filter [_buildFilterGraph] adds for a [StickerOverlay] whose
/// [StickerOverlay.imagePath] is set) without touching real media or a real
/// `ffmpeg` binary — same fake-ffmpeg-script approach as
/// test/ffmpeg_engine_canvas_test.dart.
void main() {
  late Directory tmp;
  late File captureFile;
  late String fakeFfmpeg;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_fake_ffmpeg_');
    captureFile = File('${tmp.path}/args.txt');
    fakeFfmpeg = '${tmp.path}/fake_ffmpeg.sh';
    File(fakeFfmpeg).writeAsStringSync(
        '#!/bin/sh\nprintf \'%s\\n\' "\$@" > "${captureFile.path}"\nexit 0\n');
    Process.runSync('chmod', ['+x', fakeFfmpeg]);
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

  test('an image sticker adds a -loop -i input and an overlay stage',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      stickerOverlays: [
        StickerOverlay(
          imagePath: '/tmp/circle.png',
          start: 1.5,
          end: 4.25,
          size: 0.3,
          x: 0.25,
          y: 0.6,
        ),
      ],
    );

    final args = capturedArgs();
    // The sticker's image file is fed in as its own `-loop 1 -i <path>`
    // input, in addition to the one clip's own input.
    expect(args, containsAllInOrder(['-loop', '1', '-i', '/tmp/circle.png']));

    final filter = capturedFilter(args);
    expect(filter, contains('format=rgba'));
    expect(filter, contains('scale2ref='));
    // The sticker's own `overlay` stage — distinct from the per-clip
    // bg/fg compositing `overlay` every export already has (which never
    // references `overlay_w`/`overlay_h`, only this stage does).
    expect(filter, contains('overlay_w/2'));
    expect(filter, contains('overlay_h/2'));
    // Scaled to the sticker's own `size` (a fraction of the output height).
    expect(filter, contains("main_h*0.300000"));
    // Positioned at its own x/y anchor.
    expect(filter, contains('main_w*0.250000'));
    expect(filter, contains('main_h*0.600000'));
    // Timed on the final timeline, same as every other overlay.
    expect(filter, contains("enable='between(t,1.500,4.250)'"));
    // An image sticker never goes through the emoji/drawtext path.
    expect(filter, isNot(contains('drawtext')));
  });

  test('an unrotated image sticker emits no rotate filter', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      stickerOverlays: [
        StickerOverlay(imagePath: '/tmp/circle.png', start: 0, end: 3),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, isNot(contains('rotate=')));
  });

  test('a rotated image sticker emits a rotate filter with its angle in radians',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      stickerOverlays: [
        StickerOverlay(
            imagePath: '/tmp/circle.png', start: 0, end: 3, rotation: 90),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    // 90 degrees == pi/2 radians == ~1.570796.
    expect(filter, contains('rotate=1.570796'));
    expect(filter, contains('c=none'));
  });

  test('an image sticker after a video clip indexes its own input correctly',
      () async {
    // Two real-video clips occupy inputs 0 and 1 — the sticker's image must
    // land on input 2, not collide with either clip's input.
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip(), clip()],
      outputPath: '${tmp.path}/out.mp4',
      stickerOverlays: [
        StickerOverlay(imagePath: '/tmp/circle.png', start: 0, end: 3),
      ],
    );

    final filter = capturedFilter(capturedArgs());
    expect(filter, contains('[2:v]format=rgba'));
  });

  test('emoji and image stickers can coexist on the same project', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      stickerOverlays: [
        StickerOverlay(emoji: '🔥', start: 0, end: 2),
        StickerOverlay(imagePath: '/tmp/circle.png', start: 2, end: 4),
      ],
    );

    final args = capturedArgs();
    expect(args, containsAllInOrder(['-loop', '1', '-i', '/tmp/circle.png']));
    final filter = capturedFilter(args);
    expect(filter, contains('drawtext='));
    expect(filter, contains('overlay='));
  });

  test(
      'no stickers at all reproduces the pre-feature graph '
      '(no sticker-overlay or drawtext stage)', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [clip()], outputPath: '${tmp.path}/out.mp4');

    final filter = capturedFilter(capturedArgs());
    // `scale2ref`/`format=rgba`/`drawtext` only ever appear as part of
    // sticker burn-in — the per-clip bg/fg compositing stage every export
    // already has does use `overlay=`, just not these.
    expect(filter, isNot(contains('scale2ref=')));
    expect(filter, isNot(contains('format=rgba')));
    expect(filter, isNot(contains('drawtext=')));
  });
}
