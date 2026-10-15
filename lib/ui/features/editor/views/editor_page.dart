import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../core/app_colors.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/editor_view_model.dart';
import 'inspector_panel.dart';
import 'media_panel.dart';
import 'preview_panel.dart';
import 'timeline_panel.dart';

/// The editor shell: a classic NLE layout — media bin on the left, the monitor
/// in the centre, the inspector on the right, and the timeline across the
/// bottom. Modelled on Concat's default dock.
class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  static const _mediaWidth = 230.0;
  static const _inspectorWidth = 288.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _Toolbar(),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: const [
                SizedBox(width: _mediaWidth, child: MediaPanel()),
                _VDivider(),
                Expanded(child: PreviewPanel()),
                _VDivider(),
                SizedBox(width: _inspectorWidth, child: InspectorPanel()),
              ],
            ),
          ),
          const _HDivider(),
          const SizedBox(height: 190, child: TimelinePanel()),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: AppColors.line);
}

class _HDivider extends StatelessWidget {
  const _HDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.line);
}

class _Toolbar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final progress = ref.watch(exportProgressProvider);
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
          const Spacer(),
          if (exporting)
            SizedBox(
              width: 180,
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: progress)),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
            )
          else ...[
            TextButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                await ref.read(appProvider.notifier).saveCurrent();
                if (context.mounted) _snack(context, 'Project saved');
              },
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Export'),
              onPressed:
                  state.clips.isEmpty ? null : () => _export(context, ref),
            ),
          ],
          const SizedBox(width: 12),
        ],
      ),
    );
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
