import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/speech/whisper_service.dart';
import '../../../../domain/models/caption.dart';
import '../../../../domain/models/clip.dart';
import '../../../core/app_colors.dart';
import '../view_models/captions_view_model.dart';
import '../view_models/editor_view_model.dart';

/// The Captions tab: runs local, on-device speech-to-text (whisper.cpp) on
/// the selected clip and lists the resulting segments, each editable or
/// deletable before export burns them into the video.
class CaptionsPanel extends ConsumerWidget {
  const CaptionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
    final status = ref.watch(captionGenerationProvider);
    final busy = status != null;

    if (clip == null) {
      return Center(
        child: Text(
          'Select a clip to generate captions.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }

    final captions = clip.captions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size(0, 36),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.closed_caption_outlined, size: 18),
                label: Text(status ?? 'Generate captions'),
                onPressed: busy ? null : () => _generate(context, ref, clip),
              ),
              const SizedBox(height: 6),
              Text(
                'Runs locally with whisper.cpp — no upload, no account.',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: captions.isEmpty
              ? Center(
                  child: Text(
                    busy ? 'Transcribing…' : 'No captions yet.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: captions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _CaptionTile(
                    key: ValueKey('${clip.id}-$i'),
                    index: i,
                    caption: captions[i],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _generate(
      BuildContext context, WidgetRef ref, Clip clip) async {
    final generation = ref.read(captionGenerationProvider.notifier);
    generation.set('Starting…');
    try {
      final captions = await ref.read(whisperServiceProvider).transcribe(
            clip.sourcePath,
            start: clip.inPoint,
            end: clip.outPoint,
            onStatus: generation.set,
          );
      ref.read(editorProvider.notifier).setSelectedCaptions(captions);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(captions.isEmpty
                  ? 'No speech detected in this clip.'
                  : 'Generated ${captions.length} caption segment(s).')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      generation.set(null);
    }
  }
}

class _CaptionTile extends ConsumerStatefulWidget {
  const _CaptionTile({super.key, required this.index, required this.caption});

  final int index;
  final Caption caption;

  @override
  ConsumerState<_CaptionTile> createState() => _CaptionTileState();
}

class _CaptionTileState extends ConsumerState<_CaptionTile> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.caption.text);
  }

  @override
  void didUpdateWidget(covariant _CaptionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption.text != widget.caption.text &&
        widget.caption.text != _controller.text) {
      _controller.text = widget.caption.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.well,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmt(caption.start)} – ${_fmt(caption.end)}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 13),
                  maxLines: null,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) => ref
                      .read(editorProvider.notifier)
                      .updateSelectedCaption(
                          widget.index, caption.copyWith(text: value)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete',
            onPressed: () => ref
                .read(editorProvider.notifier)
                .deleteSelectedCaption(widget.index),
          ),
        ],
      ),
    );
  }

  static String _fmt(double seconds) {
    final s = seconds.clamp(0, double.infinity);
    final m = (s ~/ 60).toInt();
    final r = s - m * 60;
    return '$m:${r.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
