import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

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

/// The Stickers tab: a searchable, categorised catalogue. Clicking a sticker
/// is a stub for now — placing stickers on the timeline lands in a later
/// task. Catalogue UI only; it never touches the Clip model or engine.
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
      ],
    );
  }
}

class _StickerCell extends StatelessWidget {
  const _StickerCell({required this.sticker});

  final _Sticker sticker;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: sticker.label ?? '',
      child: Material(
        color: AppColors.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
                content: Text('Placing stickers — coming soon'))),
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
}
