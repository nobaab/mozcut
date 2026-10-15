import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/caption.dart';

part 'whisper_service.g.dart';

/// Local, on-device speech-to-text via [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
///
/// No network calls and no API keys — audio is extracted from the clip with
/// `ffmpeg`, then handed to a whisper.cpp binary on disk. The binary and a
/// ggml model file are expected to already be installed (see
/// [WhisperException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without whisper.cpp.
@Riverpod(keepAlive: true)
WhisperService whisperService(Ref ref) => WhisperService();

class WhisperService {
  WhisperService({String? ffmpegPath, String? binaryPath, String? modelPath})
      : _ffmpeg = ffmpegPath ?? _resolveFfmpeg(),
        _binaryOverride = binaryPath,
        _modelOverride = modelPath;

  final String _ffmpeg;
  final String? _binaryOverride;
  final String? _modelOverride;

  /// Binary names whisper.cpp has shipped its CLI under across versions.
  static const _binaryCandidates = [
    'whisper-cli',
    'whisper-cpp',
    'whisper',
    'main',
  ];

  static const _toolDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];

  static const _modelDirs = [
    '/opt/homebrew/share/whisper-cpp',
    '/opt/homebrew/share/whisper.cpp',
    '/usr/local/share/whisper-cpp',
    '/usr/local/share/whisper.cpp',
  ];

  static const _modelNames = [
    'ggml-base.en.bin',
    'ggml-base.bin',
    'ggml-small.en.bin',
    'ggml-small.bin',
    'ggml-tiny.en.bin',
    'ggml-tiny.bin',
    'ggml-medium.en.bin',
    'ggml-medium.bin',
  ];

  /// Transcribes the region [start]..[end] of [sourcePath] (defaults to the
  /// whole file) into timed caption segments. Segment timing is relative to
  /// [start] — a segment's own `start` of 0 means "right at [start]".
  ///
  /// Throws [WhisperException] with a friendly, actionable message if the
  /// whisper.cpp binary or a model file cannot be found, or if either step
  /// of the pipeline (audio extraction, transcription) fails.
  Future<List<Caption>> transcribe(
    String sourcePath, {
    double start = 0,
    double? end,
    void Function(String status)? onStatus,
  }) async {
    final binary = _binaryOverride ?? _resolveBinary();
    if (binary == null) {
      throw WhisperException(
        'No whisper.cpp binary found. Install it with:\n'
        '  brew install whisper-cpp\n'
        '(or build whisper.cpp from source and put it on your PATH).',
      );
    }

    final model = _modelOverride ?? _resolveModel();
    if (model == null) {
      throw WhisperException(
        'whisper.cpp is installed but no model file was found. Download one, '
        'e.g.:\n'
        '  whisper-cpp-download-ggml-model base.en\n'
        'or set the WHISPER_MODEL_PATH environment variable to a ggml '
        '*.bin model file.',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('mozcut_whisper_');
    try {
      onStatus?.call('Extracting audio…');
      final wavPath = '${tempDir.path}/audio.wav';
      final ffmpegArgs = <String>['-y', '-i', sourcePath];
      if (start > 0) ffmpegArgs.addAll(['-ss', start.toStringAsFixed(3)]);
      if (end != null) ffmpegArgs.addAll(['-to', end.toStringAsFixed(3)]);
      ffmpegArgs.addAll([
        '-ar', '16000', // whisper.cpp expects 16kHz
        '-ac', '1',
        '-c:a', 'pcm_s16le',
        wavPath,
      ]);
      final extract = await Process.run(_ffmpeg, ffmpegArgs);
      if (extract.exitCode != 0) {
        throw WhisperException(
            'Could not extract audio from the clip: ${extract.stderr}');
      }

      onStatus?.call('Transcribing…');
      final outPrefix = '${tempDir.path}/out';
      final result = await Process.run(binary, [
        '-m', model,
        '-f', wavPath,
        '-osrt',
        '-of', outPrefix,
        '-nt', // no timestamps printed to stdout; we only want the .srt file
      ]);
      if (result.exitCode != 0) {
        throw WhisperException(
            'whisper.cpp failed:\n${result.stderr}\n${result.stdout}');
      }

      final srtFile = File('$outPrefix.srt');
      if (!srtFile.existsSync()) {
        throw WhisperException(
            'whisper.cpp did not produce any captions for this clip.');
      }
      return parseSrt(await srtFile.readAsString());
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; a leftover temp dir is not worth failing over.
      }
    }
  }

  /// Finds an installed whisper.cpp binary — checked in common Homebrew/
  /// system locations first, then via `which`/`where` on PATH. Returns null
  /// if nothing is found, rather than guessing and failing later.
  static String? _resolveBinary() {
    for (final dir in _toolDirs) {
      for (final name in _binaryCandidates) {
        final path = '$dir/$name';
        if (File(path).existsSync()) return path;
      }
    }
    for (final name in _binaryCandidates) {
      final found = _which(name);
      if (found != null) return found;
    }
    return null;
  }

  static String? _resolveModel() {
    final envPath = Platform.environment['WHISPER_MODEL_PATH'];
    if (envPath != null && File(envPath).existsSync()) return envPath;

    final home = Platform.environment['HOME'];
    final searchDirs = [
      ..._modelDirs,
      if (home != null) '$home/.cache/whisper',
      if (home != null) '$home/.whisper/models',
    ];
    for (final dir in searchDirs) {
      for (final name in _modelNames) {
        final path = '$dir/$name';
        if (File(path).existsSync()) return path;
      }
    }
    return null;
  }

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

  static String _resolveFfmpeg() {
    for (final dir in _toolDirs) {
      final path = '$dir/ffmpeg';
      if (File(path).existsSync()) return path;
    }
    return 'ffmpeg';
  }
}

class WhisperException implements Exception {
  WhisperException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses the contents of a `.srt` file into caption segments. Pure (no
/// process spawning), so this is unit-testable without whisper.cpp installed.
List<Caption> parseSrt(String content) {
  final captions = <Caption>[];
  final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
  final timeRe = RegExp(
    r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})',
  );

  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;

    final timeLineIndex = lines.indexWhere((l) => timeRe.hasMatch(l));
    if (timeLineIndex == -1) continue;

    final match = timeRe.firstMatch(lines[timeLineIndex])!;
    final start = _timeToSeconds(match, 1);
    final end = _timeToSeconds(match, 5);
    final text = lines.sublist(timeLineIndex + 1).join(' ').trim();
    if (text.isEmpty) continue;

    captions.add(Caption(start: start, end: end, text: text));
  }
  return captions;
}

double _timeToSeconds(RegExpMatch m, int groupOffset) {
  final hours = int.parse(m.group(groupOffset)!);
  final minutes = int.parse(m.group(groupOffset + 1)!);
  final secs = int.parse(m.group(groupOffset + 2)!);
  final millis = int.parse(m.group(groupOffset + 3)!);
  return hours * 3600 + minutes * 60 + secs + millis / 1000;
}
