import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/project.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/audio_clips_view_model.dart';
import '../view_models/editor_view_model.dart';
import 'editor_shortcuts.dart';
import 'export_dialog.dart';
import '../view_models/sticker_overlays_view_model.dart';
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
          VIconButton(
            icon: Icons.photo_camera_outlined,
            tooltip: 'Export frame at playhead as image',
            onPressed:
                hasClips && !exporting ? () => _exportFrame(context, ref) : null,
          ),
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
    final stickerOverlays = ref.read(stickerOverlaysProvider);
    final audioClips = ref.read(audioClipsProvider);
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();
    final progress = ref.read(exportProgressProvider.notifier);
    progress.set(0);
    try {
      await engine.export(
          clips: clips,
          outputPath: path,
          settings: settings,
          textOverlays: textOverlays,
          stickerOverlays: stickerOverlays,
          audioClips: audioClips,
          canvasWidth: canvas.width,
          canvasHeight: canvas.height,
          onProgress: progress.set);
      if (context.mounted) _snack(context, 'Exported to $path');
    } catch (e) {
      if (context.mounted) _snack(context, 'Export failed: $e');
    } finally {
      progress.set(null);
    }
  }

  /// Saves the frame currently showing at the player's playhead as a PNG.
  /// Reuses the exact composited-timeline frame [Engine.exportStillFrame]
  /// produces — transforms, captions, text/sticker overlays all included,
  /// same as a real export would show at this instant.
  Future<void> _exportFrame(BuildContext context, WidgetRef ref) async {
    final clips = ref.read(editorProvider).clips;
    if (clips.isEmpty) return;
    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose where to save the frame');
    if (dir == null) return;
    if (!context.mounted) return;
    final path =
        '$dir/mozcut_frame_${DateTime.now().millisecondsSinceEpoch}.png';
    final engine = ref.read(engineProvider);
    final textOverlays = ref.read(textOverlaysProvider);
    final stickerOverlays = ref.read(stickerOverlaysProvider);
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();
    final atSeconds = _playheadTimelineSeconds(ref);
    try {
      await engine.exportStillFrame(
          clips: clips,
          textOverlays: textOverlays,
          stickerOverlays: stickerOverlays,
          canvasWidth: canvas.width,
          canvasHeight: canvas.height,
          atSeconds: atSeconds,
          outputPath: path);
      if (context.mounted) _snack(context, 'Frame saved to $path');
    } catch (e) {
      if (context.mounted) _snack(context, 'Frame export failed: $e');
    }
  }

  /// Where the player's playhead currently sits on the *timeline* — the same
  /// seconds [Clip] durations stack up in, not the per-clip source seconds
  /// [Playhead] itself stores (see its doc comment). Mirrors the calculation
  /// `AudioPanel`/`TimelinePanel` use to place their own playhead markers:
  /// cumulative start of the selected clip on the track, plus how far into
  /// that clip the preview currently is. Falls back to the raw playhead value
  /// when nothing is selected (e.g. right after "Render preview" loads the
  /// whole-timeline proxy, where the playhead *is* already timeline-relative).
  double _playheadTimelineSeconds(WidgetRef ref) {
    final editor = ref.read(editorProvider);
    final idx = editor.selectedIndex;
    final playhead = ref.read(playheadProvider);
    if (idx < 0 || idx >= editor.clips.length) return playhead;
    var start = 0.0;
    for (var i = 0; i < idx; i++) {
      start += editor.clips[i].duration;
    }
    final clip = editor.clips[idx];
    final within = (playhead - clip.inPoint).clamp(0.0, clip.duration);
    return start + within;
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
}
