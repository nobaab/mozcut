import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/clip.dart' as model;
import '../../../core/app_colors.dart';
import '../../../core/widgets/split_handle.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/thumbnails_view_model.dart';

/// The timeline: a fixed track-header gutter on the left, then a horizontally
/// scrolling ruler + track lane. Clips sit end to end on one video track, sized
/// by the zoom. A playhead line tracks the preview. Modelled on CapCut.
class TimelinePanel extends ConsumerWidget {
  const TimelinePanel({super.key});

  static const _headerWidth = 150.0;
  static const _rulerHeight = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final px = ref.watch(timelineZoomProvider);

    final total = state.totalDuration;
    // Cumulative start offset of each clip on the timeline.
    final starts = <double>[];
    var acc = 0.0;
    for (final c in state.clips) {
      starts.add(acc);
      acc += c.duration;
    }

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
          SizedBox(width: _headerWidth, child: _trackHeader()),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
          Expanded(
            child: state.clips.isEmpty
                ? Center(
                    child: Text('Imported clips show up here',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25))),
                  )
                : LayoutBuilder(builder: (context, c) {
                    final contentW =
                        (total * px + 80).clamp(c.maxWidth, double.infinity);
                    void scrub(double localDx) => _scrubToTimelineSeconds(
                        ref, state, starts, localDx / px);
                    return SingleChildScrollView(
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
                              child: _Ruler(seconds: total, px: px),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  // The one video track lane.
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      height: 64,
                                      width: contentW.toDouble(),
                                      child: Stack(
                                        children: [
                                          // Empty track space: click to scrub
                                          // (clips above handle their own
                                          // taps/drags and take priority).
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
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
                                              width: state.clips[i].duration *
                                                  px,
                                              top: 0,
                                              bottom: 0,
                                              child: _ClipSlot(
                                                clip: state.clips[i],
                                                index: i,
                                                clips: state.clips,
                                                starts: starts,
                                                px: px,
                                                selected: state.clips[i].id ==
                                                    state.selectedId,
                                                onTap: () => ref
                                                    .read(editorProvider
                                                        .notifier)
                                                    .select(
                                                        state.clips[i].id),
                                                onReorder: (newIndex) => ref
                                                    .read(editorProvider
                                                        .notifier)
                                                    .reorder(i, newIndex),
                                                onTrimLeftDx: (dx) {
                                                  final c = ref
                                                      .read(editorProvider)
                                                      .clips[i];
                                                  ref
                                                      .read(editorProvider
                                                          .notifier)
                                                      .setTrim(c.id,
                                                          inPoint: c.inPoint +
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
                                  ),
                                  // Playhead
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
          const SizedBox(height: _rulerHeight),
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
    final count = thumbnailCountForWidth(widthPx);
    final waveformWidth = waveformWidthForBarWidth(widthPx);
    final thumbs = ref
        .watch(clipFilmstripProvider(clip, count, kFilmstripThumbHeight))
        .value;
    final wave = ref
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
