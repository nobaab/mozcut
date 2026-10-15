import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../view_models/editor_view_model.dart';

/// The media bin: the project's source clips. Import adds to it; clicking a clip
/// selects it (which loads it in the preview). Concat's left-hand "media" pane.
class MediaPanel extends ConsumerWidget {
  const MediaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    return Panel(
      title: 'Media',
      padBody: false,
      trailing: IconButton(
        icon: const Icon(Icons.add, size: 18),
        tooltip: 'Import video',
        onPressed: () => _import(context, ref),
      ),
      child: state.clips.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No media yet.\nClick + to import a video.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: state.clips.length,
              itemBuilder: (context, i) {
                final clip = state.clips[i];
                final selected = clip.id == state.selectedId;
                return InkWell(
                  onTap: () =>
                      ref.read(editorProvider.notifier).select(clip.id),
                  child: Container(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : null,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.well,
                            borderRadius: BorderRadius.circular(4),
                            border: selected
                                ? Border.all(color: AppColors.accent)
                                : null,
                          ),
                          child: Icon(Icons.movie_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(clip.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text('${clip.duration.toStringAsFixed(1)}s',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white
                                          .withValues(alpha: 0.4))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not import ${f.name}: $e')));
        }
      }
    }
  }
}
