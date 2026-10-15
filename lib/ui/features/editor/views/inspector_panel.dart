import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/rows.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';

/// The inspector, modelled on CapCut: Video / Audio / Speed / Animation /
/// Adjustment tabs, with the Video tab's Basic / Remove BG / Mask / Retouch
/// sub-tabs and the Transform + Blend sections. Transform controls are visual
/// for now; Trim & Edit at the bottom are wired to the real engine.
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
          _sliderRow('Scale', 1.0, 0, 4, '100%'),
          _toggleRow('Uniform scale', true),
          _xyRow('Position', 'X', 'Y'),
          _fieldRow('Rotate', '0°'),
          const SizedBox(height: 8),
          _alignRow(),
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

  Widget _toggleRow(String label, bool on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: _lbl)),
          Switch(value: on, onChanged: (_) {}),
        ]),
      );

  Widget _xyRow(String label, String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 56, child: Text(label, style: _lbl)),
          Expanded(child: _miniField(a, '0')),
          const SizedBox(width: 8),
          Expanded(child: _miniField(b, '0')),
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

  Widget _alignRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Icon(Icons.align_horizontal_left, size: 18),
          Icon(Icons.align_horizontal_center, size: 18),
          Icon(Icons.align_horizontal_right, size: 18),
          Icon(Icons.align_vertical_top, size: 18),
          Icon(Icons.align_vertical_center, size: 18),
          Icon(Icons.align_vertical_bottom, size: 18),
        ],
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
