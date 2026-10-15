import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/speech/whisper_service.dart';

/// Pure parsing tests — no whisper.cpp binary required. [parseSrt] is the
/// boundary between "what whisper.cpp printed" and our Caption model, so it
/// is the piece worth unit testing without a real transcription run.
void main() {
  test('parseSrt reads a standard whisper.cpp .srt output', () {
    const srt = '''
1
00:00:00,000 --> 00:00:02,500
Hello and welcome.

2
00:00:02,500 --> 00:00:05,120
This is a test of auto captions.
''';

    final captions = parseSrt(srt);

    expect(captions.length, 2);
    expect(captions[0].start, 0);
    expect(captions[0].end, 2.5);
    expect(captions[0].text, 'Hello and welcome.');
    expect(captions[1].start, 2.5);
    expect(captions[1].end, closeTo(5.12, 0.001));
    expect(captions[1].text, 'This is a test of auto captions.');
  });

  test('parseSrt joins multi-line caption text with a space', () {
    const srt = '''
1
00:00:00,000 --> 00:00:03,000
Line one
line two
''';

    final captions = parseSrt(srt);

    expect(captions, hasLength(1));
    expect(captions.first.text, 'Line one line two');
  });

  test('parseSrt tolerates dot-separated milliseconds and CRLF newlines', () {
    final srt = [
      '1',
      '00:00:00.000 --> 00:00:01.000',
      'Dotted millis',
      '',
    ].join('\r\n');

    final captions = parseSrt(srt);

    expect(captions, hasLength(1));
    expect(captions.first.text, 'Dotted millis');
  });

  test('parseSrt skips blocks with no text and returns empty for blank input',
      () {
    expect(parseSrt(''), isEmpty);
    expect(
        parseSrt('1\n00:00:00,000 --> 00:00:01,000\n\n'),
        isEmpty);
  });

  test('WhisperException.toString returns the message', () {
    final e = WhisperException('binary not found');
    expect(e.toString(), 'binary not found');
  });
}
