import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/clip.dart';

part 'thumbnails_view_model.g.dart';

/// Height (px) of each filmstrip thumbnail tile — matches the timeline
/// track-lane height in `timeline_panel.dart`.
const kFilmstripThumbHeight = 64;

/// Height (px) of the waveform strip drawn along the bottom of a clip bar.
const kWaveformHeight = 22;

/// The assumed source aspect ratio (width/height) used to size filmstrip
/// tiles before any frame has actually loaded. 16:9 covers the overwhelming
/// majority of footage; a mismatched real aspect just means tiles are
/// letterboxed/cropped slightly by [BoxFit.cover] in the UI, not a layout bug.
const kAssumedClipAspect = 16 / 9;

/// How many filmstrip thumbnails to request for a clip bar [widthPx] wide,
/// given tiles are [thumbHeight] tall at [aspect] (width / height).
///
/// [widthPx] is first rounded down to the nearest [bucketPx] — this is the
/// "debounce" for zoom/resize: small width changes (scrolling, a one-pixel
/// zoom nudge) land in the same bucket and therefore request the exact same
/// [count], so the thumbnail provider (keyed on `(clip, count, height)`)
/// reuses its cached result instead of re-extracting. Only a zoom/resize big
/// enough to cross a bucket boundary changes the count.
int thumbnailCountForWidth(
  double widthPx, {
  double thumbHeight = 64.0, // kFilmstripThumbHeight, as a double literal
  double aspect = kAssumedClipAspect,
  double bucketPx = 48,
  int minCount = 1,
  int maxCount = 40,
}) {
  if (widthPx <= 0) return minCount;
  final bucketed = (widthPx / bucketPx).floor() * bucketPx;
  final tileWidth = thumbHeight * aspect;
  if (tileWidth <= 0) return minCount;
  final count = (bucketed / tileWidth).ceil();
  return count.clamp(minCount, maxCount);
}

/// Bucketed waveform PNG width to request for a clip bar [barWidthPx] wide —
/// same bucketing idea as [thumbnailCountForWidth], so minor width changes
/// reuse the cached waveform image instead of re-rendering it.
int waveformWidthForBarWidth(double barWidthPx, {double bucketPx = 64}) {
  if (barWidthPx <= 0) return bucketPx.round();
  final bucketed = (barWidthPx / bucketPx).floor() * bucketPx;
  return (bucketed < bucketPx ? bucketPx : bucketed).round();
}

/// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
/// used to paint the timeline's filmstrip. Resolves to an empty list while
/// loading or if extraction isn't possible — the timeline keeps its
/// solid-colour placeholder bar in either case, so this never throws.
///
/// `keepAlive` (matching every other provider in this app — see
/// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
/// `@riverpod` default `autoDispose`: a request is keyed on
/// `(clip, count, height)`, and both [Clip] and the bucketing in
/// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
/// recurs across rebuilds/scrolling, so once extracted it should just stay
/// cached for the rest of the editing session rather than being thrown away
/// (and re-run) the instant a clip bar briefly stops being watched — e.g.
/// while another clip is being dragged over it.
@Riverpod(keepAlive: true)
Future<List<String>> clipFilmstrip(
  Ref ref,
  Clip clip,
  int count,
  int height,
) async {
  if (count <= 0) return const [];
  final engine = ref.watch(engineProvider);
  try {
    return await engine.extractThumbnails(
        clip: clip, count: count, height: height);
  } catch (_) {
    return const [];
  }
}

/// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
/// while loading / if the clip has no audio (or rendering otherwise fails).
/// `keepAlive` for the same reason as [clipFilmstrip].
@Riverpod(keepAlive: true)
Future<String?> clipWaveform(
  Ref ref,
  Clip clip,
  int width,
  int height,
) async {
  if (width <= 0) return null;
  final engine = ref.watch(engineProvider);
  try {
    return await engine.waveformPng(clip: clip, width: width, height: height);
  } catch (_) {
    return null;
  }
}
