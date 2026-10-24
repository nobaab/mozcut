import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/media_type.dart';
import '../../../core/app_colors.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/media_import.dart';
import 'audio_panel.dart';
import 'captions_panel.dart';
import 'effects_panel.dart';
import 'filters_panel.dart';
import 'stickers_panel.dart';
import 'templates_panel.dart';
import 'transitions_panel.dart';

/// The left browser: its content depends on the active feature tab. The media
/// (Import), Audio and Captions browsers are wired; the rest are present as
import 'text_panel.dart';

/// The left browser: its content depends on the active feature tab. The media
/// (Import), Captions and Text browsers are wired; the rest are present as
/// panels with their shape sketched in, ready to be filled.
class BrowserPanel extends ConsumerWidget {
  const BrowserPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(leftTabProvider);
    return Container(
      color: AppColors.panel,
      child: switch (tab) {
        EditorLeftTab.media => const _MediaBrowser(),
        EditorLeftTab.audio => const AudioPanel(),
        EditorLeftTab.captions => const CaptionsPanel(),
        EditorLeftTab.effects => const EffectsPanel(),
        EditorLeftTab.filters => const FiltersPanel(),
        EditorLeftTab.transitions => const TransitionsPanel(),
        EditorLeftTab.stickers => const StickersPanel(),
        EditorLeftTab.templates => const TemplatesPanel(),
        EditorLeftTab.text => const TextPanel(),
      },
    );
  }
}

// ── the media browser ───────────────────────────────────────────────────────

class _MediaBrowser extends ConsumerWidget {
  const _MediaBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-rail: Device / Spaces / Stock / Brand (CapCut's left strip).
        Container(
          width: 94,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: const [
              _SubRailItem('Device', active: true),
              _SubRailItem('Import', indent: true, active: true),
              _SubRailItem('My presets', indent: true),
              _SubRailItem('Spaces'),
              _SubRailItem('Stock media'),
              _SubRailItem('Brand assets'),
            ],
          ),
        ),
        const Expanded(child: _MediaGridArea()),
      ],
    );
  }
}

class _SubRailItem extends StatelessWidget {
  const _SubRailItem(this.label, {this.active = false, this.indent = false});
  final String label;
  final bool active;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 18 : 10, 5, 8, 5),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active && !indent ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? (indent ? AppColors.accent : Colors.white)
                : Colors.white.withValues(alpha: 0.6),
          )),
    );
  }
}

class _MediaGridArea extends ConsumerStatefulWidget {
  const _MediaGridArea();

  @override
  ConsumerState<_MediaGridArea> createState() => _MediaGridAreaState();
}

class _MediaGridAreaState extends ConsumerState<_MediaGridArea> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        await importMediaPaths(
          ref,
          details.files.map((f) => f.path),
          onError: (message) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          },
        );
      },
      child: Stack(
        children: [
          _buildContent(context, ref),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: const Center(
                    child: Text('Drop to import',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: SizedBox(
            height: 34,
            child: TextField(
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search project, subjects, lines',
                hintStyle: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: AppColors.well,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        // Toolbar: Import + view / sort / filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Import'),
                onPressed: () => _import(context, ref),
              ),
              const Spacer(),
              _iconBtn(context, Icons.grid_view, 'View'),
              _iconBtn(context, Icons.sort, 'Sort'),
              _iconBtn(context, Icons.filter_list, 'Filter'),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('All',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: state.clips.isEmpty
              ? Center(
                  child: Text(
                      'No media yet.\nClick Import or drop files to add '
                      'video, images or audio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35))),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: state.clips.length,
                  itemBuilder: (context, i) {
                    final clip = state.clips[i];
                    final selected = clip.id == state.selectedId;
                    return InkWell(
                      onTap: () =>
                          ref.read(editorProvider.notifier).select(clip.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.well,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.line),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                      child: Icon(
                                          clip.mediaType == MediaType.image
                                              ? Icons.image_outlined
                                              : Icons.movie_outlined,
                                          size: 22,
                                          color: Colors.white
                                              .withValues(alpha: 0.4))),
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                          '${clip.duration.toStringAsFixed(1)}s',
                                          style: const TextStyle(fontSize: 10)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(clip.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, String tip) =>
      IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$tip — coming soon'))),
      );

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    await FilePicker.skipEntitlementsChecks();
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kImportableExtensions,
    );
    await importMediaPaths(
      ref,
      files.map((f) => f.path).whereType<String>(),
      onError: (message) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }
}

