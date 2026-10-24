import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/media_type.dart';

/// Covers [mediaTypeForPath]'s extension -> [MediaType] classification, used
/// by both the Import button and drag-and-drop to route a file to the right
/// place (main track vs. audio lane).
void main() {
  group('mediaTypeForPath', () {
    test('classifies every video extension as video', () {
      for (final ext in kVideoExtensions) {
        expect(mediaTypeForPath('/a/file.$ext'), MediaType.video,
            reason: '.$ext should be video');
      }
    });

    test('classifies every image extension as image', () {
      for (final ext in kImageExtensions) {
        expect(mediaTypeForPath('/a/file.$ext'), MediaType.image,
            reason: '.$ext should be image');
      }
    });

    test('classifies every audio extension as audio', () {
      for (final ext in kAudioExtensions) {
        expect(mediaTypeForPath('/a/file.$ext'), MediaType.audio,
            reason: '.$ext should be audio');
      }
    });

    test('is case-insensitive', () {
      expect(mediaTypeForPath('/a/PHOTO.JPG'), MediaType.image);
      expect(mediaTypeForPath('/a/SONG.MP3'), MediaType.audio);
      expect(mediaTypeForPath('/a/CLIP.MOV'), MediaType.video);
    });

    test('falls back to video for an unknown or missing extension', () {
      expect(mediaTypeForPath('/a/file.xyz'), MediaType.video);
      expect(mediaTypeForPath('/a/file'), MediaType.video);
      expect(mediaTypeForPath('/a/file.'), MediaType.video);
    });

    test('handles Windows-style backslash paths', () {
      expect(mediaTypeForPath(r'C:\Users\me\photo.png'), MediaType.image);
    });
  });

  test('kImportableExtensions covers every video/image/audio extension once',
      () {
    expect(
      kImportableExtensions.toSet(),
      {...kVideoExtensions, ...kImageExtensions, ...kAudioExtensions},
    );
    expect(kImportableExtensions.length,
        kVideoExtensions.length + kImageExtensions.length + kAudioExtensions.length);
  });

  test('MediaType.fromJson round-trips and defaults unknown values to video',
      () {
    for (final type in MediaType.values) {
      expect(MediaType.fromJson(type.toJson()), type);
    }
    expect(MediaType.fromJson(null), MediaType.video);
    expect(MediaType.fromJson('bogus'), MediaType.video);
  });
}
