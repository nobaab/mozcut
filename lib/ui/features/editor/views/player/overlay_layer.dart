import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../data/engine/engine.dart';
import '../../../../../data/engine/ffmpeg_engine.dart';
import '../../../../../domain/models/clip.dart';
import '../../../../../domain/models/sticker_overlay.dart';
import '../../../../../domain/models/text_overlay.dart';
import '../../../../../domain/models/video_overlay.dart';
import '../../view_models/sticker_overlays_view_model.dart';
import '../../view_models/text_overlays_view_model.dart';
import '../../view_models/video_overlays_view_model.dart';

part 'overlay_layer.g.dart';

/// A cache of still poster frames (keyed by source path) for picture-in-picture
/// overlays — the "poster-frame tier (a)" from spec §4: rather than spin up a
/// second live decoder per PiP, the preview shows one cached still frame of the
/// overlay, which is cheap and good enough for placement. The accurate preview
/// proxy (§6) still renders the real moving PiP.
@Riverpod(keepAlive: true)
class PipPosters extends _$PipPosters {
  final Set<String> _pending = {};

  @override
  Map<String, String> build() => const {};

  /// Ensures a poster frame exists for [overlay]'s source (idempotent; only the
  /// first request per source path spawns ffmpeg). Best-effort — a failure just
  /// leaves the overlay showing its labelled placeholder box.
  Future<void> ensure(Engine engine, VideoOverlay overlay) async {
    final key = overlay.sourcePath;
    if (state.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    try {
      final out =
          '${Directory.systemTemp.path}/mozcut_pip_poster_${key.hashCode}.jpg';
      if (!File(out).existsSync()) {
        await engine.savePoster(
          clip: Clip(
            sourcePath: overlay.sourcePath,
            sourceDuration: overlay.sourceDuration,
            inPoint: overlay.inPoint,
            outPoint: overlay.outPoint,
          ),
          outputPath: out,
          width: 480,
        );
      }
      if (File(out).existsSync()) state = {...state, key: out};
    } catch (_) {
      // Best-effort: the placeholder box covers this case.
    } finally {
      _pending.remove(key);
    }
  }
}

/// Parses a `#RRGGBB` (or `#AARRGGBB`) hex colour string, falling back to white.
Color parseHexColor(String hex) {
  var s = hex.replaceAll('#', '').trim();
  if (s.length == 6) s = 'FF$s';
  final value = int.tryParse(s, radix: 16);
  return value == null ? Colors.white : Color(value);
}

/// The text / sticker / PiP overlay layer drawn over the base video in the
/// real-time composite (spec §4). Shows every overlay active at the playhead
/// (`start ≤ t < end`) as a Flutter widget placed with the model's
/// frame-fraction coordinates — the same fractions ffmpeg burns in on export,
/// so placement is WYSIWYG.
class OverlayLayer extends ConsumerWidget {
  const OverlayLayer({
    super.key,
    required this.timelineT,
    required this.displayW,
    required this.displayH,
  });

  /// Timeline seconds at the playhead.
  final double timelineT;
  final double displayW;
  final double displayH;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texts = ref.watch(textOverlaysProvider);
    final stickers = ref.watch(stickerOverlaysProvider);
    final pips = ref.watch(videoOverlaysProvider);
    final t = timelineT;

    final children = <Widget>[];

    // PiP video overlays (poster-frame tier) — drawn first, under stickers/text.
    for (final o in pips) {
      if (!(t >= o.startTime && t < o.startTime + o.duration)) continue;
      children.add(_pip(ref, o));
    }
    // Stickers (emoji / image).
    for (final s in stickers) {
      if (!(t >= s.start && t < s.end)) continue;
      children.add(_sticker(s));
    }
    // Text overlays on top.
    for (final o in texts) {
      if (!(t >= o.start && t < o.end)) continue;
      children.add(_text(o));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(child: Stack(children: children));
  }

  Widget _text(TextOverlay o) {
    // Anchor the text box at (x, y); the alignment shifts the box relative to
    // that anchor the same way drawtext's alignment does (spec §4 table).
    final anchorShift = switch (o.alignment) {
      TextOverlayAlignment.left => 0.0,
      TextOverlayAlignment.center => -0.5,
      TextOverlayAlignment.right => -1.0,
    };
    final textAlign = switch (o.alignment) {
      TextOverlayAlignment.left => TextAlign.left,
      TextOverlayAlignment.center => TextAlign.center,
      TextOverlayAlignment.right => TextAlign.right,
    };
    return Positioned(
      left: o.x * displayW,
      top: o.y * displayH,
      child: FractionalTranslation(
        translation: Offset(anchorShift, 0),
        child: Text(
          o.text,
          textAlign: textAlign,
          style: TextStyle(
            color: parseHexColor(o.color),
            fontSize: o.fontSize * displayH,
            height: 1.1,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sticker(StickerOverlay s) {
    final size = s.size * displayH;
    final Widget content = s.isImage
        ? Image.file(File(s.imagePath!), height: size, fit: BoxFit.contain)
        : Text(s.emoji ?? '', style: TextStyle(fontSize: size, height: 1.0));
    return Positioned(
      left: s.x * displayW,
      top: s.y * displayH,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: s.rotation * 3.141592653589793 / 180.0,
          child: content,
        ),
      ),
    );
  }

  Widget _pip(WidgetRef ref, VideoOverlay o) {
    final engine = ref.read(engineProvider);
    // Kick off (idempotent) poster generation and read whatever is cached.
    ref.read(pipPostersProvider.notifier).ensure(engine, o);
    final posterPath = ref.watch(pipPostersProvider)[o.sourcePath];
    final width = o.scale * displayW;
    final Widget box = posterPath != null
        ? Image.file(File(posterPath), width: width, fit: BoxFit.contain)
        : Container(
            width: width,
            height: width * 9 / 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                o.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          );
    return Positioned(
      left: o.posX * displayW,
      top: o.posY * displayH,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Opacity(
          opacity: o.opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: o.rotation * 3.141592653589793 / 180.0,
            child: box,
          ),
        ),
      ),
    );
  }
}
