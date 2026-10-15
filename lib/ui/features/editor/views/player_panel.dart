import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/player_control.dart';

/// The centre monitor, modelled on CapCut's Player: a "Player" header, the video
/// in the middle, and a controls bar (timecode, play, fit, aspect, fullscreen).
///
/// v0.x previews one clip at a time (the selected one). Full timeline-sequence
/// playback is a later step; export already joins the whole timeline.
class PlayerPanel extends ConsumerStatefulWidget {
  const PlayerPanel({super.key});

  @override
  ConsumerState<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends ConsumerState<PlayerPanel> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  String? _loadedPath;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.stream.position.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
      ref.read(playheadProvider.notifier).set(p.inMilliseconds / 1000.0);
    });
    _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(editorProvider.select((s) => s.selected));

    // Keyboard shortcuts (Space, Left/Right arrow) send commands here rather
    // than touching media_kit directly, since the Player lives in this
    // State's private fields.
    ref.listen<PlayerCommand?>(playerControlProvider, (previous, next) {
      if (next == null || _loadedPath == null) return;
      switch (next.type) {
        case PlayerCommandType.togglePlayPause:
          _player.playOrPause();
          break;
        case PlayerCommandType.seekBy:
          final deltaMs = ((next.seconds ?? 0) * 1000).round();
          final targetMs = (_position.inMilliseconds + deltaMs)
              .clamp(0, _duration.inMilliseconds)
              .toInt();
          _player.seek(Duration(milliseconds: targetMs));
          break;
      }
    });

    if (selected != null && selected.sourcePath != _loadedPath) {
      _loadedPath = selected.sourcePath;
      _player.open(Media(selected.sourcePath), play: false);
    } else if (selected == null && _loadedPath != null) {
      _loadedPath = null;
      _player.stop();
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: Container(
              color: Colors.black,
              child: selected == null
                  ? Center(
                      child: Text('Import a video to start',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3))),
                    )
                  : Video(controller: _controller, controls: NoVideoControls),
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  Widget _header() => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            const Text('Player',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.menu, size: 16, color: Colors.white.withValues(alpha: 0.6)),
          ],
        ),
      );

  Widget _controls() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final valMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          Slider(
            value: maxMs > 0 ? valMs : 0,
            max: maxMs > 0 ? maxMs : 1,
            onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
          ),
          Row(
            children: [
              Text(_tc(_position),
                  style: const TextStyle(
                      fontSize: 12, fontFeatures: [], color: Colors.white70)),
              Text('  /  ${_tc(_duration)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4))),
              const Spacer(),
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => _player.playOrPause(),
              ),
              const Spacer(),
              _ctl(Icons.fit_screen, 'Fit'),
              _customChip(),
              _ctl(Icons.fullscreen, 'Fullscreen'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ctl(IconData icon, String tip) => VIconButton(
        icon: icon,
        tooltip: tip,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$tip — coming soon'))),
      );

  Widget _customChip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: VChip(
          label: 'Custom',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Aspect ratio — coming soon'))),
        ),
      );

  /// HH:MM:SS:FF at 30 fps — CapCut's timecode shape.
  static String _tc(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final f = ((d.inMilliseconds.remainder(1000) / 1000) * 30)
        .floor()
        .toString()
        .padLeft(2, '0');
    return '$h:$m:$s:$f';
  }
}
