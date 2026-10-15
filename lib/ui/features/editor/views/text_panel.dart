import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/text_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/text_overlays_view_model.dart';

/// The Text tab: add title cards and edit the project's text overlays.
///
/// Overlays are project-level (not per-clip, see [TextOverlay]'s doc comment)
/// so every title here applies to the final, concatenated timeline and is
/// burned into the export via ffmpeg's `drawtext` filter.
class TextPanel extends ConsumerWidget {
  const TextPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlays = ref.watch(textOverlaysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: VButton(
            label: 'Add text',
            icon: Icons.add,
            variant: VButtonVariant.primary,
            expand: true,
            onPressed: () =>
                ref.read(textOverlaysProvider.notifier).add(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: VSectionHeader('Title presets'),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) =>
                _PresetChip(preset: _presets[i]),
          ),
        ),
        const SizedBox(height: 8),
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
        Expanded(
          child: overlays.isEmpty
              ? Center(
                  child: Text(
                    'No text yet. Tap "Add text" to place a title.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: overlays.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _OverlayTile(
                    key: ValueKey(overlays[i].id),
                    index: i,
                    overlay: overlays[i],
                  ),
                ),
        ),
      ],
    );
  }
}

// ── title presets ───────────────────────────────────────────────────────────

class _TitlePreset {
  const _TitlePreset(
    this.label, {
    this.fontSize = 0.08,
    this.color = '#FFFFFF',
    this.comingSoon = false,
  });

  final String label;
  final double fontSize;
  final String color;

  /// Static placeholder — tapping it just says so. The real styling (outline,
  /// shadow, animated entrances) is future work; see docs/FEATURES.md.
  final bool comingSoon;
}

const _presets = [
  _TitlePreset('Simple'),
  _TitlePreset('Bold', fontSize: 0.11),
  _TitlePreset('Subtitle', fontSize: 0.05, color: '#FFD60A'),
  _TitlePreset('Elegant', comingSoon: true),
  _TitlePreset('Typewriter', comingSoon: true),
  _TitlePreset('Neon glow', comingSoon: true),
  _TitlePreset('Shadow pop', comingSoon: true),
];

class _PresetChip extends ConsumerWidget {
  const _PresetChip({required this.preset});
  final _TitlePreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return VChip(
      label: preset.label,
      icon: preset.comingSoon ? Icons.lock_clock_outlined : Icons.title,
      onTap: () => preset.comingSoon
          ? _soon(context)
          : _apply(ref),
    );
  }

  void _apply(WidgetRef ref) {
    final notifier = ref.read(textOverlaysProvider.notifier);
    final added = notifier.add();
    final index = ref.read(textOverlaysProvider).length - 1;
    notifier.update(
      index,
      added.copyWith(fontSize: preset.fontSize, color: preset.color),
    );
  }

  void _soon(BuildContext context) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
        SnackBar(content: Text('${preset.label} — coming soon')));
}

// ── overlay list tile ────────────────────────────────────────────────────────

class _OverlayTile extends ConsumerStatefulWidget {
  const _OverlayTile({super.key, required this.index, required this.overlay});

  final int index;
  final TextOverlay overlay;

  @override
  ConsumerState<_OverlayTile> createState() => _OverlayTileState();
}

class _OverlayTileState extends ConsumerState<_OverlayTile> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.overlay.text);
  }

  @override
  void didUpdateWidget(covariant _OverlayTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlay.text != widget.overlay.text &&
        widget.overlay.text != _controller.text) {
      _controller.text = widget.overlay.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
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
                  '${_fmt(overlay.start)} – ${_fmt(overlay.end)}',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 4),
                VTextField(
                  controller: _controller,
                  hint: 'Title text',
                  onChanged: (value) => ref
                      .read(textOverlaysProvider.notifier)
                      .update(widget.index, overlay.copyWith(text: value)),
                ),
              ],
            ),
          ),
          VIconButton(
            icon: Icons.close,
            tooltip: 'Delete',
            onPressed: () => ref
                .read(textOverlaysProvider.notifier)
                .removeAt(widget.index),
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
