import '../../domain/models/audio_clip.dart';
import '../../domain/models/clip.dart';
import '../../domain/models/export_settings.dart';
import '../../domain/models/sticker_overlay.dart';
import '../../domain/models/text_overlay.dart';

/// The boundary between the UI and the heavy video work.
///
/// Everything above this line is Flutter. Everything below is "the engine".
/// Today the only implementation is [FfmpegEngine], which shells out to the
/// `ffmpeg` binary. The day real-time GPU effects are needed, a Rust engine
/// (via FFI / flutter_rust_bridge) can implement this same interface and the
/// UI will not change one line. Keep this interface small and media-only.
abstract class Engine {
  /// Reads a media file's duration (seconds) and basic validity.
  /// Throws [EngineException] if the file cannot be read as media.
  Future<double> probeDuration(String path);

  /// Reads a media file's pixel dimensions (width, height) from its first
  /// video stream. Used by the Ratio control's "Original" option to match
  /// the first clip's aspect. Throws [EngineException] if they cannot be
  /// determined.
  Future<(int width, int height)> probeDimensions(String path);

  /// Trims each clip to its in/out region, joins them in order, applies
  /// [settings] (resolution / frame-rate / codec / quality / format), burns in
  /// any [textOverlays] and [stickerOverlays] (both timed on the final
  /// timeline), mixes in [audioClips] (the project's audio lane, also timed
  /// on the final timeline — see [AudioClip.start]), and writes the result to
  /// [outputPath]. Reports 0..1 progress via [onProgress]. [canvasWidth]/
  /// [canvasHeight] set the working canvas every clip's transform is
  /// composited against (the project's aspect ratio) — defaults to
  /// 1920x1080, reproducing the export pipeline's original, fixed behaviour.
  /// An empty [audioClips] (the default) reproduces the exact output from
  /// before this feature existed — the main audio pad is untouched.
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double progress)? onProgress,
  });

  /// Renders a small/fast proxy of the *whole timeline* — the same edit
  /// [export] would produce (per-clip transform/speed/audio, concatenated in
  /// order, captions, [textOverlays], [stickerOverlays] and [audioClips]
  /// mixed in) but at low resolution and encoder effort, so it renders in a
  /// fraction of the time. Used to drive a WYSIWYG player preview instead of
  /// showing just one clip's raw source. [canvasWidth]/[canvasHeight] set the
  /// working canvas (the project's aspect ratio), same meaning as in [export]
  /// and defaulting the same way. Returns the path to the rendered temp MP4.
  /// Reports 0..1 progress via [onProgress]. Throws [EngineException] if
  /// [clips] is empty or ffmpeg fails.
  Future<String> renderPreview({
    required List<Clip> clips,
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<AudioClip> audioClips = const [],
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    void Function(double progress)? onProgress,
  });

  /// Writes a single JPEG frame from [clip] (at its in-point) to [outputPath],
  /// scaled to [width]. Used for project poster thumbnails. Best-effort.
  Future<void> savePoster({
    required Clip clip,
    required String outputPath,
    int width = 480,
  });

  /// Extracts [clip]'s trimmed audio (its in/out region) to [outputPath].
  /// The container/codec is inferred from [outputPath]'s extension (e.g.
  /// `.wav` or `.mp3`). Throws [EngineException] if the clip has no audio or
  /// extraction otherwise fails.
  Future<void> extractAudio({
    required Clip clip,
    required String outputPath,
  });

  /// Extracts [count] JPEG frame thumbnails evenly spaced across [clip]'s
  /// trimmed region (inPoint..outPoint), each scaled to [height] tall
  /// (width preserves source aspect). Returns their file paths in timeline
  /// order (left to right). Used to paint the timeline's filmstrip.
  ///
  /// Results are cached on disk keyed by (sourcePath, inPoint, outPoint,
  /// height, count), so calling this again with the same arguments returns
  /// instantly without re-running ffmpeg. Best-effort: returns an empty list
  /// (never throws) if extraction fails, e.g. the source has no video stream.
  Future<List<String>> extractThumbnails({
    required Clip clip,
    required int count,
    int height = 64,
  });

  /// Renders a waveform image of [clip]'s trimmed audio (inPoint..outPoint),
  /// [width]x[height], for the timeline's audio strip. Returns the cached
  /// PNG's file path, or `null` if [clip] has no audio track (or rendering
  /// otherwise fails) — best-effort, never throws.
  ///
  /// Cached on disk keyed by (sourcePath, inPoint, outPoint, width, height).
  Future<String?> waveformPng({
    required Clip clip,
    required int width,
    int height = 40,
  });
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => 'EngineException: $message';
}
