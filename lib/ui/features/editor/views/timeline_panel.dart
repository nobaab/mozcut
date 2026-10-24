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
import '../../../core/app_colors.dart';
import '../../../core/widgets/split_handle.dart';
import '../view_models/audio_clips_view_model.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/media_import.dart';
import '../view_models/thumbnails_view_model.dart';

/// The timeline: a fixed track-header gutter on the left, then a horizontally
/// scrolling ruler + video track + audio lane. Clips sit end to end on one
/// video track, sized by the zoom; audio clips float freely on the lane below,
/// positioned by their own `start`. A playhead line tracks the preview.
/// Modelled on CapCut. Also accepts drag-and-drop of media files, routed the
/// same way as the media browser's Import button (see `importMediaPaths`).
class TimelinePanel extends ConsumerStatefulWidget {
  const TimelinePanel({super.key});

  static const _headerWidth = 150.0;
  static const _rulerHeight = 24.0;
  static const _videoLaneHeight = 64.0;
  static const _laneGap = 6.0;
  static const _audioLaneHeight = 48.0;

  @override
  ConsumerState<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends ConsumerState<TimelinePanel> {
  bool _dragging = false;

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

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
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
  /// plain two-finger scroll pans. The horizontal component of a plain
  /// scroll is already handled by `SingleChildScrollView`'s own trackpad
  /// drag support, so only the vertical component is applied here — that
  /// way a straight up/down swipe also scrubs the timeline sideways,
  /// matching CapCut.
  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final scaleRatio = event.scale / _panZoomLastScale;
    _panZoomLastScale = event.scale;
    final pinching = (scaleRatio - 1.0).abs() > 0.0005;
    if (pinching) {
      _zoomBy(factor: scaleRatio, cursorDx: event.localPosition.dx);
      return;
    }
    if (_zoomModifierDown()) {
      // Ctrl/Cmd + two-finger scroll (no pinch): drive the zoom off the
      // vertical pan delta instead of panning.
      _zoomBy(
        factor: math.exp(-event.panDelta.dy * 0.01),
        cursorDx: event.localPosition.dx,
      );
      return;
    }
    _panBy(event.panDelta.dy);
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

  Widget _buildTimeline(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final px = ref.watch(timelineZoomProvider);
    final audioClips = ref.watch(audioClipsProvider);
    final selectedAudioId = ref.watch(selectedAudioClipProvider);

    final total = state.totalDuration;
    // Cumulative start offset of each clip on the timeline.
    final starts = <double>[];
    var acc = 0.0;
    for (final c in state.clips) {
      starts.add(acc);
      acc += c.duration;
    }

    // The audio lane's clips are positioned independently of the video
    // track, so the content area needs to be wide enough for whichever of
    // the two extends further right.
    var audioEnd = 0.0;
    for (final a in audioClips) {
      audioEnd = math.max(audioEnd, a.start + a.duration);
    }
    final timelineSeconds = math.max(total, audioEnd);

    // Playhead in timeline seconds, derived from the preview position within
    // the selected clip.
    double playheadT = 0;
    final selIdx = state.selectedIndex;
    if (selIdx >= 0) {
      final clip = state.clips[selIdx];
      final within = (ref.watch(playheadProvider) - clip.inPoint)
          .clamp(0.0, clip.duration);
      playheadT = starts[selIdx] + within;
    }

    return Container(
      color: AppColors.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: TimelinePanel._headerWidth, child: _trackHeader()),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
          Expanded(
            child: state.clips.isEmpty && audioClips.isEmpty
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
                      onPointerSignal: _handlePointerSignal,
                      onPointerPanZoomStart: (_) => _panZoomLastScale = 1.0,
                      onPointerPanZoomUpdate: _handlePanZoomUpdate,
                      child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentW.toDouble(),
                        child: Column(
                          children: [
                            // The ruler is a dedicated scrub strip: click or
                            // drag along it to move the playhead.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => scrub(d.localPosition.dx),
                              onHorizontalDragUpdate: (d) =>
                                  scrub(d.localPosition.dx),
                              child:
                                  _Ruler(seconds: timelineSeconds, px: px),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // The one video track lane.
                                        SizedBox(
                                          height:
                                              TimelinePanel._videoLaneHeight,
                                          width: contentW.toDouble(),
                                          child: Stack(
                                            children: [
                                              // Empty track space: click to
                                              // scrub (clips above handle
                                              // their own taps/drags and take
                                              // priority).
                                              Positioned.fill(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTapDown: (d) =>
                                                      scrub(d.localPosition.dx),
                                                ),
                                              ),
                                              for (var i = 0;
                                                  i < state.clips.length;
                                                  i++)
                                                Positioned(
                                                  key: ValueKey(
                                                      state.clips[i].id),
                                                  left: starts[i] * px,
                                                  width:
                                                      state.clips[i].duration *
                                                          px,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: _ClipSlot(
                                                    clip: state.clips[i],
                                                    index: i,
                                                    clips: state.clips,
                                                    starts: starts,
                                                    px: px,
                                                    selected: state.clips[i]
                                                            .id ==
                                                        state.selectedId,
                                                    onTap: () => ref
                                                        .read(editorProvider
                                                            .notifier)
                                                        .select(
                                                            state.clips[i].id),
                                                    onReorder: (newIndex) =>
                                                        ref
                                                            .read(
                                                                editorProvider
                                                                    .notifier)
                                                            .reorder(
                                                                i, newIndex),
                                                    onTrimLeftDx: (dx) {
                                                      final c = ref
                                                          .read(editorProvider)
                                                          .clips[i];
                                                      ref
                                                          .read(editorProvider
                                                              .notifier)
                                                          .setTrim(c.id,
                                                              inPoint: c
                                                                      .inPoint +
                                                                  dx / px);
                                                    },
                                                    onTrimRightDx: (dx) {
                                                      final c = ref
                                                          .read(editorProvider)
                                                          .clips[i];
                                                      ref
                                                          .read(editorProvider
                                                              .notifier)
                                                          .setTrim(c.id,
                                                              outPoint: c
                                                                      .outPoint +
                                                                  dx / px);
                                                    },
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                            height: TimelinePanel._laneGap),
                                        // The audio lane: clips float freely,
                                        // positioned by their own `start`
                                        // (unlike the video track, they don't
                                        // shift each other).
                                        SizedBox(
                                          height:
                                              TimelinePanel._audioLaneHeight,
                                          width: contentW.toDouble(),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
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
                                                  left: audioClips[i].start *
                                                      px,
                                                  width:
                                                      audioClips[i].duration *
                                                          px,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: _AudioClipSlot(
                                                    clip: audioClips[i],
                                                    index: i,
                                                    px: px,
                                                    selected:
                                                        audioClips[i].id ==
                                                            selectedAudioId,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Playhead, spanning both lanes.
                                  Positioned(
                                    left: playheadT * px,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                        width: 2, color: AppColors.accent),
                                  ),
                                ],
                              ),
                            ),
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

  Widget _trackHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: TimelinePanel._rulerHeight),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.well,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.image_outlined,
                      size: 16, color: Colors.white.withValues(alpha: 0.4)),
                ),
                const SizedBox(width: 6),
                const Text('Cover', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _hdrIcon(Icons.play_arrow),
                _hdrIcon(Icons.lock_outline),
                _hdrIcon(Icons.visibility_outlined),
                _hdrIcon(Icons.volume_up_outlined),
                _hdrIcon(Icons.more_horiz),
              ],
            ),
          ),
          const SizedBox(height: TimelinePanel._laneGap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.audiotrack_outlined,
                    size: 15, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                const Text('Audio', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      );

  Widget _hdrIcon(IconData icon) =>
      Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.5));
}

class _Ruler extends StatelessWidget {
  const _Ruler({required this.seconds, required this.px});
  final double seconds;
  final double px;

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
    final marks = <Widget>[];
    for (var t = 0; t <= seconds + step; t += step) {
      marks.add(Positioned(
        left: t * px,
        top: 4,
        child: Text(_fmt(t),
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
      ));
    }
    return SizedBox(
      height: TimelinePanel._rulerHeight,
      child: Stack(children: marks),
    );
  }

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
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
  var selIdx = state.selectedIndex;
  if (selIdx < 0) {
    final idx = _clipIndexAt(state.clips, starts, localDxSeconds);
    if (idx < 0) return;
    editor.select(state.clips[idx].id);
    selIdx = idx;
  }
  final clip = state.clips[selIdx];
  final within =
      (localDxSeconds - starts[selIdx]).clamp(0.0, clip.duration);
  ref.read(playheadProvider.notifier).set(clip.inPoint + within);
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

/// A clip's bar background: a filmstrip of real frames across its width with
/// a waveform strip along the bottom (CapCut-style), the filename label, and
/// the selected/accent border. Thumbnails/waveform are fetched through
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
          // Accent tab + filename label, on top of everything, with a scrim
          // behind the text so it stays legible over bright frames.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: double.infinity,
                color: AppColors.accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(clip.fileName,
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

/// A clip bar on the track: tap to select, drag the body to reorder, drag the
/// left/right edge handles to trim. The body drag only gives visual feedback
/// (a translation) while dragging; the reorder itself commits once on
/// release, based on where the bar's centre ends up relative to its
/// neighbours' centres.
class _ClipSlot extends StatefulWidget {
  const _ClipSlot({
    required this.clip,
    required this.index,
    required this.clips,
    required this.starts,
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
  State<_ClipSlot> createState() => _ClipSlotState();
}

class _ClipSlotState extends State<_ClipSlot> {
  double _dragDx = 0;

  void _commitReorder() {
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onHorizontalDragStart: (_) => setState(() => _dragDx = 0),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _dragDx += d.delta.dx),
              onHorizontalDragEnd: (_) => _commitReorder(),
              onHorizontalDragCancel: () => setState(() => _dragDx = 0),
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
    required this.px,
    required this.selected,
  });

  final AudioClip clip;
  final int index;
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

  void _commitMove() {
    final shift = _dragDx;
    setState(() => _dragDx = 0);
    if (shift.abs() < 1) return; // negligible movement — treat as a tap
    final newStart =
        (widget.clip.start + shift / widget.px).clamp(0.0, double.infinity);
    _notifier.update(widget.index, widget.clip.copyWith(start: newStart));
  }

  void _trimLeft(double dx) {
    final deltaSeconds = dx / widget.px;
    final c = widget.clip;
    var newIn = (c.inPoint + deltaSeconds).clamp(0.0, c.sourceDuration);
    if (c.outPoint - newIn < _AudioClipSlot._minLength) {
      newIn = (c.outPoint - _AudioClipSlot._minLength).clamp(0.0, c.sourceDuration);
    }
    final actualDelta = newIn - c.inPoint;
    _notifier.update(
        widget.index,
        c.copyWith(
            inPoint: newIn,
            start: (c.start + actualDelta).clamp(0.0, double.infinity)));
  }

  void _trimRight(double dx) {
    final deltaSeconds = dx / widget.px;
    final c = widget.clip;
    var newOut = (c.outPoint + deltaSeconds).clamp(0.0, c.sourceDuration);
    if (newOut - c.inPoint < _AudioClipSlot._minLength) {
      newOut = (c.inPoint + _AudioClipSlot._minLength).clamp(0.0, c.sourceDuration);
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _select,
              onHorizontalDragStart: (_) => setState(() => _dragDx = 0),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _dragDx += d.delta.dx),
              onHorizontalDragEnd: (_) => _commitMove(),
              onHorizontalDragCancel: () => setState(() => _dragDx = 0),
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

/// An audio clip's bar background: a waveform across its width (reusing
/// [audioClipWaveformProvider], which shares the engine's on-disk waveform
/// cache with the main track's clip bars), the filename label, and the
/// selected/accent border. Falls back to a plain colour bar while the
/// waveform is loading or unavailable, same spirit as [_ClipBar].
class _AudioClipBar extends ConsumerWidget {
  const _AudioClipBar(
      {required this.clip, required this.widthPx, required this.selected});

  final AudioClip clip;
  final double widthPx;
  final bool selected;

  static const _barColor = Color(0xFF2D4430);

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
              Container(
                width: 4,
                height: double.infinity,
                color: AppColors.accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(clip.fileName,
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
