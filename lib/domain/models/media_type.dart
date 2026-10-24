/// What kind of source file a [Clip] (or an import) wraps. Drives both the
/// timeline's rendering (filmstrip+waveform for video, a still frame for an
/// image) and the engine's input args (a normal trimmed `-i` for video, a
/// looped `-loop 1 -t <duration> -i` for an image — see
/// `FfmpegEngine._buildFilterGraph`).
///
/// Audio files never become a [Clip] / [MediaType.audio] clip on the main
/// track — they become an [AudioClip] on the project's audio lane instead
/// (see `lib/domain/models/audio_clip.dart`). This enum still lists `audio`
/// so [mediaTypeForPath] has a way to say "this file is audio" to callers
/// that need to route an import to the right place (e.g. the media browser's
/// Import button / drag-and-drop).
enum MediaType {
  video,
  image,
  audio;

  String toJson() => name;

  /// Defaults to [video] for a missing/unrecognized value — every clip saved
  /// before this feature existed reproduces exactly the pre-feature,
  /// video-only behaviour.
  static MediaType fromJson(String? value) => MediaType.values
      .firstWhere((m) => m.name == value, orElse: () => MediaType.video);
}

/// Video container extensions accepted by Import / drag-and-drop (no dot,
/// lower-case).
const kVideoExtensions = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'];

/// Still-image extensions accepted by Import / drag-and-drop.
const kImageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'];

/// Audio extensions accepted by Import / drag-and-drop.
const kAudioExtensions = ['mp3', 'wav', 'aac', 'flac', 'm4a', 'ogg'];

/// Every extension Import / drag-and-drop will accept, across all three
/// media types — used as `FilePicker`'s `allowedExtensions`.
const kImportableExtensions = [
  ...kVideoExtensions,
  ...kImageExtensions,
  ...kAudioExtensions,
];

/// Classifies [path] by its file extension. Unknown/missing extensions fall
/// back to [MediaType.video] — the pre-feature behaviour, since every file
/// this app could import used to be a video.
MediaType mediaTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return MediaType.video;
  final ext = path.substring(dot + 1).toLowerCase();
  if (kImageExtensions.contains(ext)) return MediaType.image;
  if (kAudioExtensions.contains(ext)) return MediaType.audio;
  return MediaType.video;
}
