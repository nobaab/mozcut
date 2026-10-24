import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/aspect_presets.dart';
import '../../../../domain/models/project.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/player_control.dart';
import '../view_models/sticker_overlays_view_model.dart';
import '../view_models/text_overlays_view_model.dart';
import 'ratio_dialog.dart';

/// The centre monitor, modelled on CapCut's Player: a "Player" header, the video
/// in the middle, and a controls bar (timecode, play, fit, aspect, fullscreen).
///
/// By default this previews one clip at a time (the selected one's raw
/// source) — cheap and instant while scrubbing/trimming. The "Render preview"
/// button in the header renders the *whole* timeline (transforms, speed,
/// volume, captions, text overlays — the same filtergraph `export` uses, just
/// small/fast) via [Engine.renderPreview] and loads that proxy instead, so the
/// player can show the real edit on demand.
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

  // True once a timeline proxy (from [Engine.renderPreview]) is loaded —
  // while true, the per-selected-clip raw-source sync below is suppressed so
  // changing the timeline selection doesn't kick the player back to showing
  // one clip's raw source.
  bool _previewMode = false;

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
    final editorState = ref.watch(editorProvider);
    final selected = editorState.selected;
    final hasClips = editorState.clips.isNotEmpty;
    final previewBusy = ref.watch(previewRenderingProvider);
    final canvas = ref.watch(appProvider)?.video ?? const VideoSettings();
    final aspectRatio =
        canvas.height > 0 ? canvas.width / canvas.height : 16 / 9;

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

    if (!hasClips) {
      // Nothing left to show — drop out of preview mode too, so the next
      // import goes back to the normal per-clip sync below.
      if (_loadedPath != null || _previewMode) {
        _loadedPath = null;
        _previewMode = false;
        _player.stop();
      }
    } else if (!_previewMode) {
      // Not showing a timeline proxy: keep the player in sync with whichever
      // clip is selected, same as before "Render preview" existed.
      if (selected != null && selected.sourcePath != _loadedPath) {
        _loadedPath = selected.sourcePath;
        _player.open(Media(selected.sourcePath), play: false);
      } else if (selected == null && _loadedPath != null) {
        _loadedPath = null;
        _player.stop();
      }
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _header(hasClips: hasClips, busy: previewBusy),
          Expanded(
            child: Container(
              color: Colors.black,
              child: !hasClips
                  ? Center(
                      child: Text('Import a video to start',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3))),
                    )
                  // Letterbox/pillarbox to the project's canvas aspect ratio
                  // (black bars fill the rest of this container) — this is
                  // the same framing `export`/`renderPreview` produce, so the
                  // Ratio control visibly reflows the preview the moment it
                  // changes.
                  : Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: Video(
                            controller: _controller, controls: NoVideoControls),
                      ),
                    ),
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  /// Renders the whole timeline (all clips, transforms, speed, volume,
  /// captions, text overlays) to a low-res proxy via [Engine.renderPreview]
  /// and loads it into the player, replacing whatever raw clip was showing.
  Future<void> _renderPreview() async {
    final clips = ref.read(editorProvider).clips;
    if (clips.isEmpty) return;
    final textOverlays = ref.read(textOverlaysProvider);
    final stickerOverlays = ref.read(stickerOverlaysProvider);
    final engine = ref.read(engineProvider);
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();

    ref.read(previewRenderingProvider.notifier).set(true);
    try {
      final path = await engine.renderPreview(
          clips: clips,
          textOverlays: textOverlays,
          stickerOverlays: stickerOverlays,
          canvasWidth: canvas.width,
          canvasHeight: canvas.height);
      if (!mounted) return;
      _previewMode = true;
      _loadedPath = path;
      await _player.open(Media(path), play: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Preview render failed: $e')));
      }
    } finally {
      if (mounted) ref.read(previewRenderingProvider.notifier).set(false);
    }
  }

  Widget _header({required bool hasClips, required bool busy}) => Container(
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
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              VIconButton(
                icon: Icons.movie_creation_outlined,
                tooltip: 'Render preview',
                onPressed: hasClips ? _renderPreview : null,
              ),
            const SizedBox(width: 4),
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
              _ratioControl(),
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

  /// The Ratio control: shows the project's current ratio label and opens
  /// [RatioDialog] on tap — presets, "Original" (probes the first clip via
  /// the engine) and Custom W×H. Picking one calls `App.setCanvas`, which the
  /// preview (letterboxed above) and a later export both pick up.
  Widget _ratioControl() {
    final project = ref.watch(appProvider);
    final video = project?.video ?? const VideoSettings();
    final label = ratioLabelFor(video.width, video.height);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: VChip(
        icon: Icons.aspect_ratio,
        label: label,
        onTap: project == null ? null : () => _openRatioDialog(project.video),
      ),
    );
  }

  Future<void> _openRatioDialog(VideoSettings current) async {
    final clips = ref.read(editorProvider).clips;
    final engine = ref.read(engineProvider);
    final firstClipPath = clips.isEmpty ? null : clips.first.sourcePath;
    final result = await showRatioDialog(
      context,
      current: current,
      probeOriginal:
          firstClipPath == null ? null : () => engine.probeDimensions(firstClipPath),
    );
    if (result == null || !mounted) return;
    ref.read(appProvider.notifier).setCanvas(result.width, result.height);
  }

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
