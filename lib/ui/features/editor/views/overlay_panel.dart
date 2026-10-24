import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/media_type.dart';
import '../../../../domain/models/video_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/video_overlays_view_model.dart';

/// Where the player's playhead currently sits on the *timeline* — the same
/// seconds [VideoOverlay.startTime] is measured in, not the per-clip source
/// seconds [Playhead] itself stores. Identical in spirit to
/// `audio_panel.dart`'s/`stickers_panel.dart`'s `_playheadTimelineSeconds` —
/// every project-level lane places a new item at "where the preview
/// currently is".
///
/// Falls back to the end of the last-placed overlay when nothing is
/// selected, so newly-added overlays queue up after whatever's already there
/// instead of all landing on top of each other at 0.
double _playheadTimelineSeconds(WidgetRef ref) {
  final editor = ref.read(editorProvider);
  final idx = editor.selectedIndex;
  if (idx < 0) {
    var end = 0.0;
    for (final o in ref.read(videoOverlaysProvider)) {
      final overlayEnd = o.startTime + o.duration;
      if (overlayEnd > end) end = overlayEnd;
    }
    return end;
  }
  var start = 0.0;
  for (var i = 0; i < idx; i++) {
    start += editor.clips[i].duration;
  }
  final clip = editor.clips[idx];
  final within =
      (ref.read(playheadProvider) - clip.inPoint).clamp(0.0, clip.duration);
  return start + within;
}

/// The Overlay tab: a picture-in-picture lane. Import a video (or a still
/// image, imported the same way the main track accepts one) via "Import
/// video" and it's added as a [VideoOverlay] at the current playhead,
/// composited on top of the whole timeline by `FfmpegEngine._buildFilterGraph`
/// (see that method's video-overlay stage) — scaled/positioned, with its own
/// opacity and blend mode. The project's placed overlays are listed below,
/// each with inline controls for exactly those properties, mirroring
/// `StickersPanel`'s `_StickerTile`.
class OverlayPanel extends ConsumerStatefulWidget {
  const OverlayPanel({super.key});

  @override
  ConsumerState<OverlayPanel> createState() => _OverlayPanelState();
}

class _OverlayPanelState extends ConsumerState<OverlayPanel> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Picture-in-picture: a second video that plays on top of the '
                'timeline.',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 10),
              VButton(
                label: _importing ? 'Importing…' : 'Import video',
                icon: _importing ? null : Icons.add_to_queue_outlined,
                variant: VButtonVariant.primary,
                expand: true,
                onPressed: _importing ? null : () => _import(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('On this project',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7))),
          ),
        ),
        const Expanded(child: _PlacedOverlaysList()),
      ],
    );
  }

  Future<void> _import(BuildContext context) async {
    await FilePicker.skipEntitlementsChecks();
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kVideoExtensions,
      );
      if (!context.mounted) return;
      final paths = files.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return;

      var start = _playheadTimelineSeconds(ref);
      var added = 0;
      for (final path in paths) {
        try {
          final overlay = await ref
              .read(videoOverlaysProvider.notifier)
              .addFromPath(path, startTime: start);
          start += overlay.duration;
          added++;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not add overlay: $e')));
          }
        }
      }
      if (added > 0 && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(added == 1
                  ? 'Added to the overlay lane'
                  : 'Added $added overlays to the overlay lane')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

// ── placed overlay list ─────────────────────────────────────────────────────

class _PlacedOverlaysList extends ConsumerWidget {
  const _PlacedOverlaysList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlays = ref.watch(videoOverlaysProvider);

    if (overlays.isEmpty) {
      return Center(
        child: Text(
          'No overlays yet. Import a video above to place one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: overlays.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _OverlayTile(
        key: ValueKey(overlays[i].id),
        index: i,
        overlay: overlays[i],
      ),
    );
  }
}

/// Edits one placed overlay's timing/scale/position/rotation/opacity/blend
/// mode and lets it be deleted — the inspector-style controls this feature's
/// design calls for, following the same per-property-row idiom
/// `inspector_panel.dart` uses for the selected *clip* (`VSectionHeader` +
/// `VPropertyRow`), applied here to the selected *overlay* instead (mirrors
/// `StickersPanel`'s `_StickerTile`).
class _OverlayTile extends ConsumerWidget {
  const _OverlayTile({super.key, required this.index, required this.overlay});

  final int index;
  final VideoOverlay overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(videoOverlaysProvider.notifier);
    final selectedId = ref.watch(selectedVideoOverlayProvider);
    final selected = overlay.id == selectedId;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
            color: selected ? AppColors.accent : AppColors.line),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            ref.read(selectedVideoOverlayProvider.notifier).set(overlay.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.picture_in_picture_alt_outlined,
                    size: 16, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(overlay.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                VIconButton(
                  icon: Icons.close,
                  tooltip: 'Delete',
                  onPressed: () {
                    notifier.removeAt(index);
                    if (selected) {
                      ref
                          .read(selectedVideoOverlayProvider.notifier)
                          .set(null);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            VPropertyRow(
              label: 'Start',
              child: Slider(
                value: overlay.startTime.clamp(0.0, 600.0),
                min: 0,
                max: 600,
                onChanged: (v) =>
                    notifier.update(index, overlay.copyWith(startTime: v)),
              ),
            ),
            VPropertyRow(
              label: 'Scale',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: overlay.scale.clamp(0.05, 2.0),
                      min: 0.05,
                      max: 2.0,
                      onChanged: (v) =>
                          notifier.update(index, overlay.copyWith(scale: v)),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${(overlay.scale * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            VPropertyRow(
              label: 'X',
              child: Slider(
                value: overlay.posX.clamp(0.0, 1.0),
                onChanged: (v) =>
                    notifier.update(index, overlay.copyWith(posX: v)),
              ),
            ),
            VPropertyRow(
              label: 'Y',
              child: Slider(
                value: overlay.posY.clamp(0.0, 1.0),
                onChanged: (v) =>
                    notifier.update(index, overlay.copyWith(posY: v)),
              ),
            ),
            VPropertyRow(
              label: 'Rotate',
              child: Slider(
                value: overlay.rotation.clamp(-180.0, 180.0),
                min: -180,
                max: 180,
                onChanged: (v) =>
                    notifier.update(index, overlay.copyWith(rotation: v)),
              ),
            ),
            VPropertyRow(
              label: 'Opacity',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: overlay.opacity.clamp(0.0, 1.0),
                      onChanged: (v) => notifier.update(
                          index, overlay.copyWith(opacity: v)),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${(overlay.opacity * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            VPropertyRow(
              label: 'Blend',
              child: DropdownButton<String>(
                value: overlay.blendMode,
                isDense: true,
                isExpanded: true,
                dropdownColor: AppColors.well,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                underline: const SizedBox.shrink(),
                items: [
                  for (final mode in kBlendModes)
                    DropdownMenuItem(
                        value: mode, child: Text(blendModeLabel(mode))),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    notifier.update(index, overlay.copyWith(blendMode: mode));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
