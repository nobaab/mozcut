import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/editor_state.dart';

/// The video monitor: shows the selected clip, with play/pause and a scrubber.
///
/// v0.1 previews one clip at a time (the selected one). Full timeline-sequence
/// playback is a later step; export already joins the whole timeline.
class PreviewPanel extends ConsumerStatefulWidget {
  const PreviewPanel({super.key});

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel> {
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
      ref.read(playheadProvider.notifier).state = p.inMilliseconds / 1000.0;
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

  /// Current playhead position in source seconds (what split/trim use).
  double get playheadSeconds => _position.inMilliseconds / 1000.0;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(editorProvider.select((s) => s.selected));

    // Load the selected clip into the player when it changes.
    if (selected != null && selected.sourcePath != _loadedPath) {
      _loadedPath = selected.sourcePath;
      _player.open(Media(selected.sourcePath), play: false);
    } else if (selected == null && _loadedPath != null) {
      _loadedPath = null;
      _player.stop();
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: selected == null
                ? const Center(
                    child: Text(
                      'Import a video to start\n(⌘O or the + button)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : Video(controller: _controller, controls: NoVideoControls),
          ),
        ),
        _TransportBar(
          playing: _playing,
          position: _position,
          duration: _duration,
          onPlayPause: () => _player.playOrPause(),
          onSeek: (d) => _player.seek(d),
        ),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF1F2026),
      child: Row(
        children: [
          IconButton(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: onPlayPause,
          ),
          Text(_fmt(position), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: max > 0 ? value : 0,
              max: max > 0 ? max : 1,
              onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
            ),
          ),
          Text(_fmt(duration), style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
