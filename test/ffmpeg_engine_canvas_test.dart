import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';

/// Exercises `FfmpegEngine.export`'s filtergraph building without touching
/// real media or a real `ffmpeg` binary: `ffmpegPath` is pointed at a tiny
/// shell script that just records the args it was invoked with (to
/// [captureFile]) and exits 0, so this is pure/fast and runs anywhere `/bin/sh`
/// exists — no `--tags integration` needed.
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

  /// The `-filter_complex` argument value ffmpeg was invoked with.
  String capturedFilter() {
    final args = captureFile.readAsLinesSync();
    final i = args.indexOf('-filter_complex');
    expect(i, greaterThanOrEqualTo(0), reason: '-filter_complex not found in $args');
    return args[i + 1];
  }

  test('export uses the default 1920x1080 canvas when none is passed', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [clip()], outputPath: '${tmp.path}/out.mp4');

    final filter = capturedFilter();
    expect(filter, contains('s=1920x1080'));
    expect(filter, contains('scale=w=1920:h=1080:force_original_aspect_ratio=decrease'));
  });

  test('export threads a passed non-default canvas into the filtergraph', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.mp4',
      canvasWidth: 1080,
      canvasHeight: 1920,
    );

    final filter = capturedFilter();
    expect(filter, contains('s=1080x1920'));
    expect(filter, contains('scale=w=1080:h=1920:force_original_aspect_ratio=decrease'));
    expect(filter, isNot(contains('s=1920x1080')));
  });

  test('renderPreview threads a passed non-default canvas into the filtergraph',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.renderPreview(
      clips: [clip()],
      canvasWidth: 1440,
      canvasHeight: 1080,
    );

    final filter = capturedFilter();
    expect(filter, contains('s=1440x1080'));
  });
}
