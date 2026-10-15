import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/caption.dart';
import '../../domain/models/clip.dart';
import '../../domain/models/text_overlay.dart';
import 'engine.dart';

part 'ffmpeg_engine.g.dart';

/// The app's single engine. Swap the implementation here (e.g. to a Rust-backed
/// engine) and nothing else changes.
@Riverpod(keepAlive: true)
Engine engine(Ref ref) => FfmpegEngine();

/// Engine implementation backed by the system `ffmpeg` / `ffprobe` binaries.
///
/// This spawns processes; it never links FFmpeg in-process. That is a feature:
/// it keeps the hard C out of the Dart app for now, and it is the easiest thing
/// that actually works on macOS and Windows. The binary is resolved from PATH,
/// then from the usual install locations.
class FfmpegEngine implements Engine {
  FfmpegEngine({String? ffmpegPath, String? ffprobePath})
      : _ffmpeg = ffmpegPath ?? _resolve('ffmpeg'),
        _ffprobe = ffprobePath ?? _resolve('ffprobe');

  final String _ffmpeg;
  final String _ffprobe;

  static const _candidateDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];

  static String _resolve(String tool) {
    final exe = Platform.isWindows ? '$tool.exe' : tool;
    for (final dir in _candidateDirs) {
      final p = '$dir/$exe';
      if (File(p).existsSync()) return p;
    }
    // Fall back to bare name and let the OS search PATH.
    return exe;
  }

  @override
  Future<double> probeDuration(String path) async {
    final result = await Process.run(_ffprobe, [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('ffprobe failed: ${result.stderr}');
    }
    final value = double.tryParse(result.stdout.toString().trim());
    if (value == null || value <= 0) {
      throw EngineException('Could not read duration from "$path"');
    }
    return value;
  }

  @override
  Future<void> export({
    required List<Clip> clips,
    required String outputPath,
    List<TextOverlay> textOverlays = const [],
    void Function(double progress)? onProgress,
  }) async {
    if (clips.isEmpty) {
      throw EngineException('Nothing to export — the timeline is empty.');
    }

    final totalDuration =
        clips.fold<double>(0, (sum, c) => sum + c.duration);

    // If any clip carries captions, burn them into the output via ffmpeg's
    // `subtitles` filter, fed from a temp .srt built from all clips' caption
    // lists with their timing shifted onto the final, concatenated timeline.
    // Keep this fully additive: no captions anywhere means no subtitles
    // filter and export behaves exactly as before.
    File? srtFile;
    if (clips.any((c) => c.captions.isNotEmpty)) {
      srtFile = File(
          '${Directory.systemTemp.path}/vidkaat_captions_${DateTime.now().millisecondsSinceEpoch}.srt');
      await srtFile.writeAsString(_buildSrt(clips));
    }

    // Each overlay's text is written to its own temp file and referenced via
    // drawtext's `textfile=` option, rather than embedding it inline as
    // `text=...`. This sidesteps ffmpeg's filtergraph escaping entirely for
    // arbitrary user text (colons, apostrophes, percent signs, …) — the only
    // thing that still needs escaping is the plain file path, exactly like
    // the subtitles file above.
    final overlayFiles = <File>[];
    try {
      // One ffmpeg call: each clip is an input trimmed with -ss/-to, then the
      // concat filter joins them. Re-encoding (not stream copy) so clips with
      // different codecs/resolutions still join cleanly — correctness over
      // speed for v0.1.
      final args = <String>['-y'];
      for (final clip in clips) {
        args.addAll([
          '-ss', clip.inPoint.toStringAsFixed(3),
          '-to', clip.outPoint.toStringAsFixed(3),
          '-i', clip.sourcePath,
        ]);
      }

      final filter = StringBuffer();
      for (var i = 0; i < clips.length; i++) {
        filter.write('[$i:v:0][$i:a:0]');
      }
      filter.write('concat=n=${clips.length}:v=1:a=1[v0][outa]');

      var videoLabel = '[v0]';
      if (srtFile != null) {
        filter.write(';[v0]subtitles=${_escapeFilterPath(srtFile.path)}[v1]');
        videoLabel = '[v1]';
      }

      // Burn in text/title overlays, one `drawtext` filter per overlay,
      // chained in order. Each is timed with `enable='between(t,start,end)'`
      // against `t`, which on this output label is already the final,
      // concatenated timeline — exactly what TextOverlay.start/end are
      // defined against. Fully additive: no overlays, no filter stage, and
      // the export is byte-for-byte what it was before this feature.
      if (textOverlays.isNotEmpty) {
        final fontFile = _resolveFont();
        for (var i = 0; i < textOverlays.length; i++) {
          final textFile = File(
              '${Directory.systemTemp.path}/vidkaat_text_${DateTime.now().millisecondsSinceEpoch}_$i.txt');
          await textFile.writeAsString(textOverlays[i].text);
          overlayFiles.add(textFile);

          final nextLabel = '[vt$i]';
          filter.write(
              ';$videoLabel${_drawtextFilter(textOverlays[i], textFile, fontFile)}$nextLabel');
          videoLabel = nextLabel;
        }
      }

      args.addAll([
        '-filter_complex', filter.toString(),
        '-map', videoLabel,
        '-map', '[outa]',
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '18',
        '-c:a', 'aac',
        '-progress', 'pipe:1',
        '-nostats',
        outputPath,
      ]);

      final process = await Process.start(_ffmpeg, args);

      // ffmpeg prints `out_time_ms=...` lines on stdout with -progress.
      process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (onProgress == null || totalDuration <= 0) return;
        if (line.startsWith('out_time_ms=')) {
          final us =
              int.tryParse(line.substring('out_time_ms='.length).trim());
          if (us != null) {
            onProgress((us / 1e6 / totalDuration).clamp(0.0, 1.0));
          }
        }
      });

      final stderr = StringBuffer();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderr.write);

      final code = await process.exitCode;
      if (code != 0) {
        throw EngineException('ffmpeg export failed (exit $code):\n$stderr');
      }
      onProgress?.call(1);
    } finally {
      if (srtFile != null && srtFile.existsSync()) {
        try {
          await srtFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      for (final file in overlayFiles) {
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (_) {
            // Best-effort cleanup only.
          }
        }
      }
    }
  }

  /// Builds a single .srt covering all [clips] in order, shifting each
  /// clip's (clip-relative) caption timings by the cumulative duration of the
  /// clips before it — i.e. onto the timeline of the final concatenated
  /// export.
  static String _buildSrt(List<Clip> clips) {
    final buffer = StringBuffer();
    var offset = 0.0;
    var index = 1;
    for (final clip in clips) {
      for (final caption in clip.captions) {
        final start = offset + caption.start;
        final end = offset + caption.end;
        if (end > start) {
          buffer
            ..writeln(index++)
            ..writeln(
                '${formatSrtTimestamp(start)} --> ${formatSrtTimestamp(end)}')
            ..writeln(caption.text)
            ..writeln();
        }
      }
      offset += clip.duration;
    }
    return buffer.toString();
  }

  /// Escapes a filesystem path for safe use inside an ffmpeg filtergraph
  /// option string (colons, backslashes and quotes are all filtergraph
  /// syntax), then wraps it in single quotes.
  static String _escapeFilterPath(String path) {
    final escaped = path
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
    return "'$escaped'";
  }

  /// Builds one `drawtext=...` filter clause (no surrounding `[in][out]`
  /// labels — the caller attaches those) for a single overlay.
  ///
  /// The overlay's text is read from [textFile] via drawtext's `textfile=`
  /// option rather than embedded inline — see the comment above the call
  /// site in [export] for why.
  ///
  /// Position: [TextOverlay.x]/[y] are fractions of the output frame, and the
  /// overlay's `alignment` only shifts where the text box sits relative to
  /// that anchor (left/center/right) — same idea as text-align in CSS.
  /// `fontsize` is left as an ffmpeg expression (`h*fraction`) rather than a
  /// literal number, so it is correct for whatever resolution this project
  /// exports at without Dart needing to know the output size.
  static String _drawtextFilter(
      TextOverlay overlay, File textFile, String? fontFile) {
    final xExpr = switch (overlay.alignment) {
      TextOverlayAlignment.left => '(w*${overlay.x})',
      TextOverlayAlignment.center => '(w*${overlay.x})-text_w/2',
      TextOverlayAlignment.right => '(w*${overlay.x})-text_w',
    };
    final parts = <String>[
      'drawtext=textfile=${_escapeFilterPath(textFile.path)}',
      if (fontFile != null) 'fontfile=${_escapeFilterPath(fontFile)}',
      'fontsize=h*${overlay.fontSize}',
      'fontcolor=${_ffColor(overlay.color)}',
      'x=$xExpr',
      'y=(h*${overlay.y})-text_h/2',
      // `expansion=none` stops drawtext from treating a lone '%' in the text
      // as the start of a `%{...}` template sequence — without it, titles
      // containing a literal '%' silently fail to render at all.
      'expansion=none',
      "enable='between(t,${overlay.start.toStringAsFixed(3)},${overlay.end.toStringAsFixed(3)})'",
    ];
    return parts.join(':');
  }

  /// Resolves a usable TrueType font for `drawtext`, trying common system
  /// locations across macOS/Windows/Linux. Returns null if none is found —
  /// the caller then omits `fontfile` entirely and lets ffmpeg fall back to
  /// its own default (via fontconfig, where available) rather than crashing.
  static String? _resolveFont() {
    const candidates = [
      // macOS
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      // Linux (common distro paths)
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      // Windows
      'C:/Windows/Fonts/arial.ttf',
      'C:/Windows/Fonts/Arial.ttf',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Converts a `#RRGGBB` (or `RRGGBB`) hex colour to the `0xRRGGBB` form
  /// ffmpeg's colour parser accepts. Anything that doesn't look like a hex
  /// triplet is passed through as-is (ffmpeg also accepts named colours like
  /// `white`).
  static String _ffColor(String color) {
    final hex = color.startsWith('#') ? color.substring(1) : color;
    final isHex = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
    return isHex ? '0x$hex' : color;
  }

  @override
  Future<void> savePoster({
    required Clip clip,
    required String outputPath,
    int width = 480,
  }) async {
    final result = await Process.run(_ffmpeg, [
      '-y',
      '-ss', clip.inPoint.toStringAsFixed(3),
      '-i', clip.sourcePath,
      '-frames:v', '1',
      '-vf', 'scale=$width:-2',
      outputPath,
    ]);
    if (result.exitCode != 0) {
      throw EngineException('poster extraction failed: ${result.stderr}');
    }
  }
}
