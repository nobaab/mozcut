import '../../../domain/models/audio_clip.dart';
import '../../../domain/models/clip.dart' as model;
import '../../../domain/models/video_overlay.dart';

/// Pure snapping math shared by every lane's move/trim drag handling (see
/// `timeline_panel.dart`'s `_ClipSlot`/`_AudioClipSlot`/`_VideoOverlaySlot`)
/// and the timeline's snap toggle/indicator (`editor_ui_state.dart`'s
/// `SnapEnabled`/`SnapIndicator`). Mirrors both reference editors analysed in
/// docs/TIMELINE-BEHAVIOR.md §7: targets are `0`, the playhead, and every
/// OTHER item's start/end across the video track, audio lane and overlay
/// lane; the threshold is a constant 8 screen pixels, converted to seconds at
/// the current zoom.

/// 8 screen pixels' worth of timeline seconds at [pixelsPerSecond] — the
/// snap threshold both reference editors use (`8/pps` in rea-capcut,
/// `8.0 * seconds_per_pixel` in concat). Returns 0 for a non-positive zoom
/// rather than dividing by zero/going negative.
double snapThresholdSeconds(double pixelsPerSecond) =>
    pixelsPerSecond <= 0 ? 0 : 8 / pixelsPerSecond;

/// Returns whichever entry of [targets] is nearest to [candidate], if one
/// lies within [thresholdSeconds] (inclusive); otherwise null. Ties (two
/// targets exactly equidistant) favour whichever appears first in [targets].
/// Pure and deterministic — see test/timeline_snap_test.dart.
double? snapTime(
  double candidate,
  List<double> targets,
  double thresholdSeconds,
) {
  double? best;
  var bestDistance = double.infinity;
  for (final target in targets) {
    final distance = (target - candidate).abs();
    if (distance <= thresholdSeconds && distance < bestDistance) {
      bestDistance = distance;
      best = target;
    }
  }
  return best;
}

/// The cumulative start offset (timeline seconds) of each clip in [clips], in
/// order on the single video track — clip `i` starts exactly where clip
/// `i - 1` ends. Factored out of `timeline_panel.dart`'s `_buildTimeline` so
/// the snap-target collection below (and tests) can share it.
List<double> computeClipStarts(List<model.Clip> clips) {
  final starts = <double>[];
  var acc = 0.0;
  for (final clip in clips) {
    starts.add(acc);
    acc += clip.duration;
  }
  return starts;
}

/// Every snap target (timeline seconds) available to a drag/trim currently in
/// progress: `0`, [playhead], and every *other* clip/audio-clip/video-overlay
/// edge (start and end) — never the item being dragged itself, which is why
/// the three `exclude*Id` parameters exist. Pass whichever one matches what's
/// being manipulated; the other two stay null (nothing to exclude in those
/// lanes).
///
/// [clipStarts] lets a caller that already has the video track's cumulative
/// starts (e.g. `_buildTimeline`) pass them in rather than recomputing; if
/// omitted they're derived from [clips] via [computeClipStarts].
List<double> collectSnapTargets({
  required double playhead,
  required List<model.Clip> clips,
  List<double>? clipStarts,
  List<AudioClip> audioClips = const [],
  List<VideoOverlay> overlays = const [],
  String? excludeClipId,
  String? excludeAudioClipId,
  String? excludeOverlayId,
}) {
  final starts = clipStarts ?? computeClipStarts(clips);
  final targets = <double>[0, playhead];
  for (var i = 0; i < clips.length; i++) {
    if (clips[i].id == excludeClipId) continue;
    targets.add(starts[i]);
    targets.add(starts[i] + clips[i].duration);
  }
  for (final audio in audioClips) {
    if (audio.id == excludeAudioClipId) continue;
    targets.add(audio.start);
    targets.add(audio.start + audio.duration);
  }
  for (final overlay in overlays) {
    if (overlay.id == excludeOverlayId) continue;
    targets.add(overlay.startTime);
    targets.add(overlay.startTime + overlay.duration);
  }
  return targets;
}

/// Attempts to snap a clip/item being *moved* (as opposed to trimmed) by
/// testing both of its edges against [targets] — "tested on both dragged
/// edges" in both reference editors (docs/TIMELINE-BEHAVIOR.md §3/§7), since
/// either the leading or trailing edge might be the one that lands near a
/// target. [start]/[duration] describe the item's unsnapped candidate
/// position (timeline seconds). Returns null if neither edge is within
/// [thresholdSeconds] of any target; otherwise the adjusted start (shifted by
/// whichever edge snapped with the smaller correction) and the absolute
/// timeline position the snap indicator line should be drawn at.
({double start, double lineAt})? snapMove({
  required double start,
  required double duration,
  required List<double> targets,
  required double thresholdSeconds,
}) {
  final snappedStart = snapTime(start, targets, thresholdSeconds);
  final snappedEnd = snapTime(start + duration, targets, thresholdSeconds);

  double? bestDelta;
  double? bestLineAt;
  if (snappedStart != null) {
    bestDelta = snappedStart - start;
    bestLineAt = snappedStart;
  }
  if (snappedEnd != null) {
    final delta = snappedEnd - (start + duration);
    if (bestDelta == null || delta.abs() < bestDelta.abs()) {
      bestDelta = delta;
      bestLineAt = snappedEnd;
    }
  }
  if (bestDelta == null) return null;
  return (start: start + bestDelta, lineAt: bestLineAt!);
}
