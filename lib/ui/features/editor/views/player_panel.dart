import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/aspect_presets.dart';
import '../../../../domain/models/audio_clip.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/sticker_overlay.dart';
import '../../../../domain/models/text_overlay.dart';
import '../../../../domain/models/video_overlay.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/chips.dart';
import '../../launcher/view_models/launcher_view_model.dart';
import '../view_models/audio_clips_view_model.dart';
import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/player_control.dart';
import '../view_models/sticker_overlays_view_model.dart';
import '../view_models/text_overlays_view_model.dart';
import '../view_models/video_overlays_view_model.dart';
import 'ratio_dialog.dart';

/// The centre monitor, modelled on CapCut's Player: a "Player" header, the video
/// in the middle, and a controls bar (timecode, play, fit, aspect, fullscreen).
///
/// The preview is WYSIWYG: whenever the timeline changes (trims, reorders,
/// transforms, speed, volume, overlays, audio clips, canvas ratio) it
/// re-renders the *whole* timeline to a small/fast proxy via
/// [Engine.renderPreview] — the SAME filtergraph `export` uses — and plays
/// that. So the player reflects the real edit: trimmed regions stop where the
/// trim says, the audio lane is audible, overlays show. Re-renders are
/// debounced (so dragging a trim handle only renders once, on release) and
/// coalesced (one render in flight at a time), and playback position/▶ state
/// are preserved across a re-render. The header button forces an immediate
/// re-render.
class PlayerPanel extends ConsumerStatefulWidget {
  const PlayerPanel({super.key});

  @override
  ConsumerState<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends ConsumerState<PlayerPanel> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  /// Preview zoom/pan. Identity = "Fit" (the video letterboxed to the canvas).
  /// Scroll/pinch to zoom in and pan; the Fit button resets this to identity.
  final TransformationController _zoom = TransformationController();

  String? _loadedPath;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  /// Signature of the timeline the currently-loaded proxy was rendered from.
  /// A build whose freshly-computed signature differs schedules a re-render.
  String? _renderedSignature;

  /// Debounce timer: a burst of edits (e.g. a trim drag) collapses into a
  /// single render once they stop.
  Timer? _debounce;

  /// True while an [Engine.renderPreview] call is in flight — a second edit
  /// during that window sets [_renderPending] instead of starting a parallel
  /// render, and we render once more when the current one finishes.
  bool _rendering = false;
  bool _renderPending = false;

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
      if (!mounted) return;
      setState(() => _playing = p);
      // Lets the timeline drive its playback auto-scroll-follow (see
      // `IsPlaying` in editor_ui_state.dart) without holding a reference to
      // this player.
      ref.read(isPlayingProvider.notifier).set(p);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _zoom.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final hasClips = editorState.clips.isNotEmpty;
    final previewBusy = ref.watch(previewRenderingProvider);
    final canvas = ref.watch(appProvider)?.video ?? const VideoSettings();
    final aspectRatio =
        canvas.height > 0 ? canvas.width / canvas.height : 16 / 9;
    // Watched so edits to any lane (not just the video track) trigger a
    // rebuild → signature check → WYSIWYG re-render below.
    final audioClips = ref.watch(audioClipsProvider);
    final videoOverlays = ref.watch(videoOverlaysProvider);
    final textOverlays = ref.watch(textOverlaysProvider);
    final stickerOverlays = ref.watch(stickerOverlaysProvider);

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

    // Scrubbing the ruler/timeline sets the playhead (timeline seconds); seek
    // the preview to match. The player's own position stream also writes the
    // playhead continuously during playback, so only act on a jump big enough
    // to be a deliberate scrub (not the frame-by-frame playback trickle) —
    // that also stops this from fighting the position stream in a loop.
    ref.listen<double>(playheadProvider, (previous, next) {
      if (_loadedPath == null) return;
      final deltaMs = (next * 1000 - _position.inMilliseconds).abs();
      if (deltaMs > 200) {
        _player.seek(Duration(milliseconds: (next * 1000).round()));
      }
    });

    if (!hasClips) {
      // Nothing left to show — tear down any loaded proxy.
      _debounce?.cancel();
      if (_loadedPath != null) {
        _loadedPath = null;
        _renderedSignature = null;
        _player.stop();
      }
    } else {
      // WYSIWYG: if the timeline differs from what the loaded proxy was
      // rendered from, (re)render it. Computed every build, but the actual
      // render is debounced + coalesced so this is cheap during editing.
      final signature = _timelineSignature(
        editorState,
        canvas,
        audioClips,
        videoOverlays,
        textOverlays,
        stickerOverlays,
      );
      if (signature != _renderedSignature) {
        _renderedSignature = signature;
        _scheduleAutoRender();
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
                        child: InteractiveViewer(
                          transformationController: _zoom,
                          clipBehavior: Clip.hardEdge,
                          minScale: 1,
                          maxScale: 5,
                          child: Video(
                              controller: _controller,
                              controls: NoVideoControls),
                        ),
                      ),
                    ),
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  /// A compact fingerprint of everything that affects the rendered preview, so
  /// a rebuild can tell whether the timeline actually changed (vs. e.g. a
  /// selection-only change, which shouldn't trigger a re-render).
  String _timelineSignature(
    EditorState state,
    VideoSettings canvas,
    List<AudioClip> audioClips,
    List<VideoOverlay> videoOverlays,
    List<TextOverlay> textOverlays,
    List<StickerOverlay> stickerOverlays,
  ) {
    return jsonEncode({
      'c': state.clips.map((c) => c.toJson()).toList(),
      'a': audioClips.map((a) => a.toJson()).toList(),
      'v': videoOverlays.map((v) => v.toJson()).toList(),
      't': textOverlays.map((t) => t.toJson()).toList(),
      's': stickerOverlays.map((s) => s.toJson()).toList(),
      'w': canvas.width,
      'h': canvas.height,
    });
  }

  /// Debounce a WYSIWYG re-render: a burst of edits (dragging a trim handle,
  /// typing a caption) collapses into a single render once it settles.
  void _scheduleAutoRender() {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 450), _renderPreviewNow);
  }

  /// Renders the whole timeline (all clips, transforms, speed, volume,
  /// captions, text/sticker/video overlays and the audio lane — the same
  /// filtergraph `export` uses) to a low-res proxy via [Engine.renderPreview]
  /// and loads it, preserving the current position and play state so editing
  /// mid-playback doesn't jump the viewer back to the start. Coalesced: only
  /// one render runs at a time; edits arriving during a render queue exactly
  /// one more.
  Future<void> _renderPreviewNow() async {
    if (_rendering) {
      _renderPending = true;
      return;
    }
    final clips = ref.read(editorProvider).clips;
    if (clips.isEmpty) return;
    final engine = ref.read(engineProvider);
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();

    _rendering = true;
    ref.read(previewRenderingProvider.notifier).set(true);
    // Remember where the viewer was so the re-rendered proxy resumes there.
    final resumeAt = _position;
    final wasPlaying = _playing;
    try {
      final path = await engine.renderPreview(
          clips: clips,
          textOverlays: ref.read(textOverlaysProvider),
          stickerOverlays: ref.read(stickerOverlaysProvider),
          audioClips: ref.read(audioClipsProvider),
          videoOverlays: ref.read(videoOverlaysProvider),
          canvasWidth: canvas.width,
          canvasHeight: canvas.height);
      if (!mounted) return;
      _loadedPath = path;
      await _player.open(Media(path), play: wasPlaying);
      if (resumeAt > Duration.zero) await _player.seek(resumeAt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Preview render failed: $e')));
      }
    } finally {
      _rendering = false;
      if (mounted) ref.read(previewRenderingProvider.notifier).set(false);
      // An edit landed while we were rendering — render exactly once more.
      if (_renderPending && mounted) {
        _renderPending = false;
        _renderPreviewNow();
      }
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
                tooltip: 'Refresh preview now',
                onPressed: hasClips
                    ? () {
                        _debounce?.cancel();
                        _renderPreviewNow();
                      }
                    : null,
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
              _ctl(Icons.fit_screen, 'Fit', _resetZoom),
              _ratioControl(),
              _ctl(Icons.fullscreen, 'Fullscreen', _enterFullscreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ctl(IconData icon, String tip, VoidCallback onPressed) => VIconButton(
        icon: icon,
        tooltip: tip,
        onPressed: onPressed,
      );

  /// "Fit" — reset preview zoom/pan so the video is letterboxed to the canvas.
  void _resetZoom() => _zoom.value = Matrix4.identity();

  /// Fills the whole window with the preview (same [Player]/[VideoController]),
  /// letterboxed to the project's canvas aspect. Esc, the close button, or
  /// tapping the background exits; playback state is unchanged (same player).
  void _enterFullscreen() {
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();
    final aspect = canvas.height > 0 ? canvas.width / canvas.height : 16 / 9;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (ctx, _, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              () => Navigator.of(ctx).pop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: Video(
                        controller: _controller, controls: NoVideoControls),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit,
                        color: Colors.white, size: 28),
                    tooltip: 'Exit full screen (Esc)',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: IconButton(
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 40),
                      onPressed: () => _player.playOrPause(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

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
