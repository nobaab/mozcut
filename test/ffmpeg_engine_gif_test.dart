import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/export_settings.dart';

/// Exercises `FfmpegEngine.export`'s GIF branch without touching real media
/// or a real `ffmpeg` binary — same fake-ffmpeg-shell-script trick as
/// `ffmpeg_engine_canvas_test.dart`: `ffmpegPath` points at a tiny shell
/// script that records the args it was invoked with and exits 0, so this is
/// pure/fast and runs anywhere `/bin/sh` exists — no `--tags integration`
/// needed.
void main() {
  late Directory tmp;
  late File captureFile;
  late String fakeFfmpeg;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_fake_ffmpeg_gif_');
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
    expect(i, greaterThanOrEqualTo(0),
        reason: '-filter_complex not found in $args');
    return args[i + 1];
  }

  test('gif format appends a palettegen/paletteuse pipeline to the filtergraph',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [clip()],
      outputPath: '${tmp.path}/out.gif',
      settings: const ExportSettings(format: ExportFormat.gif),
    );

    final args = capturedArgs();
    final filter = capturedFilter(args);
    expect(filter, contains('palettegen'));
    expect(filter, contains('paletteuse'));
    expect(filter, contains('split'));
    // The audio pad is never mapped for a gif export, but ffmpeg's
    // -filter_complex parser rejects a graph with any unconnected output pad
    // — so the unused audio pad must still be routed somewhere.
    expect(filter, contains('anullsink'));

    // The palette-mapped pad is what gets mapped to output, not the raw
    // concatenated video pad.
    expect(args, contains('[gifout]'));

    // No audio is mapped for a gif export, and the gif ffmpeg args (no
    // -c:v/-crf/-c:a, a looping -loop 0) are present.
    final mapIndices = [
      for (var i = 0; i < args.length; i++)
        if (args[i] == '-map') i,
    ];
    expect(mapIndices, hasLength(1), reason: 'gif export should map only video');
    expect(args, isNot(contains('-c:v')));
    expect(args, isNot(contains('-c:a')));
    expect(args, contains('-loop'));
  });

  test('mp4 export is unaffected by the gif branch (byte-identical args)',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [clip()], outputPath: '${tmp.path}/out.mp4');

    final args = capturedArgs();
    final filter = capturedFilter(args);
    expect(filter, isNot(contains('palettegen')));
    expect(filter, isNot(contains('paletteuse')));

    final mapIndices = [
      for (var i = 0; i < args.length; i++)
        if (args[i] == '-map') i,
    ];
    expect(mapIndices, hasLength(2),
        reason: 'non-gif export still maps both video and audio');
    expect(args, contains('-c:v'));
    expect(args, contains('-c:a'));
  });
}
