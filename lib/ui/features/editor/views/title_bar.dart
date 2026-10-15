import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../core/app_colors.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/editor_view_model.dart';

/// The top bar, modelled on CapCut: project name in the middle, and the row of
/// actions on the right (Shortcuts, Pro, Share, Export). Back to the launcher is
/// on the left — our own addition, since Vidkaat has a project launcher.
class EditorTitleBar extends ConsumerWidget implements PreferredSizeWidget {
  const EditorTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(appProvider)?.name ?? 'Vidkaat';
    final progress = ref.watch(exportProgressProvider);
    final exporting = progress != null;
    final hasClips = ref.watch(editorProvider).clips.isNotEmpty;

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Save & back to projects',
            onPressed: exporting
                ? null
                : () => ref.read(appProvider.notifier).closeToStart(),
          ),
          const Spacer(),
          Text(name,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          _ghost(context, Icons.grid_view, 'Layout'),
          _pill(context, Icons.keyboard_outlined, 'Shortcuts'),
          const SizedBox(width: 8),
          _pill(context, Icons.ios_share, 'Share'),
          const SizedBox(width: 8),
          if (exporting)
            SizedBox(
              width: 150,
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: progress)),
                  const SizedBox(width: 6),
                  Text('${(progress * 100).round()}%',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Export'),
              onPressed: hasClips ? () => _export(context, ref) : null,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _ghost(BuildContext context, IconData icon, String tip) => IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tip,
        onPressed: () => _soon(context, tip),
      );

  Widget _pill(BuildContext context, IconData icon, String label) =>
      TextButton.icon(
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: () => _soon(context, label),
      );

  void _soon(BuildContext context, String what) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$what — coming soon')));

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose where to export');
    if (dir == null) return;
    final path =
        '$dir/vidkaat_export_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final engine = ref.read(engineProvider);
    final clips = ref.read(editorProvider).clips;
    final progress = ref.read(exportProgressProvider.notifier);
    progress.set(0);
    try {
      await engine.export(
          clips: clips, outputPath: path, onProgress: progress.set);
      if (context.mounted) _snack(context, 'Exported to $path');
    } catch (e) {
      if (context.mounted) _snack(context, 'Export failed: $e');
    } finally {
      progress.set(null);
    }
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
}
