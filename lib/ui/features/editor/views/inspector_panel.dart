import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../view_models/editor_view_model.dart';

/// The inspector: details and actions for the selected clip. Concat's right-hand
/// pane. As features land (effects, text, grading) their controls live here.
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
    final editor = ref.read(editorProvider.notifier);

    return Panel(
      title: 'Inspector',
      child: clip == null
          ? Center(
              child: Text('Select a clip to see its details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
            )
          : ListView(
              children: [
                _section('Source'),
                _row('File', clip.fileName),
                _row('Length', '${clip.sourceDuration.toStringAsFixed(2)}s'),
                const SizedBox(height: 16),
                _section('Trim'),
                _row('In', '${clip.inPoint.toStringAsFixed(2)}s'),
                _row('Out', '${clip.outPoint.toStringAsFixed(2)}s'),
                _row('Duration', '${clip.duration.toStringAsFixed(2)}s'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.first_page, size: 16),
                        label: const Text('Set In'),
                        onPressed: () => editor.trimSelected(
                            inPoint: ref.read(playheadProvider)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.last_page, size: 16),
                        label: const Text('Set Out'),
                        onPressed: () => editor.trimSelected(
                            outPoint: ref.read(playheadProvider)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section('Edit'),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_cut, size: 16),
                  label: const Text('Split at playhead'),
                  onPressed: () =>
                      editor.splitSelectedAt(ref.read(playheadProvider)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete clip'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent),
                  onPressed: editor.removeSelected,
                ),
              ],
            ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: AppColors.accent)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45))),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}
