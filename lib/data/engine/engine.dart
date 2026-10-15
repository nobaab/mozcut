import '../../domain/models/clip.dart';
import '../../domain/models/export_settings.dart';
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

  /// Trims each clip to its in/out region, joins them in order, applies
  /// [settings] (resolution / frame-rate / codec / quality / format), burns in
  /// any [textOverlays] (timed on the final timeline), and writes the result to
  /// [outputPath]. Reports 0..1 progress via [onProgress]. Defaults reproduce
  /// the export pipeline's original, fixed behaviour.
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    ExportSettings settings = const ExportSettings(),
    List<TextOverlay> textOverlays = const [],
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
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => 'EngineException: $message';
}
