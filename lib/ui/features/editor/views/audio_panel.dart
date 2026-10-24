import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/audio_clip.dart';
import '../../../../domain/models/media_type.dart';
import '../../../../domain/models/sfx_presets.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/audio_clips_view_model.dart';
import '../view_models/editor_view_model.dart';

/// Where the player's playhead currently sits on the *timeline* — the same
/// seconds [AudioClip.start] is measured in, not the per-clip source seconds
/// [Playhead] itself stores. Mirrors the calculation `TimelinePanel` uses to
/// place its own playhead marker (cumulative start of the selected clip on
/// the track, plus how far into that clip the preview currently is).
///
/// Falls back to the end of the audio lane when nothing is selected, so
/// newly-added sounds queue up after whatever's already there instead of all
/// landing on top of each other at 0.
double _playheadTimelineSeconds(WidgetRef ref) {
  final editor = ref.read(editorProvider);
  final idx = editor.selectedIndex;
  if (idx < 0) {
    var end = 0.0;
    for (final a in ref.read(audioClipsProvider)) {
      final clipEnd = a.start + a.duration;
      if (clipEnd > end) end = clipEnd;
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

enum _AudioSection { myAudio, sfx, extract }

/// The Audio tab's left browser: import audio files or drag them in, add a
/// built-in (ffmpeg-generated) sound effect, or extract the audio from a clip
/// already on the timeline — every action appends an [AudioClip] to the
/// project's audio lane at the current playhead via [AudioClips].
class AudioPanel extends ConsumerStatefulWidget {
  const AudioPanel({super.key});

  @override
  ConsumerState<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends ConsumerState<AudioPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  _AudioSection _section = _AudioSection.myAudio;
  bool _dragging = false;
  bool _importing = false;
  bool _extracting = false;
  String? _generatingSfxId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        final audioPaths = details.files
            .map((f) => f.path)
            .where((p) => mediaTypeForPath(p) == MediaType.audio);
        await _addPaths(context, audioPaths);
      },
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: VTextField(
                  controller: _searchController,
                  hint: 'Search audio, sound effects',
                  icon: Icons.search,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    VChip(
                      label: 'My audio',
                      icon: Icons.library_music_outlined,
                      selected: _section == _AudioSection.myAudio,
                      onTap: () =>
                          setState(() => _section = _AudioSection.myAudio),
                    ),
                    VChip(
                      label: 'Sound effects',
                      icon: Icons.graphic_eq,
                      selected: _section == _AudioSection.sfx,
                      onTap: () =>
                          setState(() => _section = _AudioSection.sfx),
                    ),
                    VChip(
                      label: 'Extract',
                      icon: Icons.audiotrack_outlined,
                      selected: _section == _AudioSection.extract,
                      onTap: () =>
                          setState(() => _section = _AudioSection.extract),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.line),
              Expanded(child: _buildSection(context)),
            ],
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: const Center(
                    child: Text('Drop to add to the audio lane',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    switch (_section) {
      case _AudioSection.myAudio:
        return _buildMyAudio(context);
      case _AudioSection.sfx:
        return _buildSfx(context);
      case _AudioSection.extract:
        return _buildExtract(context);
    }
  }

  // ── My audio ─────────────────────────────────────────────────────────────

  Widget _buildMyAudio(BuildContext context) {
    // The audio lane doubles as the "library" of previously-imported files —
    // dedupe by source path so a track used twice on the timeline only shows
    // up once here, and clicking it adds another instance.
    final seen = <String>{};
    final sources = <AudioClip>[];
    for (final clip in ref.watch(audioClipsProvider)) {
      if (seen.add(clip.sourcePath)) sources.add(clip);
    }
    final filtered = _query.isEmpty
        ? sources
        : sources
            .where((c) => c.fileName.toLowerCase().contains(_query))
            .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            minimumSize: const Size(0, 36),
          ),
          icon: _importing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add, size: 18),
          label: Text(_importing ? 'Importing…' : 'Import audio'),
          onPressed: _importing ? null : () => _import(context),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              sources.isEmpty
                  ? 'No audio imported yet.\nImport a file or drop one here '
                      'to add it to the timeline.'
                  : 'No matches.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            ),
          )
        else ...[
          VSectionHeader('Imported'),
          for (final clip in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AudioTile(
                icon: Icons.music_note,
                title: clip.fileName,
                subtitle: _fmtDuration(clip.sourceDuration),
                onTap: () => _addPaths(context, [clip.sourcePath]),
              ),
            ),
        ],
      ],
    );
  }

  // ── Sound effects ────────────────────────────────────────────────────────

  Widget _buildSfx(BuildContext context) {
    final filtered = _query.isEmpty
        ? kSfxPresets
        : kSfxPresets
            .where((p) => p.label.toLowerCase().contains(_query))
            .toList();
    final tones =
        filtered.where((p) => p.category == SfxCategory.tone).toList();
    final sfx = filtered.where((p) => p.category == SfxCategory.sfx).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Generated on first use with ffmpeg — no licensing, tap to add.',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 14),
        if (tones.isNotEmpty) ...[
          VSectionHeader('Tones'),
          _SfxGrid(
            presets: tones,
            generatingId: _generatingSfxId,
            onTap: (p) => _addSfx(context, p),
          ),
          const SizedBox(height: 18),
        ],
        if (sfx.isNotEmpty) ...[
          VSectionHeader('Sound effects'),
          _SfxGrid(
            presets: sfx,
            generatingId: _generatingSfxId,
            onTap: (p) => _addSfx(context, p),
          ),
        ],
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No matches.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
          ),
      ],
    );
  }

  // ── Extract ──────────────────────────────────────────────────────────────

  Widget _buildExtract(BuildContext context) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        VSectionHeader('Extract audio from a clip'),
        Text(
          clip == null
              ? 'Select a video clip on the timeline to pull out its audio.'
              : 'Pulls "${clip.fileName}"\'s audio track and adds it to the '
                  'audio lane.',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            minimumSize: const Size(0, 36),
          ),
          icon: _extracting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.audiotrack_outlined, size: 18),
          label:
              Text(_extracting ? 'Extracting…' : 'Extract to the audio lane'),
          onPressed: clip == null || _extracting
              ? null
              : () => _extract(context, clip.id),
        ),
      ],
    );
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _import(BuildContext context) async {
    await FilePicker.skipEntitlementsChecks();
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAudioExtensions,
      );
      if (!context.mounted) return;
      await _addPaths(
        context,
        files.map((f) => f.path).whereType<String>(),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Adds each of [paths] to the audio lane, one after another starting at
  /// the current playhead — later files queue up after earlier ones (by
  /// their probed duration) rather than all overlapping at the same spot.
  Future<void> _addPaths(BuildContext context, Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;

    var start = _playheadTimelineSeconds(ref);
    var added = 0;
    for (final path in list) {
      try {
        final clip = await ref
            .read(audioClipsProvider.notifier)
            .addFromPath(path, start: start);
        start += clip.duration;
        added++;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Could not add ${_fileName(path)}: $e')));
        }
      }
    }
    if (added > 0 && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(added == 1
                ? 'Added to the audio lane'
                : 'Added $added files to the audio lane')));
    }
  }

  Future<void> _addSfx(BuildContext context, SfxPreset preset) async {
    setState(() => _generatingSfxId = preset.id);
    try {
      final path = await ref.read(engineProvider).generateSfx(preset.id);
      if (!context.mounted) return;
      final start = _playheadTimelineSeconds(ref);
      await ref
          .read(audioClipsProvider.notifier)
          .addFromPath(path, start: start);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text('Added "${preset.label}" to the audio lane')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Could not generate: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingSfxId = null);
    }
  }

  Future<void> _extract(BuildContext context, String clipId) async {
    final clip =
        ref.read(editorProvider).clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;

    final dir = Directory('${Directory.systemTemp.path}/mozcut-audio-extract');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final base = clip.fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final outputPath =
        '${dir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}.wav';

    setState(() => _extracting = true);
    try {
      await ref
          .read(engineProvider)
          .extractAudio(clip: clip, outputPath: outputPath);
      if (!context.mounted) return;
      final start = _playheadTimelineSeconds(ref);
      await ref
          .read(audioClipsProvider.notifier)
          .addFromPath(outputPath, start: start);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(
                  'Added "${clip.fileName}"\'s audio to the audio lane')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Extraction failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  static String _fileName(String path) =>
      path.split(RegExp(r'[/\\]')).last;

  static String _fmtDuration(double seconds) {
    final s = seconds.clamp(0, double.infinity);
    final m = (s ~/ 60).toInt();
    final r = (s - m * 60).toInt();
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}

// ── shared tiles ─────────────────────────────────────────────────────────────

/// A single-row item used by "My audio" — an icon, a title and subtitle, and
/// a tap target that adds it to the timeline.
class _AudioTile extends StatelessWidget {
  const _AudioTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.well,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline,
                size: 16, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

/// A 2-column grid of sound-effect/tone cards. Shows a small spinner over
/// whichever preset is currently being generated (`generatingId`).
class _SfxGrid extends StatelessWidget {
  const _SfxGrid({
    required this.presets,
    required this.generatingId,
    required this.onTap,
  });

  final List<SfxPreset> presets;
  final String? generatingId;
  final ValueChanged<SfxPreset> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.6,
      ),
      itemCount: presets.length,
      itemBuilder: (context, i) {
        final preset = presets[i];
        final busy = generatingId == preset.id;
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: busy ? null : () => onTap(preset),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.well,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    preset.category == SfxCategory.tone
                        ? Icons.graphic_eq
                        : Icons.bolt_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(preset.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      Text(
                          preset.duration < 1
                              ? '${(preset.duration * 1000).round()}ms'
                              : '${preset.duration.toStringAsFixed(1)}s',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.4))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
