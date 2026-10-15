import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/editor_view_model.dart';

/// A placeholder catalogue entry (music track or sound effect). Not backed by
/// a real stock-audio source yet — tapping one just says so.
class _AudioSample {
  const _AudioSample(this.name, this.length);
  final String name;
  final String length;
}

const _music = [
  _AudioSample('Ambient Calm', '2:14'),
  _AudioSample('Upbeat Pop', '1:48'),
  _AudioSample('Cinematic Build', '3:02'),
  _AudioSample('Lo-fi Chill', '2:30'),
  _AudioSample('Acoustic Morning', '2:05'),
  _AudioSample('Driving Synth', '2:41'),
];

const _sfx = [
  _AudioSample('Whoosh', '0:02'),
  _AudioSample('Camera Shutter', '0:01'),
  _AudioSample('Pop', '0:01'),
  _AudioSample('Notification', '0:02'),
  _AudioSample('Click', '0:01'),
  _AudioSample('Swoosh Transition', '0:02'),
];

/// The Audio tab's left browser: search, a static Music / Sound effects
/// catalogue (both "coming soon" — there is no stock-audio backend yet), and
/// the one real, wired action: extracting the selected clip's audio track to
/// a file on disk via ffmpeg.
class AudioPanel extends ConsumerStatefulWidget {
  const AudioPanel({super.key});

  @override
  ConsumerState<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends ConsumerState<AudioPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _extracting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
    final music = _filter(_music);
    final sfx = _filter(_sfx);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        VTextField(
          controller: _searchController,
          hint: 'Search music, sound effects',
          icon: Icons.search,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 14),

        // ── the one real action ──
        VSectionHeader('Extract audio'),
        Text(
          clip == null
              ? 'Select a clip on the timeline to extract its audio.'
              : 'Writes "${clip.fileName}"\'s audio track to a WAV file.',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 8),
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
          label: Text(_extracting
              ? 'Extracting…'
              : 'Extract audio from selected clip'),
          onPressed: clip == null || _extracting
              ? null
              : () => _extract(context, clip.id),
        ),
        const SizedBox(height: 22),

        VSectionHeader('Music'),
        _SampleGrid(samples: music),
        const SizedBox(height: 22),
        VSectionHeader('Sound effects'),
        _SampleGrid(samples: sfx),
      ],
    );
  }

  List<_AudioSample> _filter(List<_AudioSample> all) => _query.isEmpty
      ? all
      : all.where((s) => s.name.toLowerCase().contains(_query)).toList();

  Future<void> _extract(BuildContext context, String clipId) async {
    final clip =
        ref.read(editorProvider).clips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;

    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose where to save the extracted audio');
    if (dir == null || !context.mounted) return;

    final base = clip.fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final outputPath = '$dir/${base}_audio.wav';

    setState(() => _extracting = true);
    try {
      await ref
          .read(engineProvider)
          .extractAudio(clip: clip, outputPath: outputPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text('Audio extracted to $outputPath')));
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
}

class _SampleGrid extends StatelessWidget {
  const _SampleGrid({required this.samples});
  final List<_AudioSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No matches.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
      );
    }
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
      itemCount: samples.length,
      itemBuilder: (context, i) {
        final sample = samples[i];
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
                SnackBar(content: Text('${sample.name} — coming soon'))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.well,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.music_note,
                    size: 16, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sample.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      Text(sample.length,
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
