import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/sticker_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../view_models/sticker_overlays_view_model.dart';

/// A single entry in the sticker catalogue. Emoji categories render the
/// [emoji] glyph directly; non-emoji categories (e.g. Trending image packs)
/// are placeholders until real sticker art ships.
class _Sticker {
  const _Sticker(this.emoji, [this.label]);

  /// The glyph to render, or null for an "image sticker" placeholder.
  final String? emoji;

  /// Optional accessible/tooltip label.
  final String? label;
}

class _StickerCategory {
  const _StickerCategory(this.name, this.icon, this.stickers);

  final String name;
  final IconData icon;
  final List<_Sticker> stickers;
}

/// ~60 common emoji — enough that the Emoji category reads as a real, populated
/// catalogue rather than a stub.
const _kEmoji = [
  '😀', '😂', '🤣', '😊', '😍', '🥰', '😘', '😎', '🤩', '🥳',
  '😢', '😭', '😡', '🤯', '😱', '🥺', '😴', '🤔', '🙄', '😇',
  '🎉', '🎊', '🔥', '✨', '💯', '⭐️', '🌟', '💫', '⚡️', '💥',
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💕',
  '👍', '👎', '👏', '🙌', '👋', '✌️', '🤞', '💪', '🙏', '👀',
  '🎵', '🎬', '📸', '🎮', '🏆', '🚀', '🌈', '☀️', '🌙', '🍀',
];

final _kCategories = [
  _StickerCategory(
    'Emoji',
    Icons.emoji_emotions_outlined,
    [for (final e in _kEmoji) _Sticker(e)],
  ),
  const _StickerCategory('Shapes', Icons.category_outlined, [
    _Sticker(null, 'Circle'),
    _Sticker(null, 'Square'),
    _Sticker(null, 'Triangle'),
    _Sticker(null, 'Star'),
    _Sticker(null, 'Heart outline'),
    _Sticker(null, 'Hexagon'),
    _Sticker(null, 'Blob'),
    _Sticker(null, 'Burst'),
  ]),
  const _StickerCategory('Arrows', Icons.north_east, [
    _Sticker(null, 'Arrow right'),
    _Sticker(null, 'Arrow curve'),
    _Sticker(null, 'Arrow loop'),
    _Sticker(null, 'Pointer'),
    _Sticker(null, 'Swoosh'),
    _Sticker(null, 'Doodle arrow'),
  ]),
  const _StickerCategory('Social', Icons.share_outlined, [
    _Sticker(null, 'Like badge'),
    _Sticker(null, 'Follow badge'),
    _Sticker(null, 'Subscribe badge'),
    _Sticker(null, 'Comment bubble'),
    _Sticker(null, 'Share badge'),
    _Sticker(null, 'Notification bell'),
  ]),
  const _StickerCategory('Trending', Icons.local_fire_department_outlined, [
    _Sticker(null, 'New'),
    _Sticker(null, 'Viral'),
    _Sticker(null, 'Trending badge'),
    _Sticker(null, 'Hot sticker pack'),
    _Sticker(null, 'POV badge'),
    _Sticker(null, 'Caption bubble'),
  ]),
];

/// The Stickers tab: a searchable, categorised catalogue up top, and the
/// project's placed stickers below. Clicking an emoji adds a [StickerOverlay]
/// to the project (timed on the final, concatenated timeline, same as
/// [TextOverlay]) and burns it into the export via ffmpeg's `drawtext`
/// filter (an emoji is just text, rendered with a colour-emoji font — see
/// `FfmpegEngine._resolveUsableEmojiFont`). Non-emoji categories are still a
/// stub; placing real sticker art is future work.
class StickersPanel extends StatefulWidget {
  const StickersPanel({super.key});

  @override
  State<StickersPanel> createState() => _StickersPanelState();
}

class _StickersPanelState extends State<StickersPanel> {
  int _categoryIndex = 0;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final category = _kCategories[_categoryIndex];
    final stickers = _query.trim().isEmpty
        ? category.stickers
        : category.stickers
            .where((s) =>
                (s.label ?? '').toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: VTextField(
            hint: 'Search stickers',
            icon: Icons.search,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _kCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _kCategories[i];
              return VChip(
                label: c.name,
                icon: c.icon,
                selected: i == _categoryIndex,
                onTap: () => setState(() {
                  _categoryIndex = i;
                  _query = '';
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          flex: 3,
          child: stickers.isEmpty
              ? Center(
                  child: Text(
                    'No stickers found.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive column count: keep cells roughly square and
                    // comfortably tappable across panel widths.
                    const minCellWidth = 64.0;
                    final columns =
                        (constraints.maxWidth / minCellWidth).floor().clamp(3, 10);
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: stickers.length,
                      itemBuilder: (context, i) =>
                          _StickerCell(sticker: stickers[i]),
                    );
                  },
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
        const Expanded(flex: 2, child: _PlacedStickersList()),
      ],
    );
  }
}

class _StickerCell extends ConsumerWidget {
  const _StickerCell({required this.sticker});

  final _Sticker sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: sticker.label ?? '',
      child: Material(
        color: AppColors.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => _tap(context, ref),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.line),
            ),
            alignment: Alignment.center,
            child: sticker.emoji != null
                ? Text(sticker.emoji!, style: const TextStyle(fontSize: 26))
                : Icon(Icons.image_outlined,
                    size: 22, color: Colors.white.withValues(alpha: 0.35)),
          ),
        ),
      ),
    );
  }

  void _tap(BuildContext context, WidgetRef ref) {
    final emoji = sticker.emoji;
    if (emoji == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            const SnackBar(content: Text('Placing stickers — coming soon')));
      return;
    }
    ref.read(stickerOverlaysProvider.notifier).add(emoji);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Added $emoji to the project')));
  }
}

// ── placed sticker list ─────────────────────────────────────────────────────

class _PlacedStickersList extends ConsumerWidget {
  const _PlacedStickersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlays = ref.watch(stickerOverlaysProvider);

    if (overlays.isEmpty) {
      return Center(
        child: Text(
          'No stickers yet. Tap an emoji above to place one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: overlays.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _StickerTile(
        key: ValueKey(overlays[i].id),
        index: i,
        overlay: overlays[i],
      ),
    );
  }
}

/// Edits one placed sticker's timing/position and lets it be deleted —
/// mirrors `TextPanel`'s `_OverlayTile`.
class _StickerTile extends ConsumerWidget {
  const _StickerTile({super.key, required this.index, required this.overlay});

  final int index;
  final StickerOverlay overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(stickerOverlaysProvider.notifier);

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
          Text(overlay.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
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
                Row(
                  children: [
                    Expanded(
                      child: _DoubleField(
                        value: overlay.start,
                        prefix: 'In',
                        suffix: 's',
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(start: d)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DoubleField(
                        value: overlay.end,
                        prefix: 'Out',
                        suffix: 's',
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(end: d)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _DoubleField(
                        value: overlay.x,
                        prefix: 'X',
                        decimals: 2,
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(x: d)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DoubleField(
                        value: overlay.y,
                        prefix: 'Y',
                        decimals: 2,
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(y: d)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DoubleField(
                        value: overlay.size,
                        prefix: 'Size',
                        decimals: 2,
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(size: d)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          VIconButton(
            icon: Icons.close,
            tooltip: 'Delete',
            onPressed: () => notifier.removeAt(index),
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

/// A small numeric field for a double value (time/position/size), editable
/// as text. Keeps its own controller in sync with external changes the same
/// way `inspector_panel.dart`'s `_SecondsField` does.
class _DoubleField extends StatefulWidget {
  const _DoubleField({
    required this.value,
    required this.onChanged,
    this.prefix,
    this.suffix,
    this.decimals = 1,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String? prefix;
  final String? suffix;
  final int decimals;

  @override
  State<_DoubleField> createState() => _DoubleFieldState();
}

class _DoubleFieldState extends State<_DoubleField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DoubleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final text = _fmt(widget.value);
      if (_controller.text != text) _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  Widget build(BuildContext context) {
    return VNumberField(
      value: _fmt(widget.value),
      controller: _controller,
      prefix: widget.prefix,
      suffix: widget.suffix,
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}
