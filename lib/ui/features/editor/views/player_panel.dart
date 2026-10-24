import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/aspect_presets.dart';
import '../../../../domain/models/audio_clip.dart';
import '../../../../domain/models/clip.dart';
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
import 'player/gizmo_layer.dart';
import 'player/overlay_layer.dart';
import 'player/player_geometry.dart';
import 'ratio_dialog.dart';

/// The centre monitor, modelled on CapCut's Player (docs/PLAYER-BEHAVIOR.md).
///
/// The default preview is a **real-time composite**: a single media_kit player
/// bound to the raw clip under the timeline playhead (seeked, never a proxy —
/// see [clipAt]/[sourceTimeOf]), with the clip's transform applied to the
/// [Video] widget, and text/sticker/PiP overlays plus the selection's transform
/// gizmo drawn as Flutter widgets on top. This is instant and always shows a
/// real frame (spec §2, §7).
///
/// The ffmpeg proxy (the old default) is demoted to an explicit "Accurate
/// preview" the header button renders on demand — it alone shows colour/effects/
/// transitions and the full audio mix. Any edit returns to the live composite.
class PlayerPanel extends ConsumerStatefulWidget {
  const PlayerPanel({super.key});

  @override
  ConsumerState<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends ConsumerState<PlayerPanel> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  /// Preview zoom/pan. Identity = "Fit" (the video letterboxed to the canvas).
  final TransformationController _zoom = TransformationController();

  /// The playhead in timeline seconds — the single source of truth this panel
  /// drives [playheadProvider] from (NOT raw player position, which is *source*
  /// time; see spec §5.2).
  double _timelineT = 0;

  /// Raw player position (source seconds within the open clip, or proxy seconds
  /// in accurate mode).
  Duration _rawPosition = Duration.zero;
  bool _playing = false;

  /// The media currently open in the player, and which clip it belongs to.
  /// Media is only re-[open]ed when [_loadedSourcePath] would change (crossing
  /// a clip boundary); within a clip we just [seek] (spec §5.2).
  String? _loadedSourcePath;
  Clip? _currentClip;
  double _currentClipStart = 0;

  /// True between an `open` and its forced `seek`, so position events during
  /// that window don't drive the timeline clock.
  bool _opening = false;

  // ── gizmo preview (spec §3): the in-progress transform during a drag,
  // applied locally to the video + gizmo and committed once on pointer-up.
  double? _pScale, _pPosX, _pPosY, _pRot;

  // ── accurate preview (the opt-in ffmpeg proxy, spec §6/§7) ──
  bool _accurate = false;
  String? _accurateSignature;
  bool _rendering = false;

  static const double _frameEps = 0.04; // ~1 frame at 25fps

  @override
  void initState() {
    super.initState();
    _player.stream.position.listen(_onPosition);
    _player.stream.playing.listen(_onPlaying);
    _zoom.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoomChanged);
    _zoom.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── player stream handlers ─────────────────────────────────────────────

  void _onPlaying(bool p) {
    if (!mounted) return;
    setState(() => _playing = p);
    // Lets the timeline drive its playback auto-scroll-follow (see `IsPlaying`
    // in editor_ui_state.dart) without holding a reference to this player.
    ref.read(isPlayingProvider.notifier).set(p);
  }

  void _onPosition(Duration p) {
    if (!mounted) return;
    _rawPosition = p;
    if (_accurate) {
      // The proxy's timeline IS the project timeline, 1:1.
      setState(() => _timelineT = p.inMilliseconds / 1000.0);
      _writePlayhead();
      return;
    }
    if (_opening) return;
    if (_playing && _currentClip != null) _drivePlayback(p);
  }

  void _onZoomChanged() {
    // Toggle gizmo visibility as the user zooms (gizmo only shows while fit).
    if (mounted) setState(() {});
  }

  double get _zoomScale => _zoom.value.getMaxScaleOnAxis();

  void _writePlayhead() =>
      ref.read(playheadProvider.notifier).set(_timelineT);

  static double _safeRate(double speed) => speed.clamp(0.1, 8.0).toDouble();

  // ── cross-clip playback driver (spec §5.2, P4) ─────────────────────────

  /// During playback, maps the raw (source-time) position back to timeline time
  /// and advances across clip boundaries by opening the next clip.
  void _drivePlayback(Duration p) {
    final clip = _currentClip!;
    final total = ref.read(editorProvider).totalDuration;
    final srcSec = p.inMilliseconds / 1000.0;
    if (srcSec >= clip.outPoint - _frameEps) {
      _advancePlayback(total);
      return;
    }
    final speed = clip.speed <= 0 ? 1.0 : clip.speed;
    final timelineLocal = (srcSec - clip.inPoint) / speed;
    setState(() =>
        _timelineT = (_currentClipStart + timelineLocal).clamp(0.0, total));
    _writePlayhead();
  }

  void _advancePlayback(double total) {
    final clips = ref.read(editorProvider).clips;
    final nextStart = _currentClipStart + (_currentClip?.duration ?? 0);
    if (nextStart >= total - 1e-3) {
      // Reached the end of the timeline — stop on the last frame.
      _player.pause();
      setState(() => _timelineT = total);
      _writePlayhead();
      return;
    }
    final hit = clipAt(nextStart, clips);
    if (hit == null) {
      _player.pause();
      return;
    }
    setState(() => _timelineT = nextStart);
    _writePlayhead();
    _openClip(hit.$1, hit.$2, play: true, atTimeline: nextStart);
  }

  /// Opens (only when the source path changes) or seeks the player to show the
  /// frame at timeline time [atTimeline] (or the clip's in-point if null).
  /// After any `open(play:false)` it forces a `seek` so media_kit paints the
  /// target frame — the core black-screen fix (spec §7.2).
  Future<void> _openClip(
    Clip clip,
    double clipStart, {
    required bool play,
    double? atTimeline,
  }) async {
    _opening = true;
    _currentClip = clip;
    _currentClipStart = clipStart;
    final srcSec = atTimeline != null
        ? sourceTimeOf(clip, clipStart, atTimeline)
        : clip.inPoint;
    final seekTo = Duration(
        milliseconds:
            (srcSec.clamp(0.0, clip.sourceDuration) * 1000).round());
    try {
      if (clip.sourcePath != _loadedSourcePath) {
        _loadedSourcePath = clip.sourcePath;
        await _player.open(Media(clip.sourcePath), play: play);
        await _player.setRate(_safeRate(clip.speed));
        await _player.seek(seekTo);
      } else {
        await _player.seek(seekTo);
        await _player.setRate(_safeRate(clip.speed));
        if (play && !_playing) await _player.play();
      }
    } catch (_) {
      // Opening/seeking can fail transiently (e.g. a just-deleted clip); the
      // next reconcile pass recovers.
    } finally {
      _opening = false;
    }
  }

  /// Reconciles the open media with the current playhead on every build (the
  /// default/real-time path). Opens the next clip on a boundary crossing;
  /// while paused, re-seeks if a trim/reorder moved the frame under the
  /// playhead. No-op in accurate mode or mid-open.
  void _reconcile(List<Clip> clips) {
    if (_accurate || _opening) return;
    final hit = clipAt(_timelineT, clips);
    if (hit == null) return;
    final (clip, clipStart) = hit;
    if (clip.sourcePath != _loadedSourcePath) {
      _openClip(clip, clipStart, play: _playing, atTimeline: _timelineT);
    } else if (!_playing) {
      _currentClip = clip;
      _currentClipStart = clipStart;
      final desired =
          sourceTimeOf(clip, clipStart, _timelineT).clamp(0.0, clip.sourceDuration);
      final rawSec = _rawPosition.inMilliseconds / 1000.0;
      if ((rawSec - desired).abs() > 0.2) {
        _player.seek(Duration(milliseconds: (desired * 1000).round()));
      }
    }
  }

  /// Scrub/jump to timeline time [target]: writes the playhead and opens/seeks
  /// the player to match.
  Future<void> _jumpTo(double target) async {
    final clips = ref.read(editorProvider).clips;
    final total = ref.read(editorProvider).totalDuration;
    final t = target.clamp(0.0, total).toDouble();
    setState(() => _timelineT = t);
    _writePlayhead();
    if (_accurate) {
      await _player.seek(Duration(milliseconds: (t * 1000).round()));
      return;
    }
    final hit = clipAt(t, clips);
    if (hit != null) {
      await _openClip(hit.$1, hit.$2, play: _playing, atTimeline: t);
    }
  }

  void _togglePlay() {
    final total = ref.read(editorProvider).totalDuration;
    if (_playing) {
      _player.pause();
      return;
    }
    if (_accurate) {
      _player.play();
      return;
    }
    if (_timelineT >= total - 1e-3) {
      _jumpTo(0).then((_) => _player.play());
      return;
    }
    if (_loadedSourcePath == null) {
      _jumpTo(_timelineT).then((_) => _player.play());
      return;
    }
    _player.play();
  }

  // ── accurate preview (proxy) ───────────────────────────────────────────

  Future<void> _renderAccuratePreview() async {
    if (_rendering) return;
    final clips = ref.read(editorProvider).clips;
    if (clips.isEmpty) return;
    final engine = ref.read(engineProvider);
    final canvas = ref.read(appProvider)?.video ?? const VideoSettings();
    _rendering = true;
    ref.read(previewRenderingProvider.notifier).set(true);
    final resumeAt = _timelineT;
    final wasPlaying = _playing;
    try {
      final path = await engine.renderPreview(
        clips: clips,
        textOverlays: ref.read(textOverlaysProvider),
        stickerOverlays: ref.read(stickerOverlaysProvider),
        audioClips: ref.read(audioClipsProvider),
        videoOverlays: ref.read(videoOverlaysProvider),
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
      );
      if (!mounted) return;
      _accurateSignature = _timelineSignature(
        ref.read(editorProvider),
        canvas,
        ref.read(audioClipsProvider),
        ref.read(videoOverlaysProvider),
        ref.read(textOverlaysProvider),
        ref.read(stickerOverlaysProvider),
      );
      // Mark the proxy as the loaded media so leaving accurate mode reopens the
      // raw clip (its path won't match this proxy's).
      _loadedSourcePath = path;
      await _player.open(Media(path), play: wasPlaying);
      await _player.seek(Duration(milliseconds: (resumeAt * 1000).round()));
      setState(() => _accurate = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text('Accurate preview failed: $e')));
      }
    } finally {
      _rendering = false;
      if (mounted) ref.read(previewRenderingProvider.notifier).set(false);
    }
  }

  void _exitAccurate() {
    if (!_accurate) return;
    setState(() => _accurate = false);
    // Force the reconcile pass to reopen the raw clip under the playhead.
    _loadedSourcePath = null;
    _jumpTo(_timelineT);
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final clips = editorState.clips;
    final hasClips = clips.isNotEmpty;
    final previewBusy = ref.watch(previewRenderingProvider);
    final canvas = ref.watch(appProvider)?.video ?? const VideoSettings();
    final aspectRatio =
        canvas.height > 0 ? canvas.width / canvas.height : 16 / 9;
    final total = editorState.totalDuration;

    // Watched so overlay edits rebuild the live composite (and feed the
    // accurate-preview invalidation below).
    final audioClips = ref.watch(audioClipsProvider);
    final videoOverlays = ref.watch(videoOverlaysProvider);
    final textOverlays = ref.watch(textOverlaysProvider);
    final stickerOverlays = ref.watch(stickerOverlaysProvider);

    // Keyboard shortcuts (Space, arrows) come through the command bus.
    ref.listen<PlayerCommand?>(playerControlProvider, (previous, next) {
      if (next == null || !hasClips) return;
      switch (next.type) {
        case PlayerCommandType.togglePlayPause:
          _togglePlay();
          break;
        case PlayerCommandType.seekBy:
          _jumpTo(_timelineT + (next.seconds ?? 0));
          break;
      }
    });

    // Scrubbing the ruler/timeline sets the playhead (timeline seconds); seek
    // the preview to match. Our own playback writes also land here, so only act
    // on a jump big enough to be a deliberate scrub (not the playback trickle).
    ref.listen<double>(playheadProvider, (previous, next) {
      if (!hasClips) return;
      if ((next - _timelineT).abs() <= 0.2) return;
      _jumpTo(next);
    });

    if (!hasClips) {
      // Nothing to show — tear everything down.
      if (_loadedSourcePath != null || _timelineT != 0) {
        _loadedSourcePath = null;
        _currentClip = null;
        _accurate = false;
        _timelineT = 0;
        _player.stop();
      }
    } else {
      if (_timelineT > total) _timelineT = total;
      _reconcile(clips);
      // Leaving accurate mode on any edit (spec §7).
      if (_accurate) {
        final sig = _timelineSignature(editorState, canvas, audioClips,
            videoOverlays, textOverlays, stickerOverlays);
        if (sig != _accurateSignature) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _exitAccurate();
          });
        }
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
                  : Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: LayoutBuilder(
                          builder: (ctx, constraints) => _monitor(
                            constraints.maxWidth,
                            constraints.maxHeight,
                            editorState,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          _controls(total),
        ],
      ),
    );
  }

  /// The letterboxed monitor stack (spec §2.1): black canvas, the base video
  /// with its transform, the overlay layer, and the selection gizmo.
  Widget _monitor(double dW, double dH, EditorState editorState) {
    final hit = clipAt(_timelineT, editorState.clips);
    final baseClip = hit?.$1;
    final clipStart = hit?.$2 ?? 0;
    final clipT = baseClip == null
        ? 0.0
        : (_timelineT - clipStart).clamp(0.0, baseClip.duration);

    final selected = editorState.selected;
    final showGizmo = !_accurate &&
        baseClip != null &&
        selected != null &&
        selected.id == baseClip.id &&
        _zoomScale <= 1.01;

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.black)),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 5,
            child: _videoLayer(baseClip, dW, dH, clipT),
          ),
        ),
        if (!_accurate)
          Positioned.fill(
            child: OverlayLayer(
                timelineT: _timelineT, displayW: dW, displayH: dH),
          ),
        if (showGizmo)
          Positioned.fill(
            child: _gizmo(baseClip, dW, dH, clipT),
          ),
        Positioned(top: 8, left: 8, child: _modeBadge()),
      ],
    );
  }

  /// The base [Video], wrapped in the clip's transform + opacity, evaluated at
  /// the playhead via [Clip.valueAt] so keyframes animate live (spec §2.2). In
  /// accurate mode the proxy already bakes the transform in, so the video is
  /// shown untransformed.
  Widget _videoLayer(Clip? baseClip, double dW, double dH, double clipT) {
    final theVideo = Video(controller: _controller, controls: NoVideoControls);
    if (_accurate || baseClip == null) return theVideo;

    final s = _pScale ?? baseClip.valueAt(kKeyframeScale, clipT);
    final px = (_pPosX ?? baseClip.valueAt(kKeyframePosX, clipT)) * dW / 2;
    final py = (_pPosY ?? baseClip.valueAt(kKeyframePosY, clipT)) * dH / 2;
    final rot = (_pRot ?? baseClip.valueAt(kKeyframeRotation, clipT)) *
        math.pi /
        180.0;
    final op = baseClip.valueAt(kKeyframeOpacity, clipT).clamp(0.0, 1.0);

    return Opacity(
      opacity: op,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(px, py, 0, 1)
          ..rotateZ(rot)
          ..scaleByDouble(s * (baseClip.flipH ? -1.0 : 1.0), s, 1, 1),
        child: theVideo,
      ),
    );
  }

  Widget _gizmo(Clip baseClip, double dW, double dH, double clipT) {
    return GizmoLayer(
      scale: _pScale ?? baseClip.valueAt(kKeyframeScale, clipT),
      posX: _pPosX ?? baseClip.valueAt(kKeyframePosX, clipT),
      posY: _pPosY ?? baseClip.valueAt(kKeyframePosY, clipT),
      rotationDeg: _pRot ?? baseClip.valueAt(kKeyframeRotation, clipT),
      displayW: dW,
      displayH: dH,
      onPreview: (t) => setState(() {
        if (t.scale != null) _pScale = t.scale;
        if (t.posX != null) _pPosX = t.posX;
        if (t.posY != null) _pPosY = t.posY;
        if (t.rotation != null) _pRot = t.rotation;
      }),
      onCommit: (t) {
        ref.read(editorProvider.notifier).updateTransform(
              scale: t.scale,
              posX: t.posX,
              posY: t.posY,
              rotation: t.rotation,
            );
        setState(() {
          _pScale = null;
          _pPosX = null;
          _pPosY = null;
          _pRot = null;
        });
      },
    );
  }

  Widget _modeBadge() {
    if (_accurate) {
      return _Badge(
        label: 'Accurate preview',
        color: const Color(0xFFE0A33E),
        onClose: _exitAccurate,
      );
    }
    return const _Badge(label: 'Live', color: AppColors.accent);
  }

  /// A compact fingerprint of everything baked into the ffmpeg proxy, so a
  /// rebuild can tell whether an edit since the accurate render means the proxy
  /// is now stale (→ drop back to the live composite).
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
                tooltip: 'Accurate preview '
                    '(render the full proxy: colour, effects, transitions, audio)',
                onPressed:
                    hasClips && !_accurate ? _renderAccuratePreview : null,
              ),
            const SizedBox(width: 4),
            Icon(Icons.menu,
                size: 16, color: Colors.white.withValues(alpha: 0.6)),
          ],
        ),
      );

  Widget _controls(double total) {
    final maxMs = total * 1000;
    final valMs = (_timelineT * 1000).clamp(0.0, maxMs <= 0 ? 1 : maxMs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          Slider(
            value: maxMs > 0 ? valMs.toDouble() : 0,
            max: maxMs > 0 ? maxMs : 1,
            onChanged: (v) => _jumpTo(v / 1000),
          ),
          Row(
            children: [
              Text(_tc(Duration(milliseconds: (_timelineT * 1000).round())),
                  style: const TextStyle(
                      fontSize: 12, fontFeatures: [], color: Colors.white70)),
              Text('  /  ${_tc(Duration(milliseconds: (total * 1000).round()))}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4))),
              const Spacer(),
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlay,
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
  /// letterboxed to the project's canvas aspect.
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
                      onPressed: _togglePlay,
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
  /// [RatioDialog] on tap.
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
      probeOriginal: firstClipPath == null
          ? null
          : () => engine.probeDimensions(firstClipPath),
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

/// A small mode badge in the top-left of the monitor (Live / Accurate preview),
/// so it's always clear which preview the viewer is looking at (spec §7).
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.onClose});
  final String label;
  final Color color;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 3, onClose == null ? 8 : 4, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 13, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
