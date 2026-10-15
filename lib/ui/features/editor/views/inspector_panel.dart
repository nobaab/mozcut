import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/clip.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';

/// The inspector, modelled on CapCut: Video / Audio / Speed / Animation /
/// Adjustment tabs, with the Video tab's Basic / Remove BG / Mask / Retouch
/// sub-tabs and the Transform + Blend sections. Transform (scale / position /
/// rotation / flip) and Trim & Edit are wired to the real engine; Blend is
/// still a visual placeholder.
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rightTab = ref.watch(rightTabProvider);
    final clip = ref.watch(editorProvider.select((s) => s.selected));

    return Container(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabs(ref, rightTab),
          Expanded(
            child: clip == null
                ? Center(
                    child: Text('Select a clip to see its details.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35))),
                  )
                : switch (rightTab) {
                    EditorRightTab.video => _VideoTab(),
                    EditorRightTab.speed =>
                      _SpeedTab(key: ValueKey(clip.id)),
                    EditorRightTab.audio => _AudioTab(),
                    EditorRightTab.adjustment => _AdjustmentTab(),
                    _ => _ComingSoon(label: rightTab.label),
                  },
          ),
        ],
      ),
    );
  }

  Widget _tabs(WidgetRef ref, EditorRightTab active) => Container(
        height: 42,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in EditorRightTab.values)
                InkWell(
                  onTap: () => ref.read(rightTabProvider.notifier).set(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: t == active
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(t.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              t == active ? FontWeight.w600 : FontWeight.w400,
                          color: t == active
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.7),
                        )),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _VideoTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(videoSubProvider);
    final clip = ref.watch(editorProvider.select((s) => s.selected))!;
    final editor = ref.read(editorProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Sub-tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in VideoSubTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.label, style: const TextStyle(fontSize: 12)),
                    selected: s == sub,
                    onSelected: (_) =>
                        ref.read(videoSubProvider.notifier).set(s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (sub == VideoSubTab.basic) ...[
          _SectionHeader('Transform'),
          _scaleRow(editor, clip),
          // Scale is a single uniform factor (no separate X/Y scale), so
          // this toggle stays decorative — there is nothing to turn off.
          _toggleRow('Uniform scale', true),
          _positionRow(editor, clip),
          _rotateRow(editor, clip),
          _flipRow(editor, clip),
          const SizedBox(height: 8),
          _alignRow(editor),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 15),
              label: const Text('Reset transform'),
              onPressed: editor.resetTransform,
            ),
          ),
          const SizedBox(height: 18),
          _SectionHeader('Blend', hasCheckbox: true),
          _sliderRow('Opacity', 1.0, 0, 1, '100%'),
          _fieldRow('Blend mode', 'Normal'),
          const SizedBox(height: 18),

          // ── the wired bits ──
          _SectionHeader('Trim'),
          _readonly('In', '${clip.inPoint.toStringAsFixed(2)}s'),
          _readonly('Out', '${clip.outPoint.toStringAsFixed(2)}s'),
          _readonly('Duration', '${clip.duration.toStringAsFixed(2)}s'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.first_page, size: 15),
                label: const Text('Set In'),
                onPressed: () =>
                    editor.trimSelected(inPoint: ref.read(playheadProvider)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.last_page, size: 15),
                label: const Text('Set Out'),
                onPressed: () =>
                    editor.trimSelected(outPoint: ref.read(playheadProvider)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_cut, size: 15),
            label: const Text('Split at playhead'),
            onPressed: () =>
                editor.splitSelectedAt(ref.read(playheadProvider)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline, size: 15),
            label: const Text('Delete clip'),
            style:
                OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: editor.removeSelected,
          ),
        ] else
          _ComingSoon(label: sub.label),
      ],
    );
  }

  // ── little rows (visual unless noted) ──
  Widget _sliderRow(String label, double v, double min, double max, String r) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 56, child: Text(label, style: _lbl)),
          Expanded(
              child: Slider(value: v, min: min, max: max, onChanged: (_) {})),
          SizedBox(width: 44, child: Text(r, textAlign: TextAlign.right, style: _lbl)),
        ]),
      );

  // ── Transform rows (wired to the selected clip) ──

  /// Scale: 0% .. 400%, 100% = clip's "fit to canvas" size (see
  /// Clip.scale / FfmpegEngine's filter chain).
  Widget _scaleRow(Editor editor, Clip clip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 56, child: Text('Scale', style: _lbl)),
          Expanded(
            child: Slider(
              value: clip.scale.clamp(0.0, 4.0).toDouble(),
              min: 0,
              max: 4,
              onChanged: (v) => editor.updateTransform(scale: v),
            ),
          ),
          SizedBox(
            width: 56,
            child: _LiveField(
              value: (clip.scale * 100).round().toString(),
              suffix: '%',
              onChanged: (text) {
                final v = double.tryParse(text);
                if (v != null) editor.updateTransform(scale: v / 100);
              },
            ),
          ),
        ]),
      );

  /// Position: posX/posY are normalized -1..1 (see Clip's doc comments),
  /// shown here as a percentage of half the canvas for readability.
  Widget _positionRow(Editor editor, Clip clip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 56, child: Text('Position', style: _lbl)),
          Expanded(
            child: _LiveField(
              value: (clip.posX * 100).round().toString(),
              prefix: 'X',
              onChanged: (text) {
                final v = double.tryParse(text);
                if (v != null) editor.updateTransform(posX: v / 100);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LiveField(
              value: (clip.posY * 100).round().toString(),
              prefix: 'Y',
              onChanged: (text) {
                final v = double.tryParse(text);
                if (v != null) editor.updateTransform(posY: v / 100);
              },
            ),
          ),
        ]),
      );

  Widget _rotateRow(Editor editor, Clip clip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 90, child: Text('Rotate', style: _lbl)),
          Expanded(
            child: _LiveField(
              value: clip.rotation.round().toString(),
              suffix: '°',
              onChanged: (text) {
                final v = double.tryParse(text);
                if (v != null) editor.updateTransform(rotation: v);
              },
            ),
          ),
        ]),
      );

  Widget _flipRow(Editor editor, Clip clip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text('Flip horizontal', style: _lbl)),
          Switch(
            value: clip.flipH,
            onChanged: (v) => editor.updateTransform(flipH: v),
          ),
        ]),
      );

  Widget _toggleRow(String label, bool on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: _lbl)),
          Switch(value: on, onChanged: (_) {}),
        ]),
      );

  Widget _fieldRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label, style: _lbl)),
          Expanded(child: _miniField(null, value)),
        ]),
      );

  Widget _miniField(String? prefix, String value) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.well,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          if (prefix != null)
            Text('$prefix ',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
          Text(value, style: const TextStyle(fontSize: 12)),
        ]),
      );

  /// Quick-align buttons: set posX/posY straight to an edge or center.
  Widget _alignRow(Editor editor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _alignIcon(Icons.align_horizontal_left,
              () => editor.updateTransform(posX: -1)),
          _alignIcon(Icons.align_horizontal_center,
              () => editor.updateTransform(posX: 0)),
          _alignIcon(Icons.align_horizontal_right,
              () => editor.updateTransform(posX: 1)),
          _alignIcon(Icons.align_vertical_top,
              () => editor.updateTransform(posY: -1)),
          _alignIcon(Icons.align_vertical_center,
              () => editor.updateTransform(posY: 0)),
          _alignIcon(Icons.align_vertical_bottom,
              () => editor.updateTransform(posY: 1)),
        ],
      );

  Widget _alignIcon(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 18),
        ),
      );

  Widget _readonly(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 72, child: Text(label, style: _lbl)),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
        ]),
      );

  static final _lbl =
      TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5));
}

/// The Speed tab: preset chips (0.5x/1x/2x/4x) plus a custom numeric field,
/// reading/writing the selected clip's [Clip.speed]. Keyed by clip id from
/// the parent so switching the selected clip gives this a fresh controller
/// rather than showing stale text.
class _SpeedTab extends ConsumerStatefulWidget {
  const _SpeedTab({super.key});

  @override
  ConsumerState<_SpeedTab> createState() => _SpeedTabState();
}

class _SpeedTabState extends ConsumerState<_SpeedTab> {
  static const _presets = [0.5, 1.0, 2.0, 4.0];

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final clip = ref.read(editorProvider).selected!;
    _controller = TextEditingController(text: _format(clip.speed));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _format(double speed) => speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toStringAsFixed(2);

  void _applyPreset(double speed) {
    ref.read(editorProvider.notifier).setSelectedSpeed(speed);
    _controller.text = _format(speed);
  }

  void _applyCustom(String text) {
    final parsed = double.tryParse(text);
    if (parsed != null && parsed > 0) {
      ref.read(editorProvider.notifier).setSelectedSpeed(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorProvider.select((s) => s.selected))!;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const VSectionHeader('Speed'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              VChip(
                label: '${_format(p)}x',
                selected: (clip.speed - p).abs() < 0.001,
                onTap: () => _applyPreset(p),
              ),
          ],
        ),
        const SizedBox(height: 16),
        VPropertyRow(
          label: 'Custom',
          child: VNumberField(
            value: _controller.text,
            controller: _controller,
            suffix: 'x',
            onChanged: _applyCustom,
          ),
        ),
        const SizedBox(height: 18),
        const VSectionHeader('Result'),
        VPropertyRow(
          label: 'Duration',
          child: Text('${clip.duration.toStringAsFixed(2)}s',
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.hasCheckbox = false});
  final String label;
  final bool hasCheckbox;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          if (hasCheckbox)
            SizedBox(
              width: 22,
              child: Checkbox(value: true, onChanged: (_) {}),
            ),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(Icons.expand_more,
              size: 18, color: Colors.white.withValues(alpha: 0.5)),
        ]),
      );
}

/// A compact numeric text field used by the Transform rows. Displays
/// [value] (as text) and reports committed edits via [onChanged] — on
/// Enter, or when the field loses focus. Re-syncs its text from [value]
/// whenever it isn't focused, so external changes (slider drag, selecting
/// a different clip, Reset) show up without clobbering live typing.
class _LiveField extends StatefulWidget {
  const _LiveField({
    required this.value,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? prefix;
  final String? suffix;

  @override
  State<_LiveField> createState() => _LiveFieldState();
}

class _LiveFieldState extends State<_LiveField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onChanged(_controller.text);
    });
  }

  @override
  void didUpdateWidget(covariant _LiveField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.well,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.centerLeft,
        child: Row(children: [
          if (widget.prefix != null)
            Text('${widget.prefix} ',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                suffixText: widget.suffix,
                suffixStyle: const TextStyle(fontSize: 12),
              ),
              onSubmitted: widget.onChanged,
            ),
          ),
        ]),
      );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('$label — coming soon',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
        ),
      );
}

/// The Audio tab: volume (0–200%, default 100) and fade in/out (seconds),
/// wired to [Editor.updateSelectedAudio] and, on export, to ffmpeg's
/// `volume`/`afade` filters.
class _AudioTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(editorProvider.select((s) => s.selected))!;
    final editor = ref.read(editorProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        VSectionHeader('Volume'),
        VPropertyRow(
          label: 'Volume',
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: clip.volume.clamp(0.0, 2.0),
                  min: 0,
                  max: 2,
                  onChanged: (v) => editor.updateSelectedAudio(volume: v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${(clip.volume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        VSectionHeader('Fade'),
        VPropertyRow(
          label: 'Fade in',
          child: _SecondsField(
            key: ValueKey('${clip.id}-fadeIn'),
            value: clip.fadeIn,
            onChanged: (v) => editor.updateSelectedAudio(fadeIn: v),
          ),
        ),
        VPropertyRow(
          label: 'Fade out',
          child: _SecondsField(
            key: ValueKey('${clip.id}-fadeOut'),
            value: clip.fadeOut,
            onChanged: (v) => editor.updateSelectedAudio(fadeOut: v),
          ),
        ),
      ],
    );
  }
}

/// A small numeric field for a seconds value (fade in/out), editable as text.
/// Keeps its own controller in sync with external changes (e.g. switching
/// the selected clip) the same way the captions panel syncs its text field.
class _SecondsField extends StatefulWidget {
  const _SecondsField({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant _SecondsField oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    return VNumberField(
      value: _fmt(widget.value),
      controller: _controller,
      suffix: 's',
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null && parsed >= 0) widget.onChanged(parsed);
      },
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// The Adjustment tab: Brightness / Contrast / Saturation sliders wired to
/// the selected clip's manual colour correction (independent of any applied
/// filter preset — see the Filters panel), plus a Reset. On export these
/// become an `eq=...` stage layered on top of the clip's filter preset, if
/// any (see FfmpegEngine's `_videoFilterChain`).
class _AdjustmentTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(editorProvider.select((s) => s.selected))!;
    final editor = ref.read(editorProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        VSectionHeader('Color'),
        VPropertyRow(
          label: 'Brightness',
          child: _adjustSlider(
            value: clip.brightness,
            min: -1,
            max: 1,
            display: '${(clip.brightness * 100).round()}',
            onChanged: (v) => editor.updateSelectedColor(brightness: v),
          ),
        ),
        VPropertyRow(
          label: 'Contrast',
          child: _adjustSlider(
            value: clip.contrast,
            min: 0,
            max: 2,
            display: '${(clip.contrast * 100).round()}%',
            onChanged: (v) => editor.updateSelectedColor(contrast: v),
          ),
        ),
        VPropertyRow(
          label: 'Saturation',
          child: _adjustSlider(
            value: clip.saturation,
            min: 0,
            max: 2,
            display: '${(clip.saturation * 100).round()}%',
            onChanged: (v) => editor.updateSelectedColor(saturation: v),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt, size: 15),
            label: const Text('Reset'),
            onPressed: editor.resetColor,
          ),
        ),
        if (clip.filterId != null) ...[
          const SizedBox(height: 18),
          VSectionHeader('Filter'),
          VPropertyRow(
            label: 'Applied',
            child: Text(clip.filterId!, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }

  Widget _adjustSlider({
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) =>
      Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(display,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      );
}
