import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/clip.dart';

part 'upscale_service.g.dart';

/// Local, on-device AI video upscaling via
/// [Real-ESRGAN (ncnn-vulkan)](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan).
///
/// No network calls and no API keys — frames are extracted from the clip with
/// `ffmpeg`, upscaled frame-by-frame with the `realesrgan-ncnn-vulkan` binary
/// (processed in chunks so disk usage stays bounded on long clips), then
/// re-encoded and muxed back with the original audio. The binary and its
/// bundled model files are expected to already be installed (see
/// [UpscaleException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without Real-ESRGAN.
@Riverpod(keepAlive: true)
UpscaleService upscaleService(Ref ref) => UpscaleService();

/// Message an [UpscaleException] carries when [upscale] was stopped via a
/// [UpscaleCancelToken] rather than failing outright — callers can compare
/// against this to tell "the user cancelled" apart from a real error.
const upscaleCancelledMessage = 'Upscale cancelled.';

class UpscaleService {
  UpscaleService({
    String? ffmpegPath,
    String? ffprobePath,
    String? binaryPath,
    String? modelsDirPath,
  })  : _ffmpeg = ffmpegPath ?? _resolveTool('ffmpeg'),
        _ffprobe = ffprobePath ?? _resolveTool('ffprobe'),
        _binaryOverride = binaryPath,
        _modelsDirOverride = modelsDirPath;

  final String _ffmpeg;
  final String _ffprobe;
  final String? _binaryOverride;
  final String? _modelsDirOverride;

  static const defaultModel = 'realesr-animevideov3';
  static const defaultScale = 4;

  /// Frames per realesrgan-ncnn-vulkan batch. Bounds how many source + output
  /// PNGs ever sit on disk at once — each chunk's frames are deleted as soon
  /// as it has been encoded into a segment (see [upscale]).
  static const _chunkSize = 150;

  static const _toolDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];

  static const _modelDirCandidates = [
    '/opt/homebrew/share/realesrgan-ncnn-vulkan/models',
    '/usr/local/share/realesrgan-ncnn-vulkan/models',
    '/usr/local/share/realesrgan/models',
  ];

  /// Returns the deterministic cache file path for upscaling [clip]'s
  /// trimmed region at [targetWidth]x[targetHeight]/[scale]/[model], under
  /// `getApplicationSupportDirectory()`. If a file already exists at this
  /// path, [upscale] returns it instantly without doing any work — this *is*
  /// the cache: same inputs always resolve to the same path.
  Future<String> cacheFilePath(
    Clip clip, {
    required int targetWidth,
    required int targetHeight,
    int scale = defaultScale,
    String model = defaultModel,
  }) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/mozcut-upscale-cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final key = computeUpscaleCacheKey(
      sourcePath: clip.sourcePath,
      inPoint: clip.inPoint,
      outPoint: clip.outPoint,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      scale: scale,
      model: model,
    );
    return '${dir.path}/upscale_$key.mp4';
  }

  /// Upscales [clip]'s trimmed region (`clip.inPoint`..`clip.outPoint`) to
  /// roughly [targetWidth]x[targetHeight] and writes the result to
  /// [outputPath] (typically [cacheFilePath]'s result — if a file already
  /// exists there, this returns instantly instead of redoing the work).
  ///
  /// Pipeline: extract audio, extract base-resolution frames (downscaled with
  /// lanczos to `target/scale` so Real-ESRGAN's own [scale]x upscale lands
  /// back on the target), upscale frames in bounded-size chunks (each chunk's
  /// frames are deleted once encoded, so a long clip never needs its full
  /// frame set on disk at once), encode each chunk to its own segment, concat
  /// the segments, then mux the original audio back in.
  ///
  /// Deliberately does *not* force `-x264opts scenecut=0` on any encode: that
  /// would give every segment a uniform GOP structure, which sounds tempting
  /// for clean concatenation, but it disables adaptive keyframe placement at
  /// real scene cuts and causes visible stutter there. Chunk boundaries don't
  /// need it — each segment is its own encode and always starts on a
  /// keyframe, so stream-copy concatenation is already clean.
  ///
  /// Reports progress (0..1, across all chunks) via [onProgress] and
  /// human-readable stage text via [onStatus]. If [cancel] is cancelled while
  /// this is running, the in-flight process is killed and this throws an
  /// [UpscaleException] with [upscaleCancelledMessage].
  ///
  /// Throws [UpscaleException] with a friendly, actionable message if the
  /// Real-ESRGAN binary or its model files cannot be found, or if any stage
  /// of the pipeline fails.
  Future<String> upscale({
    required Clip clip,
    required String outputPath,
    required int targetWidth,
    required int targetHeight,
    int scale = defaultScale,
    String model = defaultModel,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    UpscaleCancelToken? cancel,
  }) async {
    if (File(outputPath).existsSync()) {
      onStatus?.call('Using cached result…');
      onProgress?.call(1);
      return outputPath;
    }

    final binary = _binaryOverride ?? _resolveBinary();
    if (binary == null) {
      throw UpscaleException(
        'No Real-ESRGAN binary found. Download a release for your platform '
        'from:\n'
        '  https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases\n'
        'then put "realesrgan-ncnn-vulkan" (and the "models" folder that '
        'ships next to it) on your PATH, or in /usr/local/bin.',
      );
    }

    final modelsDir = _modelsDirOverride ?? _resolveModelsDir(binary);
    final modelName = resolveModelName(model, scale);
    if (modelsDir == null || !_modelFilesExist(modelsDir, modelName)) {
      throw UpscaleException(
        'Real-ESRGAN is installed but the "$modelName" model files were not '
        'found. Make sure the "models" folder that ships with the release '
        'zip sits next to the binary, or set the REALESRGAN_MODELS_DIR '
        'environment variable to point at it.',
      );
    }

    _throwIfCancelled(cancel);
    final tempDir = await Directory.systemTemp.createTemp('mozcut_upscale_');
    try {
      final start = clip.inPoint;
      final end = clip.outPoint;

      onStatus?.call('Reading source…');
      final fps = await _probeFrameRate(clip.sourcePath);
      final hasAudio = await _probeHasAudio(clip.sourcePath);

      String? audioPath;
      if (hasAudio) {
        onStatus?.call('Extracting audio…');
        final candidate = '${tempDir.path}/audio.m4a';
        final extractAudio = await _run(
          _ffmpeg,
          [
            '-y',
            '-ss', start.toStringAsFixed(3),
            '-to', end.toStringAsFixed(3),
            '-i', clip.sourcePath,
            '-vn',
            '-c:a', 'aac',
            candidate,
          ],
          cancel: cancel,
        );
        // Best-effort: a clip with an unusual/unextractable audio stream
        // still gets upscaled, just silently.
        if (extractAudio.exitCode == 0 && File(candidate).existsSync()) {
          audioPath = candidate;
        }
      }

      _throwIfCancelled(cancel);
      onStatus?.call('Extracting frames…');
      final framesDir = Directory('${tempDir.path}/frames')
        ..createSync(recursive: true);
      final base = baseFrameDimensions(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        scale: scale,
      );
      final extractFrames = await _run(
        _ffmpeg,
        [
          '-y',
          '-ss', start.toStringAsFixed(3),
          '-to', end.toStringAsFixed(3),
          '-i', clip.sourcePath,
          '-vf', 'scale=${base.$1}:${base.$2}:flags=lanczos',
          '-vsync', '0',
          '-start_number', '1',
          '${framesDir.path}/frame_%08d.png',
        ],
        cancel: cancel,
      );
      if (extractFrames.exitCode != 0) {
        throw UpscaleException(
            'Could not extract frames from the clip: ${extractFrames.stderr}');
      }

      final frames = framesDir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .toList(growable: false)
        ..sort();
      if (frames.isEmpty) {
        throw UpscaleException('No frames could be extracted from this clip.');
      }

      _throwIfCancelled(cancel);
      final chunks = chunkFrames(frames, _chunkSize);
      final segments = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        _throwIfCancelled(cancel);
        onStatus?.call('Upscaling frames (${i + 1}/${chunks.length})…');

        final chunkIn = Directory('${tempDir.path}/chunk_in')
          ..createSync(recursive: true);
        final chunkOut = Directory('${tempDir.path}/chunk_out')
          ..createSync(recursive: true);
        for (final framePath in chunks[i]) {
          File(framePath)
              .renameSync('${chunkIn.path}/${_basename(framePath)}');
        }

        final run = await _run(
          binary,
          [
            '-i', chunkIn.path,
            '-o', chunkOut.path,
            '-n', modelName,
            '-s', '$scale',
            '-m', modelsDir,
          ],
          cancel: cancel,
        );
        if (run.exitCode != 0) {
          throw UpscaleException(
              'realesrgan-ncnn-vulkan failed:\n${run.stderr}');
        }

        _throwIfCancelled(cancel);
        final firstNumber = frameNumberFromPath(chunks[i].first);
        final segmentPath =
            '${tempDir.path}/segment_${i.toString().padLeft(4, '0')}.mp4';
        final encode = await _run(
          _ffmpeg,
          [
            '-y',
            '-start_number', '$firstNumber',
            '-framerate', fps.toStringAsFixed(6),
            '-i', '${chunkOut.path}/frame_%08d.png',
            '-frames:v', '${chunks[i].length}',
            '-c:v', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-preset', 'medium',
            '-crf', '18',
            segmentPath,
          ],
          cancel: cancel,
        );
        if (encode.exitCode != 0) {
          throw UpscaleException(
              'Could not encode an upscaled segment: ${encode.stderr}');
        }
        segments.add(segmentPath);

        // Disk safety: this chunk's raw + upscaled frames are no longer
        // needed once its segment is encoded.
        await chunkIn.delete(recursive: true);
        await chunkOut.delete(recursive: true);

        onProgress?.call((i + 1) / chunks.length);
      }

      _throwIfCancelled(cancel);
      onStatus?.call('Combining segments…');
      final listFile = File('${tempDir.path}/segments.txt');
      await listFile.writeAsString(segments
          .map((s) => "file '${s.replaceAll("'", r"'\''")}'")
          .join('\n'));
      final videoOnly = '${tempDir.path}/video_only.mp4';
      final concat = await _run(
        _ffmpeg,
        [
          '-y',
          '-f', 'concat',
          '-safe', '0',
          '-i', listFile.path,
          '-c', 'copy',
          videoOnly,
        ],
        cancel: cancel,
      );
      if (concat.exitCode != 0) {
        throw UpscaleException(
            'Could not combine upscaled segments: ${concat.stderr}');
      }

      _throwIfCancelled(cancel);
      onStatus?.call('Finalizing…');
      await File(outputPath).parent.create(recursive: true);
      final muxArgs = audioPath != null
          ? [
              '-y',
              '-i', videoOnly,
              '-i', audioPath,
              '-c:v', 'copy',
              '-c:a', 'copy',
              '-shortest',
              outputPath,
            ]
          : ['-y', '-i', videoOnly, '-c', 'copy', outputPath];
      final mux = await _run(_ffmpeg, muxArgs, cancel: cancel);
      if (mux.exitCode != 0) {
        throw UpscaleException(
            'Could not finalize the upscaled video: ${mux.stderr}');
      }

      onProgress?.call(1);
      return outputPath;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; a leftover temp dir is not worth failing over.
      }
    }
  }

  // ── process plumbing ──

  Future<_ProcResult> _run(
    String executable,
    List<String> args, {
    UpscaleCancelToken? cancel,
  }) async {
    _throwIfCancelled(cancel);
    final process = await Process.start(executable, args);
    cancel?._attach(process);
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen(stdoutBuf.write);
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(stderrBuf.write);
    final code = await process.exitCode;
    cancel?._detach();
    _throwIfCancelled(cancel);
    return _ProcResult(code, stdoutBuf.toString(), stderrBuf.toString());
  }

  void _throwIfCancelled(UpscaleCancelToken? cancel) {
    if (cancel != null && cancel.isCancelled) {
      throw UpscaleException(upscaleCancelledMessage);
    }
  }

  // ── probing ──

  Future<double> _probeFrameRate(String path) async {
    final result = await Process.run(_ffprobe, [
      '-v', 'error',
      '-select_streams', 'v:0',
      '-show_entries', 'stream=r_frame_rate',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    return parseFrameRate(result.stdout.toString());
  }

  Future<bool> _probeHasAudio(String path) async {
    try {
      final result = await Process.run(_ffprobe, [
        '-v', 'error',
        '-select_streams', 'a',
        '-show_entries', 'stream=index',
        '-of', 'csv=p=0',
        path,
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── binary / model resolution ──

  static String? _resolveBinary() {
    final name = Platform.isWindows
        ? 'realesrgan-ncnn-vulkan.exe'
        : 'realesrgan-ncnn-vulkan';
    for (final dir in _toolDirs) {
      final path = '$dir/$name';
      if (File(path).existsSync()) return path;
    }
    return _which(name);
  }

  /// Resolves the directory containing Real-ESRGAN's `.param`/`.bin` model
  /// files: the `REALESRGAN_MODELS_DIR` environment variable, then a
  /// `models` folder next to [binaryPath] (how the official release zip
  /// ships), then a handful of common install locations.
  static String? _resolveModelsDir(String binaryPath) {
    final envDir = Platform.environment['REALESRGAN_MODELS_DIR'];
    if (envDir != null && Directory(envDir).existsSync()) return envDir;

    final binaryDir = File(binaryPath).parent.path;
    final nextToBinary = '$binaryDir/models';
    if (Directory(nextToBinary).existsSync()) return nextToBinary;

    for (final dir in _modelDirCandidates) {
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  static bool _modelFilesExist(String modelsDir, String modelName) =>
      File('$modelsDir/$modelName.param').existsSync() &&
      File('$modelsDir/$modelName.bin').existsSync();

  static String? _which(String name) {
    try {
      final result =
          Process.runSync(Platform.isWindows ? 'where' : 'which', [name]);
      if (result.exitCode == 0) {
        final path =
            result.stdout.toString().trim().split('\n').first.trim();
        if (path.isNotEmpty && File(path).existsSync()) return path;
      }
    } catch (_) {
      // `which`/`where` missing or unavailable — treat as "not found".
    }
    return null;
  }

  static String _resolveTool(String tool) {
    final exe = Platform.isWindows ? '$tool.exe' : tool;
    for (final dir in _toolDirs) {
      final path = '$dir/$exe';
      if (File(path).existsSync()) return path;
    }
    return exe;
  }

  static String _basename(String path) =>
      path.split(RegExp(r'[/\\]')).last;
}

/// A handle that lets the caller cancel an in-flight [UpscaleService.upscale]
/// run: it kills whatever external process is currently running and causes
/// the pipeline to throw [UpscaleException] with [upscaleCancelledMessage] at
/// its next checkpoint.
class UpscaleCancelToken {
  Process? _process;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void _attach(Process process) {
    _process = process;
    // A cancel() that races ahead of the process actually starting still
    // needs to kill it once it exists.
    if (_cancelled) process.kill();
  }

  void _detach() => _process = null;

  /// Stops the run as soon as possible: kills the current external process
  /// (if any) and marks this token cancelled so the next checkpoint throws.
  void cancel() {
    _cancelled = true;
    _process?.kill();
  }
}

class UpscaleException implements Exception {
  UpscaleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ProcResult {
  const _ProcResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

// ── pure helpers (unit-testable without any binary installed) ──

/// The base resolution to extract frames at before Real-ESRGAN's [scale]x
/// upscale, so the upscaled output lands back on roughly
/// [targetWidth]x[targetHeight]. Rounded down to even numbers (ffmpeg's
/// yuv420p pixel format requires even dimensions), and floored at 2 so a
/// pathological target/scale combination never produces a zero-size frame.
(int, int) baseFrameDimensions({
  required int targetWidth,
  required int targetHeight,
  required int scale,
}) {
  int evenFloor(num value) {
    final i = value.floor();
    final even = i.isEven ? i : i - 1;
    return even < 2 ? 2 : even;
  }

  return (
    evenFloor(targetWidth / scale),
    evenFloor(targetHeight / scale),
  );
}

/// Splits [frames] into consecutive batches of at most [chunkSize] — the unit
/// Real-ESRGAN processes (and that gets deleted once encoded) per iteration
/// of [UpscaleService.upscale]'s chunk loop. A non-positive [chunkSize] is
/// treated as "one chunk holding everything".
List<List<String>> chunkFrames(List<String> frames, int chunkSize) {
  if (chunkSize <= 0) return [frames];
  final chunks = <List<String>>[];
  for (var i = 0; i < frames.length; i += chunkSize) {
    chunks.add(frames.sublist(i, (i + chunkSize).clamp(0, frames.length)));
  }
  return chunks;
}

/// Parses ffprobe's `r_frame_rate` output (e.g. `"30000/1001"` or `"30/1"`,
/// sometimes a bare number) into a double fps value. Falls back to 30fps for
/// unparseable input rather than throwing — frame rate drives cosmetic
/// encode settings, not correctness, so a bad probe shouldn't abort the
/// whole upscale.
double parseFrameRate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.contains('/')) {
    final parts = trimmed.split('/');
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator != null && denominator != null && denominator != 0) {
        return numerator / denominator;
      }
    }
  }
  final direct = double.tryParse(trimmed);
  if (direct != null && direct > 0) return direct;
  return 30.0;
}

/// Extracts the numbered sequence index from an extracted frame's filename
/// (e.g. `frame_00000042.png` -> `42`), used as ffmpeg's `-start_number` when
/// re-encoding a chunk whose frame numbers don't start at 1. Returns 1 if no
/// digits are found, matching the sequence's own starting point.
int frameNumberFromPath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final match = RegExp(r'(\d+)').firstMatch(name);
  return match != null ? int.parse(match.group(1)!) : 1;
}

/// Resolves the on-disk model name for [model]/[scale]: Real-ESRGAN ships
/// the `realesr-animevideov3` model as separate per-scale files
/// (`realesr-animevideov3-x2`, `-x3`, `-x4`), so that one gets the scale
/// suffix appended; any other (already fully-named, e.g.
/// `realesrgan-x4plus`) model name is passed through unchanged.
String resolveModelName(String model, int scale) {
  if (RegExp(r'-x\d+$').hasMatch(model)) return model;
  if (model == UpscaleService.defaultModel) return '$model-x$scale';
  return model;
}

/// A stable (not [Object.hashCode]-based — that's randomized per isolate in
/// Dart, so it would make the cache miss on every process restart) FNV-1a
/// hash of the upscale parameters, used to name [UpscaleService.cacheFilePath]
/// deterministically. Same algorithm as `FfmpegEngine._cacheKey`.
String computeUpscaleCacheKey({
  required String sourcePath,
  required double inPoint,
  required double outPoint,
  required int targetWidth,
  required int targetHeight,
  required int scale,
  required String model,
}) {
  final parts = [
    sourcePath,
    inPoint.toStringAsFixed(3),
    outPoint.toStringAsFixed(3),
    targetWidth,
    targetHeight,
    scale,
    model,
  ].join('|');

  const fnvPrime = 0x100000001b3;
  var hash = 0xcbf29ce484222325;
  for (final unit in parts.codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFFFFFFFFFF;
    hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
