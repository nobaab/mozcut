import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';

/// The strip of tools above the timeline, modelled on CapCut: edit tools on the
/// left, zoom on the right. Split/Delete are wired; the rest are placeholders.
class TimelineToolbar extends ConsumerWidget {
  const TimelineToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.read(editorProvider.notifier);
    final hasSel = ref.watch(editorProvider.select((s) => s.selected != null));
    final zoom = ref.watch(timelineZoomProvider);

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _tool(context, Icons.near_me, 'Select'),
          _divider(),
          _tool(context, Icons.undo, 'Undo'),
          _tool(context, Icons.redo, 'Redo'),
          _divider(),
          _tool(context, Icons.content_cut, 'Split',
              onTap: hasSel
                  ? () => editor.splitSelectedAt(ref.read(playheadProvider))
                  : null),
          _tool(context, Icons.delete_outline, 'Delete',
              onTap: hasSel ? editor.removeSelected : null),
          _tool(context, Icons.crop, 'Crop'),
          _tool(context, Icons.ac_unit, 'Freeze frame'),
          _tool(context, Icons.flip, 'Mirror'),
          _tool(context, Icons.rotate_right, 'Rotate'),
          _divider(),
          _tool(context, Icons.auto_fix_high, 'Keyframe'),
          const Spacer(),
          _tool(context, Icons.mic_none, 'Record voiceover'),
          _tool(context, Icons.link, 'Link'),
          _divider(),
          _tool(context, Icons.zoom_out, 'Zoom out',
              onTap: ref.read(timelineZoomProvider.notifier).zoomOut),
          SizedBox(
            width: 120,
            child: Slider(
              value: zoom,
              min: 6,
              max: 240,
              onChanged: ref.read(timelineZoomProvider.notifier).set,
            ),
          ),
          _tool(context, Icons.zoom_in, 'Zoom in',
              onTap: ref.read(timelineZoomProvider.notifier).zoomIn),
        ],
      ),
    );
  }

  Widget _tool(BuildContext context, IconData icon, String tip,
      {VoidCallback? onTap}) {
    // A null onTap for a placeholder still shows a "coming soon" note; a null
    // onTap for a real-but-disabled action (no selection) greys it out.
    final isPlaceholder = tip != 'Split' && tip != 'Delete';
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap ??
          (isPlaceholder
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$tip — coming soon')))
              : null),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.line,
      );
}
