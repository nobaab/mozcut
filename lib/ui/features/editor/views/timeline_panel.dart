import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';

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
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentW.toDouble(),
                        child: Column(
                          children: [
                            _Ruler(seconds: total, px: px),
                            Expanded(
                              child: Stack(
                                children: [
                                  // The one video track lane.
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      height: 64,
                                      child: Stack(
                                        children: [
                                          for (var i = 0;
                                              i < state.clips.length;
                                              i++)
                                            Positioned(
                                              left: starts[i] * px,
                                              width: state.clips[i].duration *
                                                  px,
                                              top: 0,
                                              bottom: 0,
                                              child: _ClipBar(
                                                name: state.clips[i].fileName,
                                                selected: state.clips[i].id ==
                                                    state.selectedId,
                                                onTap: () => ref
                                                    .read(editorProvider
                                                        .notifier)
                                                    .select(
                                                        state.clips[i].id),
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

class _ClipBar extends StatelessWidget {
  const _ClipBar(
      {required this.name, required this.selected, required this.onTap});
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2A3550),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 4,
              color: AppColors.accent.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}
