import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../domain/models/project.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../view_models/launcher_view_model.dart';

/// A preset "video mode": one choice that bundles resolution + fps + aspect,
/// the way every editor's new-project dialog does.
class _Preset {
  const _Preset(this.label, this.icon, this.video);
  final String label;
  final IconData icon;
  final VideoSettings video;
}

const _presets = [
  _Preset('YouTube 1080p', Icons.smart_display_outlined,
      VideoSettings(width: 1920, height: 1080, fps: 30)),
  _Preset('YouTube 4K', Icons.four_k_outlined,
      VideoSettings(width: 3840, height: 2160, fps: 30)),
  _Preset('TikTok / Reels', Icons.phone_iphone,
      VideoSettings(width: 1080, height: 1920, fps: 30)),
  _Preset('Square', Icons.crop_square,
      VideoSettings(width: 1080, height: 1080, fps: 30)),
];

Future<void> showNewProjectDialog(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const Dialog(child: NewProjectDialog()),
    );

class NewProjectDialog extends ConsumerStatefulWidget {
  const NewProjectDialog({super.key});

  @override
  ConsumerState<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<NewProjectDialog> {
  final _name = TextEditingController(text: 'Untitled Project');
  String? _location;
  int _presetIndex = 0;
  bool _custom = false;
  final _w = TextEditingController(text: '1920');
  final _h = TextEditingController(text: '1080');
  final _fps = TextEditingController(text: '30');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveDefaultLocation();
  }

  Future<void> _resolveDefaultLocation() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = '${docs.path}/MozCut Projects';
    if (mounted) setState(() => _location = dir);
  }

  @override
  void dispose() {
    _name.dispose();
    _w.dispose();
    _h.dispose();
    _fps.dispose();
    super.dispose();
  }

  VideoSettings get _video {
    if (!_custom) return _presets[_presetIndex].video;
    return VideoSettings(
      width: int.tryParse(_w.text) ?? 1920,
      height: int.tryParse(_h.text) ?? 1080,
      fps: double.tryParse(_fps.text) ?? 30,
    );
  }

  bool get _canCreate =>
      !_busy && _name.text.trim().isNotEmpty && (_location?.isNotEmpty ?? false);

  Future<void> _chooseLocation() async {
    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Where should the project folder go?');
    if (dir != null) setState(() => _location = dir);
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appProvider.notifier).newProject(
            location: _location!,
            name: _name.text.trim(),
            video: _video,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add, color: Color(0xFF0568FD)),
                const SizedBox(width: 8),
                Text('New Project',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text('These settings apply to the whole edit.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 20),

            // Name
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Location
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      _location ?? 'Resolving…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                VButton(
                  label: 'Choose',
                  onPressed: _busy ? null : _chooseLocation,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Video mode
            const Text('Video mode',
                style: TextStyle(fontSize: 12, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _presets.length; i++)
                  VChip(
                    icon: _presets[i].icon,
                    label: _presets[i].label,
                    selected: !_custom && _presetIndex == i,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _custom = false;
                              _presetIndex = i;
                            }),
                  ),
                VChip(
                  label: 'Custom',
                  selected: _custom,
                  onTap: _busy ? null : () => setState(() => _custom = true),
                ),
              ],
            ),
            if (!_custom)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_presets[_presetIndex].video.label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ),
            if (_custom)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    _num(_w, 'Width'),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('×')),
                    _num(_h, 'Height'),
                    const SizedBox(width: 16),
                    _num(_fps, 'fps'),
                  ],
                ),
              ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style:
                                const TextStyle(color: Colors.redAccent))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                VButton(
                  label: 'Cancel',
                  variant: VButtonVariant.ghost,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                VButton(
                  label: _busy ? 'Creating…' : 'Create',
                  variant: VButtonVariant.primary,
                  onPressed: _canCreate ? _create : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _num(TextEditingController c, String label) => SizedBox(
        width: 84,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}
