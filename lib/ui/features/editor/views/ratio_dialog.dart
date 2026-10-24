import 'package:flutter/material.dart';

import '../../../../domain/models/aspect_presets.dart';
import '../../../../domain/models/project.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

/// Shows the Ratio picker (presets + Original + Custom) and resolves to the
/// [VideoSettings] the user applied (same fps as [current]), or `null` if
/// they cancelled. [probeOriginal], if given, offers an "Original" chip that
/// calls it to resolve the first clip's pixel dimensions (snapped to even) —
/// pass `null` (e.g. no clips imported yet) to omit "Original" entirely.
Future<VideoSettings?> showRatioDialog(
  BuildContext context, {
  required VideoSettings current,
  Future<(int, int)> Function()? probeOriginal,
}) =>
    showDialog<VideoSettings>(
      context: context,
      builder: (_) => Dialog(
        child: RatioDialog(current: current, probeOriginal: probeOriginal),
      ),
    );

/// Lets the user pick the project canvas: one of [kAspectPresets], "Original"
/// (matches the first clip), or a free Custom W×H. Purely a settings picker —
/// the caller applies the result via `App.setCanvas`.
class RatioDialog extends StatefulWidget {
  const RatioDialog({super.key, required this.current, this.probeOriginal});

  final VideoSettings current;
  final Future<(int, int)> Function()? probeOriginal;

  @override
  State<RatioDialog> createState() => _RatioDialogState();
}

class _RatioDialogState extends State<RatioDialog> {
  late int _width = widget.current.width;
  late int _height = widget.current.height;
  bool _custom = false;
  bool _probing = false;
  String? _error;

  late final _w = TextEditingController(text: '$_width');
  late final _h = TextEditingController(text: '$_height');

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  bool _isPreset(AspectPreset p) =>
      !_custom && _width == p.width && _height == p.height;

  void _choosePreset(AspectPreset p) => setState(() {
        _custom = false;
        _error = null;
        _width = p.width;
        _height = p.height;
      });

  Future<void> _chooseOriginal() async {
    final probe = widget.probeOriginal;
    if (probe == null) return;
    setState(() {
      _probing = true;
      _error = null;
    });
    try {
      final (w, h) = await probe();
      if (!mounted) return;
      setState(() {
        _custom = false;
        _width = evenClamp(w);
        _height = evenClamp(h);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read the clip: $e');
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  void _chooseCustom() => setState(() {
        _custom = true;
        _error = null;
        _w.text = '$_width';
        _h.text = '$_height';
      });

  /// Reads whatever is currently typed in the W/H fields, clamped/snapped to
  /// an even number, and applies it to `_width`/`_height` — called as the
  /// user types so the preview label (and eventual Apply) always reflect a
  /// valid size, even mid-edit.
  void _applyCustomFields() => setState(() {
        _width = evenClamp(int.tryParse(_w.text) ?? _width);
        _height = evenClamp(int.tryParse(_h.text) ?? _height);
      });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.aspect_ratio, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Ratio', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text('Choose the project canvas.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in kAspectPresets)
                  VChip(
                    label: p.label,
                    selected: _isPreset(p),
                    onTap: () => _choosePreset(p),
                  ),
                if (widget.probeOriginal != null)
                  VChip(
                    label: _probing ? 'Original…' : 'Original',
                    onTap: _probing ? null : _chooseOriginal,
                  ),
                VChip(
                  label: 'Custom',
                  selected: _custom,
                  onTap: _chooseCustom,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_custom)
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: VNumberField(
                      value: _w.text,
                      controller: _w,
                      prefix: 'W',
                      onChanged: (_) => _applyCustomFields(),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('×'),
                  ),
                  SizedBox(
                    width: 110,
                    child: VNumberField(
                      value: _h.text,
                      controller: _h,
                      prefix: 'H',
                      onChanged: (_) => _applyCustomFields(),
                    ),
                  ),
                ],
              )
            else
              Text(
                '$_width × $_height',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                VButton(
                  label: 'Cancel',
                  variant: VButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                VButton(
                  label: 'Apply',
                  variant: VButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(VideoSettings(
                      width: _width, height: _height, fps: widget.current.fps)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
