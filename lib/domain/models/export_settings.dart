/// The video codec written to the output file.
enum ExportCodec {
  h264('H.264', 'libx264'),
  hevc('HEVC', 'libx265');

  const ExportCodec(this.label, this.ffmpegName);

  /// UI label.
  final String label;

  /// The ffmpeg `-c:v` encoder name.
  final String ffmpegName;
}

/// A perceptual quality target, translated to a codec-appropriate CRF.
enum ExportQuality {
  low('Low'),
  recommended('Recommended'),
  high('High');

  const ExportQuality(this.label);

  final String label;
}

/// The output container.
enum ExportFormat {
  mp4('MP4', 'mp4'),
  mov('MOV', 'mov');

  const ExportFormat(this.label, this.extension);

  final String label;

  /// File extension (no dot) ffmpeg should use for the output container.
  final String extension;
}

/// The settings the export dialog collects and [Engine.export] consumes.
///
/// [width]/[height]/[fps] are all nullable: `null` means "keep the source's
/// own value" (no `scale` filter, no `-r` flag) — i.e. today's behaviour.
/// The defaults for every field reproduce the export pipeline exactly as it
/// was before this type existed: no scaling, no frame-rate change, H.264,
/// CRF 18, MP4.
class ExportSettings {
  const ExportSettings({
    this.width,
    this.height,
    this.fps,
    this.codec = ExportCodec.h264,
    this.quality = ExportQuality.recommended,
    this.format = ExportFormat.mp4,
  });

  final int? width;
  final int? height;
  final double? fps;
  final ExportCodec codec;
  final ExportQuality quality;
  final ExportFormat format;

  /// The ffmpeg `-c:v` encoder name for [codec].
  String get videoCodecName => codec.ffmpegName;

  /// The file extension (no dot) matching [format].
  String get fileExtension => format.extension;

  /// CRF (constant rate factor) for [quality], tuned per [codec] — HEVC needs
  /// a numerically higher CRF than H.264 for comparable perceptual quality.
  /// `recommended` + `h264` is 18, matching the value this app always used
  /// before quality became configurable.
  int get crf {
    switch (codec) {
      case ExportCodec.h264:
        switch (quality) {
          case ExportQuality.low:
            return 28;
          case ExportQuality.recommended:
            return 18;
          case ExportQuality.high:
            return 12;
        }
      case ExportCodec.hevc:
        switch (quality) {
          case ExportQuality.low:
            return 31;
          case ExportQuality.recommended:
            return 21;
          case ExportQuality.high:
            return 15;
        }
    }
  }

  /// An ffmpeg filtergraph fragment (e.g. `scale=1920:-2`) that resizes a
  /// video stream to this setting's resolution, or `null` when both
  /// dimensions are unset and the source resolution should be kept as-is.
  /// A `-2` dimension tells ffmpeg to derive it while keeping it even (a
  /// requirement of most video codecs).
  String? get scaleFilter {
    if (width == null && height == null) return null;
    final w = width?.toString() ?? '-2';
    final h = height?.toString() ?? '-2';
    return 'scale=$w:$h';
  }

  /// The ffmpeg output arguments controlling the video/audio codecs, quality
  /// and (optionally) frame rate. Does not include I/O, filtergraph or
  /// progress-reporting flags — those stay the caller's responsibility.
  List<String> toFfmpegArgs() => [
        '-c:v', videoCodecName,
        '-preset', 'medium',
        '-crf', '$crf',
        if (fps != null) ...['-r', _trimFps(fps!)],
        '-c:a', 'aac',
      ];

  static String _trimFps(double f) =>
      f == f.roundToDouble() ? f.toStringAsFixed(0) : f.toStringAsFixed(2);
}
