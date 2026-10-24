import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/media_type.dart';
import '../../../../domain/models/shape_presets.dart';
import '../../../../domain/models/sticker_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/sticker_overlays_view_model.dart';

/// Where the player's playhead currently sits on the *timeline* — the same
/// seconds [StickerOverlay.start] is measured in, not the per-clip source
/// seconds [Playhead] itself stores. Identical to (and kept in sync with)
/// `audio_panel.dart`'s `_playheadTimelineSeconds` — both panels place a
/// project-level overlay at "where the preview currently is", just on
/// different lanes.
///
/// Falls back to the end of the last-placed sticker when nothing is
/// selected, so newly-added stickers queue up after whatever's already there
/// instead of all landing on top of each other at 0.
double _playheadTimelineSeconds(WidgetRef ref) {
  final editor = ref.read(editorProvider);
  final idx = editor.selectedIndex;
  if (idx < 0) {
    var end = 0.0;
    for (final s in ref.read(stickerOverlaysProvider)) {
      if (s.end > end) end = s.end;
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

/// A single entry in the sticker catalogue. Emoji categories render the
/// [emoji] glyph directly; [shapeId] entries are built-in, ffmpeg-generated
/// geometric shapes (see `kShapePresets`); everything else is a placeholder
/// until real sticker art ships.
class _Sticker {
  const _Sticker(this.emoji, [this.label, this.shapeId, this.shapeIcon]);

  /// The glyph to render, or null for a non-emoji entry.
  final String? emoji;

  /// Optional accessible/tooltip label.
  final String? label;

  /// For a built-in shape, its [ShapePreset.id] — tapping generates (or
  /// reuses the cached render of) that shape and adds it as an image
  /// sticker. Null for emoji and not-yet-implemented placeholder entries.
  final String? shapeId;

  /// A representative icon shown for a [shapeId] entry while its real PNG
  /// hasn't been generated yet (and as the cell's glyph either way — the
  /// catalogue grid doesn't need to load every shape's actual pixels just to
  /// be browsable).
  final IconData? shapeIcon;
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
    // One entry per `kShapePresets` id — plain, original geometric outlines
    // (never a copyrighted character/logo), generated on first tap by
    // ffmpeg and cached (see `FfmpegEngine.generateShape`).
    _Sticker(null, 'Rectangle', 'rectangle', Icons.crop_square_outlined),
    _Sticker(null, 'Circle', 'circle', Icons.circle_outlined),
    _Sticker(null, 'Arrow', 'arrow', Icons.arrow_forward),
    _Sticker(null, 'Speech bubble', 'speech_bubble',
        Icons.chat_bubble_outline),
  ]),
  const _StickerCategory('Arrows', Icons.north_east, [
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

/// The Stickers tab: a searchable, categorised catalogue up top (emoji, a
/// handful of built-in generated shapes, and still-stubbed placeholder
/// categories), an "Import image" action for the user's own artwork, and the
/// project's placed stickers below.
///
/// Clicking an emoji adds a [StickerOverlay] to the project (timed on the
/// final, concatenated timeline, same as [TextOverlay]) and burns it into
/// the export via ffmpeg's `drawtext` filter (an emoji is just text,
/// rendered with a colour-emoji font — see
/// `FfmpegEngine._resolveUsableEmojiFont`). Clicking a shape or importing an
/// image instead adds an *image* sticker (`StickerOverlay.imagePath`),
/// burned in via `overlay` — see `FfmpegEngine._buildFilterGraph`. Non-shape
/// placeholder categories are still a stub; placing real sticker art there is
/// future work.
class StickersPanel extends ConsumerStatefulWidget {
  const StickersPanel({super.key});

  @override
  ConsumerState<StickersPanel> createState() => _StickersPanelState();
}

class _StickersPanelState extends ConsumerState<StickersPanel> {
  int _categoryIndex = 0;
  String _query = '';
  bool _importing = false;
  String? _generatingShapeId;

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
          child: Row(
            children: [
              Expanded(
                child: VTextField(
                  hint: 'Search stickers',
                  icon: Icons.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              VButton(
                label: _importing ? 'Importing…' : 'Import image',
                icon: _importing ? null : Icons.add_photo_alternate_outlined,
                onPressed: _importing ? null : () => _importImage(context),
              ),
            ],
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
                      itemBuilder: (context, i) => _StickerCell(
                        sticker: stickers[i],
                        busy: stickers[i].shapeId != null &&
                            stickers[i].shapeId == _generatingShapeId,
                        onAddShape: (id) => _addShape(context, id),
                      ),
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

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _importImage(BuildContext context) async {
    await FilePicker.skipEntitlementsChecks();
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kImageExtensions,
      );
      if (!context.mounted) return;
      final paths = files.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return;

      final start = _playheadTimelineSeconds(ref);
      for (final path in paths) {
        ref.read(stickerOverlaysProvider.notifier).addImage(
              path,
              start: start,
              end: start + 3,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(paths.length == 1
                  ? 'Added to the project'
                  : 'Added ${paths.length} images to the project')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _addShape(BuildContext context, String shapeId) async {
    setState(() => _generatingShapeId = shapeId);
    try {
      final path = await ref.read(engineProvider).generateShape(shapeId);
      if (!context.mounted) return;
      final start = _playheadTimelineSeconds(ref);
      ref.read(stickerOverlaysProvider.notifier).addImage(
            path,
            start: start,
            end: start + 3,
          );
      final label =
          kShapePresets.where((p) => p.id == shapeId).firstOrNull?.label ??
              shapeId;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Added "$label" to the project')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Could not add shape: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingShapeId = null);
    }
  }
}

class _StickerCell extends ConsumerWidget {
  const _StickerCell({
    required this.sticker,
    required this.busy,
    required this.onAddShape,
  });

  final _Sticker sticker;
  final bool busy;
  final ValueChanged<String> onAddShape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: sticker.label ?? '',
      child: Material(
        color: AppColors.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: busy ? null : () => _tap(context, ref),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.line),
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : sticker.emoji != null
                    ? Text(sticker.emoji!, style: const TextStyle(fontSize: 26))
                    : Icon(sticker.shapeIcon ?? Icons.image_outlined,
                        size: 22, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  void _tap(BuildContext context, WidgetRef ref) {
    final emoji = sticker.emoji;
    if (emoji != null) {
      ref.read(stickerOverlaysProvider.notifier).add(emoji);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Added $emoji to the project')));
      return;
    }
    final shapeId = sticker.shapeId;
    if (shapeId != null) {
      onAddShape(shapeId);
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
          const SnackBar(content: Text('Placing stickers — coming soon')));
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

/// Edits one placed sticker's timing/position/rotation and lets it be
/// deleted — mirrors `TextPanel`'s `_OverlayTile`. Works the same for an
/// emoji sticker (shows its glyph) and an image sticker (shows a thumbnail
/// of the imported/generated file).
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
          _StickerThumbnail(overlay: overlay),
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
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _DoubleField(
                        value: overlay.size,
                        prefix: 'Size',
                        decimals: 2,
                        onChanged: (d) =>
                            notifier.update(index, overlay.copyWith(size: d)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DoubleField(
                        value: overlay.rotation,
                        prefix: 'Rot',
                        suffix: '°',
                        decimals: 0,
                        onChanged: (d) => notifier.update(
                            index, overlay.copyWith(rotation: d)),
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

/// A small preview of a placed sticker: the emoji glyph, or a thumbnail of
/// an image sticker's file (best-effort — if the file can't be decoded,
/// falls back to a generic icon rather than failing the whole tile).
class _StickerThumbnail extends StatelessWidget {
  const _StickerThumbnail({required this.overlay});

  final StickerOverlay overlay;

  @override
  Widget build(BuildContext context) {
    if (!overlay.isImage) {
      return Text(overlay.emoji ?? '', style: const TextStyle(fontSize: 22));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        color: Colors.black26,
        child: Image.file(
          File(overlay.imagePath!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.image_outlined,
            size: 16,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// A small numeric field for a double value (time/position/size/rotation),
/// editable as text. Keeps its own controller in sync with external changes
/// the same way `inspector_panel.dart`'s `_SecondsField` does.
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
