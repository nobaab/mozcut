import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/editor_view_model.dart';
import 'editor_shortcuts.dart';
import 'export_dialog.dart';
import '../view_models/text_overlays_view_model.dart';

/// The top bar, modelled on CapCut: project name in the middle, and the row of
/// actions on the right (Shortcuts, Pro, Share, Export). Back to the launcher is
/// on the left — our own addition, since MozCut has a project launcher.
class EditorTitleBar extends ConsumerWidget implements PreferredSizeWidget {
  const EditorTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(appProvider)?.name ?? 'MozCut';
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
          VIconButton(
            icon: Icons.arrow_back,
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
          VIconButton(
              icon: Icons.grid_view,
              tooltip: 'Layout',
              onPressed: () => _soon(context, 'Layout')),
          const SizedBox(width: 4),
          VButton(
              label: 'Shortcuts',
              icon: Icons.keyboard_outlined,
              onPressed: () => showEditorShortcutsDialog(context)),
          const SizedBox(width: 8),
          VButton(
              label: 'Share',
              icon: Icons.ios_share,
              onPressed: () => _soon(context, 'Share')),
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
            VButton(
              label: 'Export',
              icon: Icons.file_upload_outlined,
              variant: VButtonVariant.primary,
              onPressed: hasClips ? () => _export(context, ref) : null,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _soon(BuildContext context, String what) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$what — coming soon')));

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final settings = await showExportDialog(context);
    if (settings == null) return;
    if (!context.mounted) return;
    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose where to export');
    if (dir == null) return;
    final path = '$dir/mozcut_export_${DateTime.now().millisecondsSinceEpoch}'
        '.${settings.fileExtension}';
    final engine = ref.read(engineProvider);
    final clips = ref.read(editorProvider).clips;
    final textOverlays = ref.read(textOverlaysProvider);
    final progress = ref.read(exportProgressProvider.notifier);
    progress.set(0);
    try {
      await engine.export(
          clips: clips,
          outputPath: path,
          settings: settings,
          textOverlays: textOverlays,
          onProgress: progress.set);
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
