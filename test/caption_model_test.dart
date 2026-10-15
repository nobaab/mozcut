import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/caption.dart';
import 'package:mozcut/domain/models/clip.dart';

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

  test('Clip defaults volume/fadeIn/fadeOut to 1.0/0/0', () {
    final clip = Clip(sourcePath: '/v/a.mp4', sourceDuration: 10);
    expect(clip.volume, 1.0);
    expect(clip.fadeIn, 0);
    expect(clip.fadeOut, 0);
  });

  test('Clip audio fields survive a JSON round-trip', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      volume: 1.5,
      fadeIn: 0.5,
      fadeOut: 1.25,
    );

    final restored = Clip.fromJson(clip.toJson());

    expect(restored.volume, 1.5);
    expect(restored.fadeIn, 0.5);
    expect(restored.fadeOut, 1.25);
  });

  test('Clip defaults audio fields when absent from JSON (old manifests)', () {
    final clip = Clip.fromJson({
      'id': 'x',
      'sourcePath': '/v/a.mp4',
      'sourceDuration': 10.0,
    });
    expect(clip.volume, 1.0);
    expect(clip.fadeIn, 0);
    expect(clip.fadeOut, 0);
  });

  test('Clip.copyWith only overrides the given audio fields', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      volume: 1.2,
      fadeIn: 1,
      fadeOut: 2,
    );
    final edited = clip.copyWith(volume: 0.5);

    expect(edited.volume, 0.5);
    expect(edited.fadeIn, 1);
    expect(edited.fadeOut, 2);
  });

  test('Clip defaults brightness/contrast/saturation/filterId to neutral', () {
    final clip = Clip(sourcePath: '/v/a.mp4', sourceDuration: 10);
    expect(clip.brightness, 0.0);
    expect(clip.contrast, 1.0);
    expect(clip.saturation, 1.0);
    expect(clip.filterId, isNull);
  });

  test('Clip color/filter fields survive a JSON round-trip', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      brightness: 0.2,
      contrast: 1.3,
      saturation: 0.7,
      filterId: 'Noir',
    );

    final restored = Clip.fromJson(clip.toJson());

    expect(restored.brightness, 0.2);
    expect(restored.contrast, 1.3);
    expect(restored.saturation, 0.7);
    expect(restored.filterId, 'Noir');
  });

  test('Clip defaults color/filter fields when absent from JSON '
      '(old manifests)', () {
    final clip = Clip.fromJson({
      'id': 'x',
      'sourcePath': '/v/a.mp4',
      'sourceDuration': 10.0,
    });
    expect(clip.brightness, 0.0);
    expect(clip.contrast, 1.0);
    expect(clip.saturation, 1.0);
    expect(clip.filterId, isNull);
  });

  test('Clip.copyWith only overrides the given color fields', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      brightness: 0.1,
      contrast: 1.1,
      saturation: 1.1,
      filterId: 'Vivid',
    );
    final edited = clip.copyWith(brightness: 0.5);

    expect(edited.brightness, 0.5);
    expect(edited.contrast, 1.1);
    expect(edited.saturation, 1.1);
    expect(edited.filterId, 'Vivid');
  });

  test('Clip.copyWith(clearFilterId: true) clears filterId regardless of '
      'other args', () {
    final clip = Clip(
      sourcePath: '/v/a.mp4',
      sourceDuration: 10,
      filterId: 'Vivid',
    );
    final edited = clip.copyWith(clearFilterId: true);

    expect(edited.filterId, isNull);
  });
}
