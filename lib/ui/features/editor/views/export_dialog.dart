import 'package:flutter/material.dart';

import '../../../../domain/models/export_settings.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/rows.dart';

/// A frame-rate choice offered in the dialog. `null` means "source" — don't
/// force a rate, leave [ExportSettings.fps] unset.
class _FpsOption {
  const _FpsOption(this.label, this.value);
  final String label;
  final double? value;
}

const _fpsOptions = [
  _FpsOption('Source', null),
  _FpsOption('24', 24),
  _FpsOption('30', 30),
  _FpsOption('60', 60),
];

/// A resolution choice offered in the dialog. `null`/`null` means "source" —
/// don't scale, leave [ExportSettings.width]/[height] unset.
class _ResOption {
  const _ResOption(this.label, this.width, this.height);
  final String label;
  final int? width;
  final int? height;
}

const _resOptions = [
  _ResOption('Source', null, null),
  _ResOption('720p', 1280, 720),
  _ResOption('1080p', 1920, 1080),
  _ResOption('4K', 3840, 2160),
];

/// Shows the export settings dialog and resolves to the [ExportSettings] the
/// user chose, or `null` if they cancelled.
Future<ExportSettings?> showExportDialog(BuildContext context) =>
    showDialog<ExportSettings>(
      context: context,
      builder: (_) => const Dialog(child: ExportDialog()),
    );

/// Lets the user pick resolution, frame rate, codec, quality and container
/// before an export runs. Purely a settings picker — the caller (the title
/// bar) still owns choosing the output location and driving the engine.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  int? _width;
  int? _height;
  double? _fps;
  ExportCodec _codec = ExportCodec.h264;
  ExportQuality _quality = ExportQuality.recommended;
  ExportFormat _format = ExportFormat.mp4;

  ExportSettings get _settings => ExportSettings(
        width: _width,
        height: _height,
        fps: _fps,
        codec: _codec,
        quality: _quality,
        format: _format,
      );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_upload_outlined,
                    color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Export', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text('Choose the output settings for this export.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 20),

            VPropertyRow(
              label: 'Resolution',
              labelWidth: 96,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in _resOptions)
                    VChip(
                      label: o.label,
                      selected: _width == o.width && _height == o.height,
                      onTap: () =>
                          setState(() {
                        _width = o.width;
                        _height = o.height;
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            VPropertyRow(
              label: 'Frame rate',
              labelWidth: 96,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in _fpsOptions)
                    VChip(
                      label: o.label,
                      selected: _fps == o.value,
                      onTap: () => setState(() => _fps = o.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            VPropertyRow(
              label: 'Codec',
              labelWidth: 96,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ExportCodec.values)
                    VChip(
                      label: c.label,
                      selected: _codec == c,
                      onTap: () => setState(() => _codec = c),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            VPropertyRow(
              label: 'Quality',
              labelWidth: 96,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in ExportQuality.values)
                    VChip(
                      label: q.label,
                      selected: _quality == q,
                      onTap: () => setState(() => _quality = q),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            VPropertyRow(
              label: 'Format',
              labelWidth: 96,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ExportFormat.values)
                    VChip(
                      label: f.label,
                      selected: _format == f,
                      onTap: () => setState(() => _format = f),
                    ),
                ],
              ),
            ),

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
                  label: 'Export',
                  variant: VButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(_settings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
