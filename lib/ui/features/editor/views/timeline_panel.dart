import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/clip.dart';
import '../view_models/editor_view_model.dart';

/// The timeline: each clip is a bar whose width is proportional to its trimmed
/// duration. Click a bar to select it (which loads it in the preview).
class TimelinePanel extends ConsumerWidget {
  const TimelinePanel({super.key});

  // Pixels per second of timeline. A zoom control can drive this later.
  static const double pxPerSecond = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    return Container(
      height: 120,
      color: const Color(0xFF131418),
      child: state.clips.isEmpty
          ? const Center(
              child: Text(
                'Timeline — imported clips show up here',
                style: TextStyle(color: Colors.white24),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final clip in state.clips)
                    _ClipBar(
                      clip: clip,
                      selected: clip.id == state.selectedId,
                      onTap: () =>
                          ref.read(editorProvider.notifier).select(clip.id),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ClipBar extends StatelessWidget {
  const _ClipBar({
    required this.clip,
    required this.selected,
    required this.onTap,
  });

  final Clip clip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width =
        (clip.duration * TimelinePanel.pxPerSecond).clamp(48.0, 4000.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width.toDouble(),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0568FD) : const Color(0xFF2A2C34),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              clip.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '${clip.duration.toStringAsFixed(1)}s',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
