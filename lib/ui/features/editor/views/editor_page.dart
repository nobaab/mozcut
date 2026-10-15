import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/toolbar_button.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/editor_view_model.dart';
import 'preview_panel.dart';
import 'timeline_panel.dart';

class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _Toolbar(),
      body: const Column(
        children: [
          Expanded(child: PreviewPanel()),
          TimelinePanel(),
        ],
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final progress = ref.watch(exportProgressProvider);
    final hasSelection = state.selected != null;
    final exporting = progress != null;

    final projectName = ref.watch(appProvider)?.name ?? 'Vidkaat';

    return AppBar(
      backgroundColor: AppColors.surface,
      titleSpacing: 8,
      title: Row(
        children: [
          Tooltip(
            message: 'Save & back to projects',
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: exporting
                  ? null
                  : () => ref.read(appProvider.notifier).closeToStart(),
            ),
          ),
          Text(projectName,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(width: 20),
          ToolbarButton(
            icon: Icons.add,
            label: 'Import',
            onPressed: exporting ? null : () => _import(context, ref),
          ),
          ToolbarButton(
            icon: Icons.content_cut,
            label: 'Split',
            onPressed: hasSelection && !exporting
                ? () => ref
                    .read(editorProvider.notifier)
                    .splitSelectedAt(ref.read(playheadProvider))
                : null,
          ),
          ToolbarButton(
            icon: Icons.first_page,
            label: 'Set In',
            onPressed: hasSelection && !exporting
                ? () => ref
                    .read(editorProvider.notifier)
                    .trimSelected(inPoint: ref.read(playheadProvider))
                : null,
          ),
          ToolbarButton(
            icon: Icons.last_page,
            label: 'Set Out',
            onPressed: hasSelection && !exporting
                ? () => ref
                    .read(editorProvider.notifier)
                    .trimSelected(outPoint: ref.read(playheadProvider))
                : null,
          ),
          ToolbarButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: hasSelection && !exporting
                ? () => ref.read(editorProvider.notifier).removeSelected()
                : null,
          ),
          ToolbarButton(
            icon: Icons.save_outlined,
            label: 'Save',
            onPressed: exporting
                ? null
                : () async {
                    await ref.read(appProvider.notifier).saveCurrent();
                    if (context.mounted) _snack(context, 'Project saved');
                  },
          ),
          const Spacer(),
          if (exporting)
            SizedBox(
              width: 160,
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: progress)),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Export'),
              onPressed:
                  state.clips.isEmpty ? null : () => _export(context, ref),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // Non-sandboxed macOS app: skip file_picker's own entitlement checks.
    await FilePicker.skipEntitlementsChecks();
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'],
    );
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      try {
        await ref.read(editorProvider.notifier).addClip(path);
      } catch (e) {
        if (context.mounted) _snack(context, 'Could not import ${f.name}: $e');
      }
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    await FilePicker.skipEntitlementsChecks();
    // saveFile() wants the file bytes up front, but ffmpeg writes the output
    // itself — so we pick a destination folder and name the file ourselves.
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where to export',
    );
    if (dir == null) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$dir/vidkaat_export_$stamp.mp4';

    final engine = ref.read(engineProvider);
    final clips = ref.read(editorProvider).clips;
    final progress = ref.read(exportProgressProvider.notifier);
    progress.set(0);
    try {
      await engine.export(
        clips: clips,
        outputPath: path,
        onProgress: progress.set,
      );
      if (context.mounted) _snack(context, 'Exported to $path');
    } catch (e) {
      if (context.mounted) _snack(context, 'Export failed: $e');
    } finally {
      progress.set(null);
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
