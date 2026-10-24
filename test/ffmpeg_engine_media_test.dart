import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/engine/ffmpeg_engine.dart';
import 'package:mozcut/domain/models/audio_clip.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/media_type.dart';

/// Exercises `FfmpegEngine.export`'s handling of image clips and audio-lane
/// clips without touching real media or a real `ffmpeg` binary — same
/// fake-ffmpeg-script technique as `ffmpeg_engine_canvas_test.dart`.
void main() {
  late Directory tmp;
  late File captureFile;
  late String fakeFfmpeg;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mozcut_fake_ffmpeg_media_');
    captureFile = File('${tmp.path}/args.txt');
    fakeFfmpeg = '${tmp.path}/fake_ffmpeg.sh';
    File(fakeFfmpeg).writeAsStringSync(
        '#!/bin/sh\nprintf \'%s\\n\' "\$@" > "${captureFile.path}"\nexit 0\n');
    Process.runSync('chmod', ['+x', fakeFfmpeg]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> capturedArgs() => captureFile.readAsLinesSync();

  /// The `-filter_complex` argument value ffmpeg was invoked with.
  String capturedFilter() {
    final args = capturedArgs();
    final i = args.indexOf('-filter_complex');
    expect(i, greaterThanOrEqualTo(0),
        reason: '-filter_complex not found in $args');
    return args[i + 1];
  }

  Clip videoClip() => Clip(
      sourcePath: '/dev/null', sourceDuration: 5, inPoint: 0, outPoint: 5);

  test('an image clip is fed in as -loop 1 -t <duration> -i <path>',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    final imageClip = Clip(
      sourcePath: '/pics/a.jpg',
      sourceDuration: kImageSourceDurationCap,
      outPoint: kImageDefaultDuration,
      mediaType: MediaType.image,
    );

    await engine.export(clips: [imageClip], outputPath: '${tmp.path}/out.mp4');

    final args = capturedArgs();
    final iIndex = args.indexOf('/pics/a.jpg');
    expect(iIndex, greaterThan(0), reason: 'image path not found in $args');
    // The flags immediately preceding "-i <path>" should be "-loop 1 -t <n>".
    expect(args[iIndex - 1], '-i');
    expect(args[iIndex - 2], kImageDefaultDuration.toStringAsFixed(3));
    expect(args[iIndex - 3], '-t');
    expect(args[iIndex - 4], '1');
    expect(args[iIndex - 5], '-loop');

    // A silent-audio input follows, so the image clip's audio pad exists.
    expect(args, contains('anullsrc=r=48000:cl=stereo'));
    expect(args, contains('lavfi'));
  });

  test('a plain video clip is unaffected by the image-input handling',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [videoClip()], outputPath: '${tmp.path}/out.mp4');

    final args = capturedArgs();
    expect(args, isNot(contains('-loop')));
    expect(args, isNot(contains('anullsrc=r=48000:cl=stereo')));
  });

  test('an empty audioClips list leaves [outa] completely untouched',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(clips: [videoClip()], outputPath: '${tmp.path}/out.mp4');
    final withoutAudioClips = capturedFilter();

    expect(withoutAudioClips, isNot(contains('amix')));
    expect(withoutAudioClips, isNot(contains('adelay')));
    expect(withoutAudioClips, contains('[outa]'));
  });

  test('audioClips are mixed in via adelay + amix, placed at their start',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    final audioClip = AudioClip(
      sourcePath: '/music/track.mp3',
      sourceDuration: 30,
      start: 2.5,
      inPoint: 0,
      outPoint: 10,
    );

    await engine.export(
      clips: [videoClip()],
      outputPath: '${tmp.path}/out.mp4',
      audioClips: [audioClip],
    );

    final args = capturedArgs();
    expect(args, contains('/music/track.mp3'));

    final filter = capturedFilter();
    expect(filter, contains('adelay=2500:all=1'));
    expect(filter, contains('amix=inputs=2'));
    // The mix result, not the raw joined pad, should be what's mapped out.
    expect(filter, contains('[outmix]'));
  });

  test('audioClips volume/fade are threaded into the mix chain', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    final audioClip = AudioClip(
      sourcePath: '/music/track.mp3',
      sourceDuration: 30,
      volume: 0.5,
      fadeIn: 1.0,
      fadeOut: 2.0,
    );

    await engine.export(
      clips: [videoClip()],
      outputPath: '${tmp.path}/out.mp4',
      audioClips: [audioClip],
    );

    final filter = capturedFilter();
    expect(filter, contains('volume=0.500'));
    expect(filter, contains('afade=t=in:st=0:d=1.000'));
    expect(filter, contains('afade=t=out:'));
  });

  test('multiple audioClips each get their own input and mix label',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [videoClip()],
      outputPath: '${tmp.path}/out.mp4',
      audioClips: [
        AudioClip(sourcePath: '/a.mp3', sourceDuration: 10),
        AudioClip(sourcePath: '/b.mp3', sourceDuration: 10, start: 3),
      ],
    );

    final args = capturedArgs();
    expect(args, contains('/a.mp3'));
    expect(args, contains('/b.mp3'));

    final filter = capturedFilter();
    expect(filter, contains('amix=inputs=3'));
  });

  test('an audio clip longer than the video extends the timeline: video is '
      'padded with black (tpad) and the output is bounded to the audio end',
      () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    // 5s video, a 30s song on the audio lane → the project is 30s long.
    await engine.export(
      clips: [videoClip()],
      outputPath: '${tmp.path}/out.mp4',
      audioClips: [
        AudioClip(
            sourcePath: '/music/track.mp3',
            sourceDuration: 30,
            inPoint: 0,
            outPoint: 30),
      ],
    );

    final filter = capturedFilter();
    // Video padded with 25s (30 - 5) of black so the song isn't cut off.
    expect(filter, contains('tpad=stop_duration=25.000000'));
    // Mix runs to the longest input, not the (short) main clip audio.
    expect(filter, contains('amix=inputs=2:duration=longest'));

    // The output `-t` bound is the full 30s timeline, not the 5s video.
    final args = capturedArgs();
    final tIndex = args.lastIndexOf('-t');
    expect(tIndex, greaterThanOrEqualTo(0));
    expect(args[tIndex + 1], '30.000');
  });

  test('a video longer than the audio is NOT padded (no tpad)', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.export(
      clips: [videoClip()], // 5s
      outputPath: '${tmp.path}/out.mp4',
      audioClips: [AudioClip(sourcePath: '/a.mp3', sourceDuration: 2)], // 2s
    );
    final filter = capturedFilter();
    expect(filter, isNot(contains('tpad')));
  });

  test('renderPreview also mixes in audioClips', () async {
    final engine = FfmpegEngine(ffmpegPath: fakeFfmpeg, ffprobePath: fakeFfmpeg);
    await engine.renderPreview(
      clips: [videoClip()],
      audioClips: [AudioClip(sourcePath: '/a.mp3', sourceDuration: 10)],
    );

    final filter = capturedFilter();
    expect(filter, contains('amix=inputs=2'));
  });
}
