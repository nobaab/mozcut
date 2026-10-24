import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/audio_clip.dart';
import '../../../../domain/models/clip.dart' as model;
import '../../../../domain/models/media_type.dart';
import '../../../../domain/models/text_overlay.dart';
import '../../../../domain/models/video_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/split_handle.dart';
import '../timeline_snap.dart';
import '../view_models/audio_clips_view_model.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/media_import.dart';
import '../view_models/text_overlays_view_model.dart';
import '../view_models/thumbnails_view_model.dart';
import '../view_models/video_overlays_view_model.dart';
import 'transitions_panel.dart' show kTransitionCatalogue;

/// The timeline: a fixed track-header gutter on the left, then a horizontally
/// scrolling ruler + (optional) text lane + video track + overlay lane +
/// audio lane. Clips sit end to end on one video track, sized by the zoom;
/// text overlays, video overlays (the picture-in-picture lane) and audio
/// clips all float freely on their own lane, positioned by their own
/// `start`/`startTime`. A playhead line — with a small grab handle sitting
/// over the ruler — spans every lane and tracks the preview. Modelled on
/// CapCut. Also accepts drag-and-drop of media files, routed the same way as
/// the media browser's Import button (see `importMediaPaths`).
class TimelinePanel extends ConsumerStatefulWidget {
  const TimelinePanel({super.key});

  static const _headerWidth = 150.0;
  static const _rulerHeight = 24.0;
  static const _textLaneHeight = 32.0;
  static const _videoLaneHeight = 64.0;
  static const _laneGap = 6.0;
  static const _overlayLaneHeight = 48.0;
  static const _audioLaneHeight = 48.0;

  @override
  ConsumerState<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends ConsumerState<TimelinePanel> {
  bool _dragging = false;

  /// The text track's selected overlay, for the terracotta bars' highlight
  /// border. Text overlays have no "current selection" concept anywhere else
  /// in the app (unlike audio clips/video overlays, which each have their own
  /// provider) — see `text_panel.dart`, which just lists every overlay
  /// inline rather than tracking one as "current" — so this stays local,
  /// visual-only state rather than inventing app-wide persistence for it.
  String? _selectedTextOverlayId;

  /// The timeline's horizontal scroll position. Owned here (rather than left
  /// implicit inside `SingleChildScrollView`) so wheel/trackpad handling can
  /// read and adjust it directly, including compensating the offset when a
  /// zoom gesture changes the content width.
  final ScrollController _hScroll = ScrollController();

  /// The cumulative scale reported by the current trackpad pinch gesture, as
  /// of the last [_handlePanZoomUpdate] call — `PointerPanZoomUpdateEvent
  /// .scale` is cumulative since the gesture started, not incremental, so
  /// this is needed to derive a per-frame ratio.
  double _panZoomLastScale = 1.0;

  /// True whenever a pointer is down (mouse/touch/stylus click-drag, a clip
  /// move/trim, a ruler/empty-space scrub) or a trackpad pan/zoom gesture is
  /// in progress anywhere in the timeline's scrolling area. Set via the
  /// [Listener] wrapping it below — that `Listener` sees every raw pointer
  /// event that hits this region regardless of which descendant gesture
  /// recognizer (if any) ends up claiming it, so this one flag cheaply covers
  /// every kind of "the user is actively doing something here" without
  /// threading start/end callbacks through every gesture individually. Used
  /// to suppress [_followPlayhead] so playback auto-scroll never fights a
  /// manual interaction (see docs/TIMELINE-BEHAVIOR.md §5).
  bool _gestureActive = false;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  /// Keeps the playhead roughly 30% in from the right edge of the viewport
  /// while the preview plays, so it never scrolls off-screen — ported from
  /// rea-capcut's auto-scroll-follow rule (docs/TIMELINE-BEHAVIOR.md §5).
  /// No-ops while [_gestureActive] (a manual scroll/drag/trim/scrub in
  /// progress) so it never fights the user, and only actually moves the
  /// scroll offset once the playhead has drifted past the comfort zone —
  /// not on every single tick inside it — so normal playback within view
  /// doesn't "creep".
  void _followPlayhead(double playheadSeconds, double px) {
    if (_gestureActive || !_hScroll.hasClients) return;
    final viewport = _hScroll.position.viewportDimension;
    if (viewport <= 0) return;
    final playheadX = playheadSeconds * px;
    final comfortZoneStart = _hScroll.offset + viewport * 0.7;
    if (playheadX <= comfortZoneStart && playheadX >= _hScroll.offset) return;
    final target = (playheadX - viewport * 0.7)
        .clamp(0.0, _hScroll.position.maxScrollExtent);
    _hScroll.jumpTo(target);
  }

  bool _zoomModifierDown() =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Scrolls the timeline horizontally by [delta] pixels, clamped to the
  /// scrollable range.
  void _panBy(double delta) {
    if (delta == 0 || !_hScroll.hasClients) return;
    final target = (_hScroll.offset + delta)
        .clamp(0.0, _hScroll.position.maxScrollExtent);
    _hScroll.jumpTo(target);
  }

  /// Multiplies the timeline zoom by [factor] (clamped by
  /// [TimelineZoom.set]), keeping the instant in time under [cursorDx]
  /// (pixels into the timeline viewport) visually stationary.
  void _zoomBy({required double factor, required double cursorDx}) {
    if (factor == 1 || !factor.isFinite) return;
    final notifier = ref.read(timelineZoomProvider.notifier);
    final oldPx = ref.read(timelineZoomProvider);
    notifier.set(oldPx * factor);
    final newPx = ref.read(timelineZoomProvider);
    if (newPx == oldPx || !_hScroll.hasClients) return;

    final oldOffset = _hScroll.offset;
    // The content width (and so maxScrollExtent) only reflects the new zoom
    // after this frame's layout runs, so defer the compensating jump.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      final target = zoomAnchoredScrollOffset(
        oldOffset: oldOffset,
        cursorDx: cursorDx,
        oldPx: oldPx,
        newPx: newPx,
        maxScrollExtent: _hScroll.position.maxScrollExtent,
      );
      _hScroll.jumpTo(target);
    });
  }

  /// Real mouse wheel: Ctrl/Cmd+scroll zooms around the cursor; a plain
  /// scroll pans the timeline. A mouse wheel only ever reports a vertical
  /// delta, so that's remapped to horizontal panning here (the built-in
  /// `SingleChildScrollView` only reacts to the horizontal component, which
  /// a plain mouse never sends).
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_zoomModifierDown()) {
      _zoomBy(
        factor: math.exp(-event.scrollDelta.dy * 0.0025),
        cursorDx: event.localPosition.dx,
      );
    } else {
      _panBy(event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy);
    }
  }

  /// Trackpad: a pinch (scale != 1) zooms around the pointer; otherwise a
  /// plain two-finger scroll pans the timeline horizontally. We own ALL
  /// panning here (the scroll view itself is [NeverScrollableScrollPhysics])
  /// so there is exactly one pan channel and nothing arbitrates against the
  /// clip-drag recognizers — the "separate channels" model from
  /// docs/TIMELINE-BEHAVIOR.md §1. Both axes drive horizontal scroll: a
  /// natural left/right two-finger swipe pans, and a straight up/down swipe
  /// also scrubs sideways (CapCut convenience) — whichever axis the swipe is
  /// dominantly along wins, so a diagonal doesn't double up.
  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final scaleRatio = event.scale / _panZoomLastScale;
    _panZoomLastScale = event.scale;
    final pinching = (scaleRatio - 1.0).abs() > 0.0005;
    if (pinching) {
      _zoomBy(factor: scaleRatio, cursorDx: event.localPosition.dx);
      return;
    }
    final d = event.panDelta;
    if (_zoomModifierDown()) {
      // Ctrl/Cmd + two-finger scroll (no pinch): drive the zoom off the
      // vertical pan delta instead of panning.
      _zoomBy(
        factor: math.exp(-d.dy * 0.01),
        cursorDx: event.localPosition.dx,
      );
      return;
    }
    // Horizontal swipe → pan by -dx (content follows the fingers); vertical
    // swipe → pan by dy. Use the dominant axis so a diagonal swipe doesn't
    // apply both at once.
    _panBy(d.dx.abs() >= d.dy.abs() ? -d.dx : d.dy);
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        await importMediaPaths(
          ref,
          details.files.map((f) => f.path),
          onError: (message) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          },
        );
      },
      child: Stack(
        children: [
          _buildTimeline(context, ref),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: const Center(
                    child: Text('Drop to import',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Toggles a default transition entering [enteringClip] from the clip
  /// before it — i.e. the boundary between [enteringClip] and its previous
  /// neighbour on the video track. See `Clip.transitionId`'s doc comment:
  /// the transition for a cut between clip N and clip N+1 lives on clip
  /// N+1 ("entering" side), not clip N — so this selects [enteringClip]
  /// (matching how the Transitions panel always edits `state.selected`) and
  /// applies the catalogue's first preset, or clears it if one's already
  /// set on that boundary.
  void _toggleTransitionAt(WidgetRef ref, model.Clip enteringClip) {
    final editor = ref.read(editorProvider.notifier);
    editor.select(enteringClip.id);
    editor.setSelectedTransition(
        enteringClip.transitionId == null ? kTransitionCatalogue.first : null);
  }

  Widget _buildTimeline(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final px = ref.watch(timelineZoomProvider);
    final audioClips = ref.watch(audioClipsProvider);
    final selectedAudioId = ref.watch(selectedAudioClipProvider);
    final videoOverlays = ref.watch(videoOverlaysProvider);
    final selectedOverlayId = ref.watch(selectedVideoOverlayProvider);
    final textOverlays = ref.watch(textOverlaysProvider);

    final total = state.totalDuration;
    // Cumulative start offset of each clip on the timeline.
    final starts = computeClipStarts(state.clips);

    // Playback auto-scroll-follow (docs/TIMELINE-BEHAVIOR.md §5): `ref
    // .listen` (not `.watch`) so this reacts to every playhead tick during
    // playback without rebuilding the timeline itself — same reasoning as
    // why [_Playhead] is isolated below. `_followPlayhead` no-ops unless
    // [IsPlaying] is true and no gesture is in progress.
    ref.listen<double>(playheadProvider, (previous, next) {
      if (ref.read(isPlayingProvider)) _followPlayhead(next, px);
    });

    // The text/overlay/audio lanes' items are positioned independently of
    // the video track, so the content area needs to be wide enough for
    // whichever of the four extends further right.
    var audioEnd = 0.0;
    for (final a in audioClips) {
      audioEnd = math.max(audioEnd, a.start + a.duration);
    }
    var overlayEnd = 0.0;
    for (final o in videoOverlays) {
      overlayEnd = math.max(overlayEnd, o.startTime + o.duration);
    }
    var textEnd = 0.0;
    for (final t in textOverlays) {
      textEnd = math.max(textEnd, t.end);
    }
    final timelineSeconds =
        math.max(total, math.max(audioEnd, math.max(overlayEnd, textEnd)));

    // CapCut hides a track entirely once it has nothing on it — each lane
    // (and its header row, see _trackHeader) only appears once it has at least
    // one item. The video track always shows.
    final showTextLane = textOverlays.isNotEmpty;
    final showOverlayLane = videoOverlays.isNotEmpty;
    final showAudioLane = audioClips.isNotEmpty;

    // The live playhead is read only inside [_Playhead] below (which alone
    // watches playheadProvider). This build deliberately does NOT watch it, so
    // the playhead ticking during playback repaints just the thin scrubber
    // overlay, not the whole timeline and every clip bar/filmstrip/waveform —
    // which is what made clicking and selecting feel laggy while playing.

    final isEmpty = state.clips.isEmpty &&
        audioClips.isEmpty &&
        videoOverlays.isEmpty &&
        textOverlays.isEmpty;

    return Container(
      color: AppColors.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: TimelinePanel._headerWidth,
              child: _trackHeader(
                  showTextLane: showTextLane,
                  showOverlayLane: showOverlayLane,
                  showAudioLane: showAudioLane)),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
          Expanded(
            child: isEmpty
                ? Center(
                    child: Text(
                        'Imported clips show up here — drop media to add it',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25))),
                  )
                : LayoutBuilder(builder: (context, c) {
                    final contentW = (timelineSeconds * px + 80)
                        .clamp(c.maxWidth, double.infinity);
                    void scrub(double localDx) => _scrubToTimelineSeconds(
                        ref, state, starts, localDx / px);
                    return Listener(
                      onPointerDown: (_) => _gestureActive = true,
                      onPointerUp: (_) => _gestureActive = false,
                      onPointerCancel: (_) => _gestureActive = false,
                      onPointerSignal: _handlePointerSignal,
                      onPointerPanZoomStart: (_) {
                        _panZoomLastScale = 1.0;
                        _gestureActive = true;
                      },
                      onPointerPanZoomEnd: (_) => _gestureActive = false,
                      onPointerPanZoomUpdate: _handlePanZoomUpdate,
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        // All panning is driven by the parent [Listener]
                        // (_handlePanZoomUpdate / _handlePointerSignal) via
                        // _hScroll.jumpTo, so the scroll view must not run its
                        // own gesture recognizer — otherwise a trackpad swipe
                        // is handled by BOTH, which fights and feels janky.
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: contentW.toDouble(),
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  // The ruler is a dedicated scrub strip:
                                  // click or drag along it to move the
                                  // playhead.
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (d) =>
                                        scrub(d.localPosition.dx),
                                    onHorizontalDragUpdate: (d) =>
                                        scrub(d.localPosition.dx),
                                    child: _Ruler(
                                        seconds: timelineSeconds, px: px),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (showTextLane) ...[
                                            SizedBox(
                                              height: TimelinePanel
                                                  ._textLaneHeight,
                                              width: contentW.toDouble(),
                                              child: Stack(
                                                children: [
                                                  // Empty lane space:
                                                  // tapping it clears the
                                                  // (local-only) text
                                                  // selection — same idiom
                                                  // as the overlay/audio
                                                  // lanes below.
                                                  Positioned.fill(
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapDown: (_) =>
                                                          setState(() =>
                                                              _selectedTextOverlayId =
                                                                  null),
                                                    ),
                                                  ),
                                                  for (final overlay
                                                      in textOverlays)
                                                    Positioned(
                                                      key:
                                                          ValueKey(overlay.id),
                                                      left: overlay.start * px,
                                                      width:
                                                          overlay.duration *
                                                              px,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: _TextOverlayBar(
                                                        overlay: overlay,
                                                        selected: overlay
                                                                .id ==
                                                            _selectedTextOverlayId,
                                                        onTap: () => setState(
                                                            () =>
                                                                _selectedTextOverlayId =
                                                                    overlay
                                                                        .id),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(
                                                height:
                                                    TimelinePanel._laneGap),
                                          ],
                                          // The one video track lane.
                                          SizedBox(
                                            height: TimelinePanel
                                                ._videoLaneHeight,
                                            width: contentW.toDouble(),
                                            child: Stack(
                                              children: [
                                                // Empty track space: click to
                                                // scrub (clips above handle
                                                // their own taps/drags and
                                                // take priority).
                                                Positioned.fill(
                                                  child: GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .opaque,
                                                    onTapDown: (d) => scrub(
                                                        d.localPosition.dx),
                                                  ),
                                                ),
                                                for (var i = 0;
                                                    i < state.clips.length;
                                                    i++)
                                                  Positioned(
                                                    key: ValueKey(
                                                        state.clips[i].id),
                                                    left: starts[i] * px,
                                                    width: state
                                                            .clips[i]
                                                            .duration *
                                                        px,
                                                    top: 0,
                                                    bottom: 0,
                                                    child: _ClipSlot(
                                                      clip: state.clips[i],
                                                      index: i,
                                                      clips: state.clips,
                                                      starts: starts,
                                                      audioClips: audioClips,
                                                      overlays: videoOverlays,
                                                      px: px,
                                                      selected: state
                                                              .clips[i].id ==
                                                          state.selectedId,
                                                      onTap: () => ref
                                                          .read(editorProvider
                                                              .notifier)
                                                          .select(state
                                                              .clips[i].id),
                                                      onReorder: (newIndex) =>
                                                          ref
                                                              .read(
                                                                  editorProvider
                                                                      .notifier)
                                                              .reorder(i,
                                                                  newIndex),
                                                      onTrimLeftDx: (dx) =>
                                                          _onVideoTrimLeft(
                                                              ref,
                                                              state.clips,
                                                              starts,
                                                              audioClips,
                                                              videoOverlays,
                                                              i,
                                                              px,
                                                              dx),
                                                      onTrimRightDx: (dx) =>
                                                          _onVideoTrimRight(
                                                              ref,
                                                              state.clips,
                                                              starts,
                                                              audioClips,
                                                              videoOverlays,
                                                              i,
                                                              px,
                                                              dx),
                                                    ),
                                                  ),
                                                // Transition markers, one
                                                // per boundary between
                                                // adjacent clips — drawn
                                                // after (so on top of) the
                                                // clips, but small enough
                                                // that they don't swallow
                                                // the trim handles/reorder
                                                // drag sitting at the same
                                                // boundary (see
                                                // _TransitionMarker).
                                                for (var i = 0;
                                                    i <
                                                        state.clips.length - 1;
                                                    i++)
                                                  Positioned(
                                                    left: starts[i + 1] * px -
                                                        _TransitionMarker
                                                                ._size /
                                                            2,
                                                    top: (TimelinePanel
                                                                ._videoLaneHeight -
                                                            _TransitionMarker
                                                                ._size) /
                                                        2,
                                                    child: _TransitionMarker(
                                                      active: state
                                                              .clips[i + 1]
                                                              .transitionId !=
                                                          null,
                                                      onTap: () =>
                                                          _toggleTransitionAt(
                                                              ref,
                                                              state.clips[
                                                                  i + 1]),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (showOverlayLane) ...[
                                            const SizedBox(
                                                height:
                                                    TimelinePanel._laneGap),
                                            // The overlay lane: video overlays
                                            // (picture-in-picture) float
                                            // freely, positioned by their own
                                            // `startTime` (unlike the video
                                            // track, they don't shift each
                                            // other) — same treatment as the
                                            // audio lane below.
                                            SizedBox(
                                              height: TimelinePanel
                                                  ._overlayLaneHeight,
                                              width: contentW.toDouble(),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapDown: (_) => ref
                                                          .read(
                                                              selectedVideoOverlayProvider
                                                                  .notifier)
                                                          .set(null),
                                                    ),
                                                  ),
                                                  for (var i = 0;
                                                      i < videoOverlays.length;
                                                      i++)
                                                    Positioned(
                                                      key: ValueKey(
                                                          videoOverlays[i].id),
                                                      left: videoOverlays[i]
                                                              .startTime *
                                                          px,
                                                      width: videoOverlays[i]
                                                              .duration *
                                                          px,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: _VideoOverlaySlot(
                                                        overlay:
                                                            videoOverlays[i],
                                                        index: i,
                                                        clips: state.clips,
                                                        starts: starts,
                                                        audioClips: audioClips,
                                                        overlays: videoOverlays,
                                                        px: px,
                                                        selected:
                                                            videoOverlays[i]
                                                                    .id ==
                                                                selectedOverlayId,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (showAudioLane) ...[
                                            const SizedBox(
                                                height:
                                                    TimelinePanel._laneGap),
                                            // The audio lane: clips float
                                            // freely, positioned by their own
                                            // `start` (unlike the video track,
                                            // they don't shift each other).
                                            SizedBox(
                                              height: TimelinePanel
                                                  ._audioLaneHeight,
                                              width: contentW.toDouble(),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapDown: (_) => ref
                                                          .read(
                                                              selectedAudioClipProvider
                                                                  .notifier)
                                                          .set(null),
                                                    ),
                                                  ),
                                                  for (var i = 0;
                                                      i < audioClips.length;
                                                      i++)
                                                    Positioned(
                                                      key: ValueKey(
                                                          audioClips[i].id),
                                                      left: audioClips[i]
                                                              .start *
                                                          px,
                                                      width: audioClips[i]
                                                              .duration *
                                                          px,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: _AudioClipSlot(
                                                        clip: audioClips[i],
                                                        index: i,
                                                        clips: state.clips,
                                                        starts: starts,
                                                        audioClips: audioClips,
                                                        overlays: videoOverlays,
                                                        px: px,
                                                        selected: audioClips[i]
                                                                .id ==
                                                            selectedAudioId,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Snap indicator: a thin line at whatever
                              // target the active drag/trim is currently
                              // magnetized to. Isolated into its own
                              // snap-watching widget (see [_SnapLine]), same
                              // reasoning as [_Playhead] just below.
                              _SnapLine(px: px),
                              // Playhead: spans the ruler and every lane
                              // beneath it, with a small grab handle sitting
                              // over the ruler. Isolated into its own
                              // playhead-watching widget (see [_Playhead]) so
                              // it repaints on its own during playback.
                              _Playhead(px: px),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  /// The left-hand track-header gutter: one row per lane, each exactly as
  /// tall as (and separated by the same gap as) its counterpart lane in the
  /// scrolling content — see the matching `TimelinePanel._xLaneHeight`/
  /// `_laneGap` constants used on both sides — so the controls here always
  /// sit level with the right track. [showTextLane]/[showOverlayLane]/
  /// [showAudioLane] must mirror whatever the content side passed for the same
  /// build (see `_buildTimeline`), so each row appears/disappears in lockstep
  /// with its lane.
  Widget _trackHeader({
    required bool showTextLane,
    required bool showOverlayLane,
    required bool showAudioLane,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: TimelinePanel._rulerHeight),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showTextLane) ...[
                  SizedBox(
                    height: TimelinePanel._textLaneHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(Icons.title,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child:
                                Text('Text', style: TextStyle(fontSize: 11)),
                          ),
                          _hdrIcon(Icons.lock_outline),
                          const SizedBox(width: 8),
                          _hdrIcon(Icons.visibility_outlined),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: TimelinePanel._laneGap),
                ],
                SizedBox(
                  height: TimelinePanel._videoLaneHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.well,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.image_outlined,
                                  size: 16,
                                  color:
                                      Colors.white.withValues(alpha: 0.4)),
                            ),
                            const SizedBox(width: 6),
                            const Text('Cover', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _hdrIcon(Icons.play_arrow),
                            _hdrIcon(Icons.lock_outline),
                            _hdrIcon(Icons.visibility_outlined),
                            _hdrIcon(Icons.volume_up_outlined),
                            _hdrIcon(Icons.more_horiz),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (showOverlayLane) ...[
                  const SizedBox(height: TimelinePanel._laneGap),
                  SizedBox(
                    height: TimelinePanel._overlayLaneHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(Icons.picture_in_picture_alt_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text('Overlay',
                                style: TextStyle(fontSize: 11)),
                          ),
                          _hdrIcon(Icons.lock_outline),
                          const SizedBox(width: 8),
                          _hdrIcon(Icons.visibility_outlined),
                        ],
                      ),
                    ),
                  ),
                ],
                if (showAudioLane) ...[
                  const SizedBox(height: TimelinePanel._laneGap),
                  SizedBox(
                    height: TimelinePanel._audioLaneHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(Icons.av_timer,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child:
                                Text('Audio', style: TextStyle(fontSize: 11)),
                          ),
                          _hdrIcon(Icons.lock_outline),
                          const SizedBox(width: 8),
                          _hdrIcon(Icons.volume_up_outlined),
                          const SizedBox(width: 8),
                          _hdrIcon(Icons.more_horiz),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _hdrIcon(IconData icon) =>
      Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.5));

  /// Handles a drag of video clip [index]'s left trim handle (see
  /// `_ClipSlot.onTrimLeftDx`): converts the raw pixel delta to a proposed
  /// `inPoint`, by way of the resulting timeline-seconds duration — which
  /// keeps the conversion speed-aware (`duration = (out-in)/speed`, the same
  /// relationship `Clip.duration`/`Editor.splitSelectedAt` use) rather than
  /// treating a screen-pixel delta as a source-seconds delta directly. Snaps
  /// that duration via [_snapVideoTrimDuration] before committing.
  void _onVideoTrimLeft(
    WidgetRef ref,
    List<model.Clip> clips,
    List<double> starts,
    List<AudioClip> audioClips,
    List<VideoOverlay> overlays,
    int index,
    double px,
    double dx,
  ) {
    final c = clips[index];
    final rawIn = c.inPoint + dx / px;
    final rawDuration = (c.outPoint - rawIn).clamp(0.0, c.sourceDuration) / c.speed;
    final duration = _snapVideoTrimDuration(
        ref, clips, starts, audioClips, overlays, index, px, rawDuration);
    final newIn = c.outPoint - duration * c.speed;
    ref.read(editorProvider.notifier).setTrim(c.id, inPoint: newIn);
  }

  /// Handles a drag of video clip [index]'s right trim handle (see
  /// `_ClipSlot.onTrimRightDx`) — the mirror of [_onVideoTrimLeft] for the
  /// `outPoint` edge.
  void _onVideoTrimRight(
    WidgetRef ref,
    List<model.Clip> clips,
    List<double> starts,
    List<AudioClip> audioClips,
    List<VideoOverlay> overlays,
    int index,
    double px,
    double dx,
  ) {
    final c = clips[index];
    final rawOut = c.outPoint + dx / px;
    final rawDuration = (rawOut - c.inPoint).clamp(0.0, c.sourceDuration) / c.speed;
    final duration = _snapVideoTrimDuration(
        ref, clips, starts, audioClips, overlays, index, px, rawDuration);
    final newOut = c.inPoint + duration * c.speed;
    ref.read(editorProvider.notifier).setTrim(c.id, outPoint: newOut);
  }

  /// Shared snapping step for both video trim handles: given [rawDuration]
  /// (the timeline-seconds duration the raw, unsnapped drag implies), snaps
  /// the clip's right edge — `starts[index] + duration`, the only edge of
  /// this clip that visually moves under either handle, since its left edge
  /// is pinned by the running-sum layout (see docs/TIMELINE-BEHAVIOR.md §4)
  /// — to the nearest target within the snap threshold, and returns the
  /// (possibly adjusted) duration. Updates [snapIndicatorProvider] to match.
  /// Returns [rawDuration] unchanged, and clears the indicator, when snapping
  /// is off or nothing is in range.
  double _snapVideoTrimDuration(
    WidgetRef ref,
    List<model.Clip> clips,
    List<double> starts,
    List<AudioClip> audioClips,
    List<VideoOverlay> overlays,
    int index,
    double px,
    double rawDuration,
  ) {
    if (!ref.read(snapEnabledProvider)) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      return rawDuration;
    }
    final targets = collectSnapTargets(
      playhead: ref.read(playheadProvider),
      clips: clips,
      clipStarts: starts,
      audioClips: audioClips,
      overlays: overlays,
      excludeClipId: clips[index].id,
    );
    final rawRightEdge = starts[index] + rawDuration;
    final snapped = snapTime(rawRightEdge, targets, snapThresholdSeconds(px));
    ref.read(snapIndicatorProvider.notifier).set(snapped);
    return snapped == null ? rawDuration : snapped - starts[index];
  }
}

/// The dark ruler strip: time labels (`00:00`, `00:03`, …) over a baseline of
/// tick marks — a tall tick under each label, shorter minor ticks
/// subdividing the gap to the next one, CapCut-style.
class _Ruler extends StatelessWidget {
  const _Ruler({required this.seconds, required this.px});
  final double seconds;
  final double px;

  /// Minor ticks drawn between each pair of labelled major ticks.
  static const _minorsPerMajor = 4;

  @override
  Widget build(BuildContext context) {
    // Choose a label step that stays readable as zoom changes.
    final step = px > 80
        ? 1
        : px > 30
            ? 5
            : px > 12
                ? 10
                : 30;
    final minorStep = step / _minorsPerMajor;
    final marks = <Widget>[];
    for (var major = 0; major <= seconds + step; major += step) {
      marks.add(_tick(major.toDouble(), tall: true));
      marks.add(Positioned(
        left: major * px,
        top: 3,
        child: Text(_fmt(major),
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
      ));
      for (var s = 1; s < _minorsPerMajor; s++) {
        final t = major + s * minorStep;
        if (t > seconds + step) break;
        marks.add(_tick(t, tall: false));
      }
    }
    return Container(
      height: TimelinePanel._rulerHeight,
      decoration: const BoxDecoration(
        color: AppColors.well,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Stack(children: marks),
    );
  }

  Widget _tick(double t, {required bool tall}) => Positioned(
        left: t * px,
        bottom: 0,
        child: Container(
          width: 1,
          height: tall ? 8 : 4,
          color: Colors.white.withValues(alpha: tall ? 0.45 : 0.2),
        ),
      );

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// The scrubber line + grab handle, spanning the ruler and every lane. This is
/// the ONLY widget that watches [playheadProvider]; the rest of the timeline
/// reads the selection statically. Keeping it separate means the playhead
/// ticking during playback repaints just these two thin boxes, not the whole
/// timeline (every clip bar, filmstrip and waveform) — otherwise clicking and
/// selecting feel laggy while the preview plays. Purely visual
/// ([IgnorePointer]) so it never steals the ruler's scrub gesture or a lane's
/// tap/drag from underneath.
class _Playhead extends ConsumerWidget {
  const _Playhead({required this.px});

  final double px;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [playheadProvider] is timeline seconds (0..totalDuration), driven by the
    // preview player and the ruler scrub — position directly.
    final playheadT = ref.watch(playheadProvider);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: playheadT * px - 1,
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: AppColors.accent),
          ),
          Positioned(
            left: playheadT * px - 6,
            top: 2,
            child: Container(
              width: 12,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The magnetic-snap indicator: a thin accent line spanning every lane,
/// shown only while a drag/trim is actively snapped to a target (`0`, the
/// playhead, or another item's edge — see `lib/ui/features/editor/
/// timeline_snap.dart` and the [snapIndicatorProvider] it feeds). The ONLY
/// widget watching that provider — same isolated, cheaply-repainting
/// treatment as [_Playhead] — so a drag's per-frame snap updates never
/// rebuild the rest of the timeline. [IgnorePointer]-wrapped so it never
/// steals a lane's own gestures.
class _SnapLine extends ConsumerWidget {
  const _SnapLine({required this.px});

  final double px;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snappedAt = ref.watch(snapIndicatorProvider);
    return IgnorePointer(
      child: Stack(
        children: [
          if (snappedAt != null)
            Positioned(
              left: snappedAt * px,
              top: 0,
              bottom: 0,
              child: Container(
                  width: 1, color: AppColors.accent.withValues(alpha: 0.9)),
            ),
        ],
      ),
    );
  }
}

/// A tap + horizontal-drag area for a clip body whose drag recognizer
/// deliberately EXCLUDES [PointerDeviceKind.trackpad]. A macOS trackpad
/// two-finger swipe is surfaced to Flutter as a synthetic pointer that an
/// ordinary [HorizontalDragGestureRecognizer] would accept — and, being the
/// hit-tested child, it wins the gesture arena against the ancestor
/// [Scrollable], so the clip slides instead of the view panning. Restricting
/// the devices lets a trackpad swipe fall through to the scroll view (the view
/// pans) while a real mouse/touch/stylus drag still moves the clip — the
/// "separate input channels" model CapCut-style editors rely on (see
/// docs/TIMELINE-BEHAVIOR.md §1).
class _ClipDragArea extends StatelessWidget {
  const _ClipDragArea({
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final VoidCallback onTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onDragCancel;
  final Widget child;

  static const _dragDevices = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    // PointerDeviceKind.trackpad intentionally omitted — see class doc.
  };

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (r) => r.onTap = onTap,
        ),
        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            HorizontalDragGestureRecognizer>(
          () =>
              HorizontalDragGestureRecognizer(supportedDevices: _dragDevices),
          (r) => r
            ..onStart = onDragStart
            ..onUpdate = onDragUpdate
            ..onEnd = onDragEnd
            ..onCancel = onDragCancel,
        ),
      },
      child: child,
    );
  }
}

/// Computes the horizontal scroll offset that keeps the instant in time under
/// the pointer visually stationary after a zoom change. [cursorDx] is the
/// pointer's position in pixels within the timeline *viewport* (not the
/// scrolled content); [oldOffset]/[oldPx] describe the scroll/zoom state just
/// before the change, and [newPx] the zoom level just after. The result is
/// clamped to `[0, maxScrollExtent]`.
double zoomAnchoredScrollOffset({
  required double oldOffset,
  required double cursorDx,
  required double oldPx,
  required double newPx,
  required double maxScrollExtent,
}) {
  final timeAtCursor = (oldOffset + cursorDx) / oldPx;
  final target = timeAtCursor * newPx - cursorDx;
  return target.clamp(0.0, maxScrollExtent);
}

/// Moves the playhead to the position under a click/drag on the ruler or
/// track. [localDxSeconds] is the horizontal position in timeline seconds. If
/// nothing is selected, best-effort-selects whichever clip sits under that
/// position first, then maps the position into that clip's source time.
void _scrubToTimelineSeconds(
  WidgetRef ref,
  EditorState state,
  List<double> starts,
  double localDxSeconds,
) {
  final editor = ref.read(editorProvider.notifier);
  if (state.selectedIndex < 0) {
    final idx = _clipIndexAt(state.clips, starts, localDxSeconds);
    if (idx >= 0) editor.select(state.clips[idx].id);
  }
  // The playhead is timeline time; set it directly. The preview player
  // listens and seeks to match (see PlayerPanel).
  final total = starts.isEmpty
      ? 0.0
      : starts.last + state.clips.last.duration;
  ref
      .read(playheadProvider.notifier)
      .set(localDxSeconds.clamp(0.0, total <= 0 ? localDxSeconds : total));
}

/// The index of the clip covering timeline second [t], clamping to the
/// nearest clip if [t] falls before the first or after the last.
int _clipIndexAt(List<model.Clip> clips, List<double> starts, double t) {
  if (clips.isEmpty) return -1;
  for (var i = 0; i < clips.length; i++) {
    if (t >= starts[i] && t < starts[i] + clips[i].duration) return i;
  }
  return t < starts.first ? 0 : clips.length - 1;
}

/// The small CapCut-style button straddling the boundary between two
/// adjacent video clips: tap to toggle a default transition entering the
/// clip on the right (see `_TimelinePanelState._toggleTransitionAt`).
/// Deliberately small, and only handles taps (no drag), so it doesn't
/// swallow the trim handles/reorder-drag area that also sit at the clip
/// boundary (see [_ClipSlot]).
class _TransitionMarker extends StatelessWidget {
  const _TransitionMarker({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  static const _size = 26.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(Icons.compare_arrows,
            size: 15,
            color: Colors.white.withValues(alpha: active ? 1 : 0.75)),
      ),
    );
  }
}

/// A text-track bar: a terracotta rounded chip showing the overlay's text,
/// positioned by its [TextOverlay.start]/[TextOverlay.end]. Tap to select —
/// see [_TimelinePanelState._selectedTextOverlayId] for why selection here is
/// local, visual-only state.
class _TextOverlayBar extends StatelessWidget {
  const _TextOverlayBar({
    required this.overlay,
    required this.selected,
    required this.onTap,
  });

  final TextOverlay overlay;
  final bool selected;
  final VoidCallback onTap;

  static const _barColor = Color(0xFFB0553C);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _barColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          overlay.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }
}

/// A clip's bar background: a filmstrip of real frames across its width with
/// a waveform strip along the bottom (CapCut-style), the filename label (in
/// a small translucent-black chip, top-left), and the selected/accent
/// border. Thumbnails/waveform are fetched through
/// [clipFilmstripProvider]/[clipWaveformProvider] (see
/// `thumbnails_view_model.dart`) — while those are loading (or if extraction
/// isn't possible, e.g. no audio track) this just keeps showing the original
/// solid-colour bar underneath, so there is never an empty/broken-looking gap.
class _ClipBar extends ConsumerWidget {
  const _ClipBar(
      {required this.clip, required this.widthPx, required this.selected});

  final model.Clip clip;
  final double widthPx;
  final bool selected;

  static const _barColor = Color(0xFF2A3550);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage = clip.mediaType == MediaType.image;

    // An image clip has no frames to extract and no real audio — show the
    // source image itself as the bar's background instead of a filmstrip,
    // and skip the waveform strip entirely.
    final count = isImage ? 0 : thumbnailCountForWidth(widthPx);
    final waveformWidth = waveformWidthForBarWidth(widthPx);
    final thumbs = isImage
        ? null
        : ref
            .watch(clipFilmstripProvider(clip, count, kFilmstripThumbHeight))
            .value;
    final wave = isImage
        ? null
        : ref
            .watch(clipWaveformProvider(clip, waveformWidth, kWaveformHeight))
            .value;

    return Container(
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: _barColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isImage)
            Image.file(
              File(clip.sourcePath),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          // Filmstrip: real frames tiled across the bar, behind everything
          // else. Falls back to the plain bar colour until frames are ready.
          if (thumbs != null && thumbs.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final path in thumbs)
                  Expanded(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          // Waveform strip along the bottom, over a translucent scrim so it
          // reads against any frame behind it.
          if (wave != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: kWaveformHeight.toDouble(),
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.35),
                child: Image.file(
                  File(wave),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Filename label, top-left, in a small translucent scrim chip —
          // on top of everything, so it stays legible over bright frames.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(left: 6, top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(clip.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A clip bar on the track: tap to select, drag the body to reorder, drag the
/// left/right edge handles to trim. The body drag only gives visual feedback
/// (a translation) while dragging; the reorder itself commits once on
/// release, based on where the bar's centre ends up relative to its
/// neighbours' centres.
class _ClipSlot extends ConsumerStatefulWidget {
  const _ClipSlot({
    required this.clip,
    required this.index,
    required this.clips,
    required this.starts,
    required this.audioClips,
    required this.overlays,
    required this.px,
    required this.selected,
    required this.onTap,
    required this.onReorder,
    required this.onTrimLeftDx,
    required this.onTrimRightDx,
  });

  final model.Clip clip;
  final int index;
  final List<model.Clip> clips;
  final List<double> starts;

  /// The audio lane and overlay lane, so a move-drag can also snap to their
  /// clips'/overlays' edges (cross-lane snapping — see
  /// docs/TIMELINE-BEHAVIOR.md §7).
  final List<AudioClip> audioClips;
  final List<VideoOverlay> overlays;

  final double px;
  final bool selected;
  final VoidCallback onTap;

  /// Called once, on release, with the resolved target index.
  final ValueChanged<int> onReorder;

  /// Called on every pointer-move of the left/right handle with the raw
  /// pixel delta (positive = dragged right).
  final ValueChanged<double> onTrimLeftDx;
  final ValueChanged<double> onTrimRightDx;

  static const _handleWidth = 8.0;

  @override
  ConsumerState<_ClipSlot> createState() => _ClipSlotState();
}

class _ClipSlotState extends ConsumerState<_ClipSlot> {
  double _dragDx = 0;

  /// Live-preview drag update: magnetizes [_dragDx] to the nearest snap
  /// target (tested on both of the clip's edges — see [snapMove]) when
  /// snapping is on, otherwise just accumulates the raw pixel delta. Updates
  /// [snapIndicatorProvider] to match so [_SnapLine] shows/hides live.
  void _onDragUpdate(DragUpdateDetails d) {
    final rawDx = _dragDx + d.delta.dx;
    if (!ref.read(snapEnabledProvider)) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    final targets = collectSnapTargets(
      playhead: ref.read(playheadProvider),
      clips: widget.clips,
      clipStarts: widget.starts,
      audioClips: widget.audioClips,
      overlays: widget.overlays,
      excludeClipId: widget.clip.id,
    );
    final candidateStart = widget.starts[widget.index] + rawDx / widget.px;
    final snap = snapMove(
      start: candidateStart,
      duration: widget.clip.duration,
      targets: targets,
      thresholdSeconds: snapThresholdSeconds(widget.px),
    );
    if (snap == null) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    ref.read(snapIndicatorProvider.notifier).set(snap.lineAt);
    setState(() =>
        _dragDx = (snap.start - widget.starts[widget.index]) * widget.px);
  }

  void _commitReorder() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    final shift = _dragDx;
    setState(() => _dragDx = 0);
    if (shift.abs() < 1) return; // negligible movement — treat as a tap

    final myWidth = widget.clip.duration * widget.px;
    final myCenter = widget.starts[widget.index] * widget.px + shift + myWidth / 2;

    var newIndex = 0;
    for (var i = 0; i < widget.clips.length; i++) {
      if (i == widget.index) continue;
      final otherCenter =
          (widget.starts[i] + widget.clips[i].duration / 2) * widget.px;
      if (myCenter > otherCenter) newIndex++;
    }
    if (newIndex != widget.index) widget.onReorder(newIndex);
  }

  void _cancelDrag() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    setState(() => _dragDx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Body: tap to select, drag to reorder. Inset from the edges so the
        // trim handles get their own, non-overlapping hit area.
        Positioned.fill(
          left: _ClipSlot._handleWidth,
          right: _ClipSlot._handleWidth,
          child: Transform.translate(
            offset: Offset(_dragDx, 0),
            child: _ClipDragArea(
              onTap: widget.onTap,
              onDragStart: (_) => setState(() => _dragDx = 0),
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) => _commitReorder(),
              onDragCancel: _cancelDrag,
              child: _ClipBar(
                clip: widget.clip,
                widthPx: widget.clip.duration * widget.px,
                selected: widget.selected,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SplitHandle(axis: Axis.vertical, onDrag: widget.onTrimLeftDx),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child:
              SplitHandle(axis: Axis.vertical, onDrag: widget.onTrimRightDx),
        ),
      ],
    );
  }
}

/// An audio-lane clip bar: tap to select, drag the body to move its `start`,
/// drag the left/right edge handles to trim (adjusting `inPoint`/`outPoint` —
/// the left handle also shifts `start` so the bar's left edge tracks the
/// drag, same visual feel as trimming a video clip). A small close button
/// appears on the selected bar to delete it.
class _AudioClipSlot extends ConsumerStatefulWidget {
  const _AudioClipSlot({
    required this.clip,
    required this.index,
    required this.clips,
    required this.starts,
    required this.audioClips,
    required this.overlays,
    required this.px,
    required this.selected,
  });

  final AudioClip clip;
  final int index;

  /// The video track and overlay lane, so this clip's move/trim can also
  /// snap to their edges (cross-lane snapping — docs/TIMELINE-BEHAVIOR.md
  /// §7). [audioClips] is the whole audio lane (including this clip itself,
  /// which snapping excludes by id).
  final List<model.Clip> clips;
  final List<double> starts;
  final List<AudioClip> audioClips;
  final List<VideoOverlay> overlays;

  final double px;
  final bool selected;

  static const _handleWidth = 8.0;
  static const _minLength = 0.1;

  @override
  ConsumerState<_AudioClipSlot> createState() => _AudioClipSlotState();
}

class _AudioClipSlotState extends ConsumerState<_AudioClipSlot> {
  double _dragDx = 0;

  AudioClips get _notifier => ref.read(audioClipsProvider.notifier);

  void _select() =>
      ref.read(selectedAudioClipProvider.notifier).set(widget.clip.id);

  List<double> _snapTargets({String? excludeAudioClipId}) =>
      collectSnapTargets(
        playhead: ref.read(playheadProvider),
        clips: widget.clips,
        clipStarts: widget.starts,
        audioClips: widget.audioClips,
        overlays: widget.overlays,
        excludeAudioClipId: excludeAudioClipId,
      );

  /// Live-preview drag update: magnetizes [_dragDx] to the nearest snap
  /// target (tested on both of the clip's edges) when snapping is on,
  /// otherwise just accumulates the raw pixel delta.
  void _onDragUpdate(DragUpdateDetails d) {
    final rawDx = _dragDx + d.delta.dx;
    if (!ref.read(snapEnabledProvider)) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    final snap = snapMove(
      start: widget.clip.start + rawDx / widget.px,
      duration: widget.clip.duration,
      targets: _snapTargets(excludeAudioClipId: widget.clip.id),
      thresholdSeconds: snapThresholdSeconds(widget.px),
    );
    if (snap == null) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    ref.read(snapIndicatorProvider.notifier).set(snap.lineAt);
    setState(() => _dragDx = (snap.start - widget.clip.start) * widget.px);
  }

  void _commitMove() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    final shift = _dragDx;
    setState(() => _dragDx = 0);
    if (shift.abs() < 1) return; // negligible movement — treat as a tap
    final newStart =
        (widget.clip.start + shift / widget.px).clamp(0.0, double.infinity);
    _notifier.update(widget.index, widget.clip.copyWith(start: newStart));
  }

  void _cancelDrag() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    setState(() => _dragDx = 0);
  }

  void _trimLeft(double dx) {
    final deltaSeconds = dx / widget.px;
    final c = widget.clip;
    var newIn = (c.inPoint + deltaSeconds).clamp(0.0, c.sourceDuration);
    if (c.outPoint - newIn < _AudioClipSlot._minLength) {
      newIn = (c.outPoint - _AudioClipSlot._minLength).clamp(0.0, c.sourceDuration);
    }
    var actualDelta = newIn - c.inPoint;
    var newStart = (c.start + actualDelta).clamp(0.0, double.infinity);

    if (ref.read(snapEnabledProvider)) {
      final snapped = snapTime(newStart,
          _snapTargets(excludeAudioClipId: c.id), snapThresholdSeconds(widget.px));
      ref.read(snapIndicatorProvider.notifier).set(snapped);
      if (snapped != null) {
        final candidateStart = snapped.clamp(0.0, double.infinity);
        final candidateDelta = candidateStart - c.start;
        final candidateIn =
            (c.inPoint + candidateDelta).clamp(0.0, c.sourceDuration);
        if (c.outPoint - candidateIn >= _AudioClipSlot._minLength) {
          newIn = candidateIn;
          actualDelta = candidateDelta;
          newStart = candidateStart;
        }
      }
    } else {
      ref.read(snapIndicatorProvider.notifier).set(null);
    }

    _notifier.update(widget.index, c.copyWith(inPoint: newIn, start: newStart));
  }

  void _trimRight(double dx) {
    final deltaSeconds = dx / widget.px;
    final c = widget.clip;
    var newOut = (c.outPoint + deltaSeconds).clamp(0.0, c.sourceDuration);
    if (newOut - c.inPoint < _AudioClipSlot._minLength) {
      newOut = (c.inPoint + _AudioClipSlot._minLength).clamp(0.0, c.sourceDuration);
    }

    if (ref.read(snapEnabledProvider)) {
      final rawEnd = c.start + (newOut - c.inPoint);
      final snapped = snapTime(rawEnd,
          _snapTargets(excludeAudioClipId: c.id), snapThresholdSeconds(widget.px));
      ref.read(snapIndicatorProvider.notifier).set(snapped);
      if (snapped != null) {
        final candidateOut =
            (c.inPoint + (snapped - c.start)).clamp(0.0, c.sourceDuration);
        if (candidateOut - c.inPoint >= _AudioClipSlot._minLength) {
          newOut = candidateOut;
        }
      }
    } else {
      ref.read(snapIndicatorProvider.notifier).set(null);
    }

    _notifier.update(widget.index, c.copyWith(outPoint: newOut));
  }

  void _delete() {
    _notifier.removeAt(widget.index);
    ref.read(selectedAudioClipProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          left: _AudioClipSlot._handleWidth,
          right: _AudioClipSlot._handleWidth,
          child: Transform.translate(
            offset: Offset(_dragDx, 0),
            child: _ClipDragArea(
              onTap: _select,
              onDragStart: (_) => setState(() => _dragDx = 0),
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) => _commitMove(),
              onDragCancel: _cancelDrag,
              child: _AudioClipBar(
                clip: widget.clip,
                widthPx: widget.clip.duration * widget.px,
                selected: widget.selected,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SplitHandle(axis: Axis.vertical, onDrag: _trimLeft),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: SplitHandle(axis: Axis.vertical, onDrag: _trimRight),
        ),
        if (widget.selected)
          Positioned(
            right: _AudioClipSlot._handleWidth + 2,
            top: 2,
            child: GestureDetector(
              onTap: _delete,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// An audio clip's bar background: a blue CapCut-style bar with a waveform
/// across its width (reusing [audioClipWaveformProvider], which shares the
/// engine's on-disk waveform cache with the main track's clip bars), the
/// filename label (in a small translucent-black chip, top-left), and the
/// selected/accent border. Falls back to a plain colour bar while the
/// waveform is loading or unavailable, same spirit as [_ClipBar].
class _AudioClipBar extends ConsumerWidget {
  const _AudioClipBar(
      {required this.clip, required this.widthPx, required this.selected});

  final AudioClip clip;
  final double widthPx;
  final bool selected;

  static const _barColor = Color(0xFF26407A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waveformWidth = waveformWidthForBarWidth(widthPx);
    final wave = ref
        .watch(audioClipWaveformProvider(
            clip, waveformWidth, kWaveformHeight * 2))
        .value;

    return Container(
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: _barColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (wave != null)
            Center(
              child: Image.file(
                File(wave),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(left: 6, top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(clip.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An overlay-lane bar: tap to select, drag the body to move its `startTime`,
/// drag the left/right edge handles to trim (adjusting `inPoint`/`outPoint` —
/// the left handle also shifts `startTime` so the bar's left edge tracks the
/// drag). Exactly [_AudioClipSlot]'s behaviour, applied to [VideoOverlay]'s
/// fields instead of [AudioClip]'s. A small close button appears on the
/// selected bar to delete it.
class _VideoOverlaySlot extends ConsumerStatefulWidget {
  const _VideoOverlaySlot({
    required this.overlay,
    required this.index,
    required this.clips,
    required this.starts,
    required this.audioClips,
    required this.overlays,
    required this.px,
    required this.selected,
  });

  final VideoOverlay overlay;
  final int index;

  /// The video track and audio lane, so this overlay's move/trim can also
  /// snap to their edges (cross-lane snapping — docs/TIMELINE-BEHAVIOR.md
  /// §7). [overlays] is the whole overlay lane (including this overlay
  /// itself, which snapping excludes by id).
  final List<model.Clip> clips;
  final List<double> starts;
  final List<AudioClip> audioClips;
  final List<VideoOverlay> overlays;

  final double px;
  final bool selected;

  static const _handleWidth = 8.0;
  static const _minLength = 0.1;

  @override
  ConsumerState<_VideoOverlaySlot> createState() => _VideoOverlaySlotState();
}

class _VideoOverlaySlotState extends ConsumerState<_VideoOverlaySlot> {
  double _dragDx = 0;

  VideoOverlays get _notifier => ref.read(videoOverlaysProvider.notifier);

  void _select() =>
      ref.read(selectedVideoOverlayProvider.notifier).set(widget.overlay.id);

  List<double> _snapTargets({String? excludeOverlayId}) => collectSnapTargets(
        playhead: ref.read(playheadProvider),
        clips: widget.clips,
        clipStarts: widget.starts,
        audioClips: widget.audioClips,
        overlays: widget.overlays,
        excludeOverlayId: excludeOverlayId,
      );

  /// Live-preview drag update: magnetizes [_dragDx] to the nearest snap
  /// target (tested on both of the overlay's edges) when snapping is on,
  /// otherwise just accumulates the raw pixel delta.
  void _onDragUpdate(DragUpdateDetails d) {
    final rawDx = _dragDx + d.delta.dx;
    if (!ref.read(snapEnabledProvider)) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    final snap = snapMove(
      start: widget.overlay.startTime + rawDx / widget.px,
      duration: widget.overlay.duration,
      targets: _snapTargets(excludeOverlayId: widget.overlay.id),
      thresholdSeconds: snapThresholdSeconds(widget.px),
    );
    if (snap == null) {
      ref.read(snapIndicatorProvider.notifier).set(null);
      setState(() => _dragDx = rawDx);
      return;
    }
    ref.read(snapIndicatorProvider.notifier).set(snap.lineAt);
    setState(
        () => _dragDx = (snap.start - widget.overlay.startTime) * widget.px);
  }

  void _commitMove() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    final shift = _dragDx;
    setState(() => _dragDx = 0);
    if (shift.abs() < 1) return; // negligible movement — treat as a tap
    final newStart = (widget.overlay.startTime + shift / widget.px)
        .clamp(0.0, double.infinity);
    _notifier.update(
        widget.index, widget.overlay.copyWith(startTime: newStart));
  }

  void _cancelDrag() {
    ref.read(snapIndicatorProvider.notifier).set(null);
    setState(() => _dragDx = 0);
  }

  void _trimLeft(double dx) {
    final deltaSeconds = dx / widget.px;
    final o = widget.overlay;
    var newIn = (o.inPoint + deltaSeconds).clamp(0.0, o.sourceDuration);
    if (o.outPoint - newIn < _VideoOverlaySlot._minLength) {
      newIn = (o.outPoint - _VideoOverlaySlot._minLength)
          .clamp(0.0, o.sourceDuration);
    }
    var actualDelta = newIn - o.inPoint;
    var newStart = (o.startTime + actualDelta).clamp(0.0, double.infinity);

    if (ref.read(snapEnabledProvider)) {
      final snapped = snapTime(newStart,
          _snapTargets(excludeOverlayId: o.id), snapThresholdSeconds(widget.px));
      ref.read(snapIndicatorProvider.notifier).set(snapped);
      if (snapped != null) {
        final candidateStart = snapped.clamp(0.0, double.infinity);
        final candidateDelta = candidateStart - o.startTime;
        final candidateIn =
            (o.inPoint + candidateDelta).clamp(0.0, o.sourceDuration);
        if (o.outPoint - candidateIn >= _VideoOverlaySlot._minLength) {
          newIn = candidateIn;
          actualDelta = candidateDelta;
          newStart = candidateStart;
        }
      }
    } else {
      ref.read(snapIndicatorProvider.notifier).set(null);
    }

    _notifier.update(
        widget.index, o.copyWith(inPoint: newIn, startTime: newStart));
  }

  void _trimRight(double dx) {
    final deltaSeconds = dx / widget.px;
    final o = widget.overlay;
    var newOut = (o.outPoint + deltaSeconds).clamp(0.0, o.sourceDuration);
    if (newOut - o.inPoint < _VideoOverlaySlot._minLength) {
      newOut = (o.inPoint + _VideoOverlaySlot._minLength)
          .clamp(0.0, o.sourceDuration);
    }

    if (ref.read(snapEnabledProvider)) {
      final rawEnd = o.startTime + (newOut - o.inPoint);
      final snapped = snapTime(rawEnd,
          _snapTargets(excludeOverlayId: o.id), snapThresholdSeconds(widget.px));
      ref.read(snapIndicatorProvider.notifier).set(snapped);
      if (snapped != null) {
        final candidateOut =
            (o.inPoint + (snapped - o.startTime)).clamp(0.0, o.sourceDuration);
        if (candidateOut - o.inPoint >= _VideoOverlaySlot._minLength) {
          newOut = candidateOut;
        }
      }
    } else {
      ref.read(snapIndicatorProvider.notifier).set(null);
    }

    _notifier.update(widget.index, o.copyWith(outPoint: newOut));
  }

  void _delete() {
    _notifier.removeAt(widget.index);
    ref.read(selectedVideoOverlayProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          left: _VideoOverlaySlot._handleWidth,
          right: _VideoOverlaySlot._handleWidth,
          child: Transform.translate(
            offset: Offset(_dragDx, 0),
            child: _ClipDragArea(
              onTap: _select,
              onDragStart: (_) => setState(() => _dragDx = 0),
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) => _commitMove(),
              onDragCancel: _cancelDrag,
              child: _VideoOverlayBar(
                overlay: widget.overlay,
                widthPx: widget.overlay.duration * widget.px,
                selected: widget.selected,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SplitHandle(axis: Axis.vertical, onDrag: _trimLeft),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: SplitHandle(axis: Axis.vertical, onDrag: _trimRight),
        ),
        if (widget.selected)
          Positioned(
            right: _VideoOverlaySlot._handleWidth + 2,
            top: 2,
            child: GestureDetector(
              onTap: _delete,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// A video overlay's bar background: a violet, CapCut-style bar with a PiP
/// icon and the filename label (in a small translucent-black chip), plus the
/// selected/accent border — same visual idiom as [_AudioClipBar] but without
/// a waveform (this lane is video, not audio; a filmstrip would need the
/// same thumbnail-extraction machinery [_ClipBar] uses, left for later).
class _VideoOverlayBar extends StatelessWidget {
  const _VideoOverlayBar(
      {required this.overlay, required this.widthPx, required this.selected});

  final VideoOverlay overlay;
  final double widthPx;
  final bool selected;

  static const _barColor = Color(0xFF5B3B8C);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: _barColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 7),
                child: Icon(Icons.picture_in_picture_alt_outlined,
                    size: 12, color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(overlay.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
