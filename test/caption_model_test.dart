import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/domain/models/caption.dart';
import 'package:vidkaat/domain/models/clip.dart';

void main() {
  test('Caption survives a JSON round-trip', () {
    const caption =
        Caption(start: 1.25, end: 3.5, text: 'Hello, world!');

    final restored = Caption.fromJson(caption.toJson());

    expect(restored.start, 1.25);
    expect(restored.end, 3.5);
    expect(restored.text, 'Hello, world!');
    expect(restored, caption);
  });

  test('Caption.copyWith only overrides given fields', () {
    const caption = Caption(start: 0, end: 2, text: 'Hi');
    final edited = caption.copyWith(text: 'Hi there');

    expect(edited.start, 0);
    expect(edited.end, 2);
    expect(edited.text, 'Hi there');
  });

  test('Caption.duration is end minus start, never negative', () {
    expect(const Caption(start: 1, end: 4, text: 'a').duration, 3);
    expect(const Caption(start: 4, end: 1, text: 'a').duration, 0);
  });

  test('formatSrtTimestamp formats hh:mm:ss,mmm', () {
    expect(formatSrtTimestamp(0), '00:00:00,000');
    expect(formatSrtTimestamp(1.5), '00:00:01,500');
    expect(formatSrtTimestamp(3661.025), '01:01:01,025');
  });

  test('Clip persists its captions through a JSON round-trip', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      captions: const [
        Caption(start: 0, end: 1.5, text: 'Hi'),
        Caption(start: 1.5, end: 3, text: 'there'),
      ],
    );

    final restored = Clip.fromJson(clip.toJson());

    expect(restored.captions.length, 2);
    expect(restored.captions[0].text, 'Hi');
    expect(restored.captions[1].start, 1.5);
  });

  test('Clip defaults to no captions when the key is absent (old manifests)', () {
    final clip = Clip.fromJson({
      'id': 'x',
      'sourcePath': '/v/a.mp4',
      'sourceDuration': 10.0,
    });
    expect(clip.captions, isEmpty);
  });
}
