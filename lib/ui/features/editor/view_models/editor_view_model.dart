import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/caption.dart';
import '../../../../domain/models/clip.dart';
import '../../../../domain/models/keyframe.dart';
import '../../../../domain/models/media_type.dart';

part 'editor_view_model.g.dart';

/// The whole edit: the ordered list of clips plus which one is selected.
class EditorState {
  const EditorState({this.clips = const [], this.selectedId});

  final List<Clip> clips;
  final String? selectedId;

  Clip? get selected {
    if (selectedId == null) return null;
    for (final c in clips) {
      if (c.id == selectedId) return c;
    }
    return null;
  }

  int get selectedIndex =>
      selectedId == null ? -1 : clips.indexWhere((c) => c.id == selectedId);

  double get totalDuration =>
      clips.fold<double>(0, (sum, c) => sum + c.duration);

  EditorState copyWith({List<Clip>? clips, String? selectedId}) => EditorState(
        clips: clips ?? this.clips,
        selectedId: selectedId ?? this.selectedId,
      );
}

@Riverpod(keepAlive: true)
class Editor extends _$Editor {
  /// How many snapshots [_undoStack] (and, defensively, [_redoStack]) may
  /// hold before the oldest entry is dropped.
  static const int _historyLimit = 100;

  /// States to restore on [undo], most-recent last.
  final List<EditorState> _undoStack = [];

  /// States to restore on [redo], most-recent last. Cleared by any new
  /// mutation — once you branch off into a new edit, the old "future" is
  /// gone, same as every other undo/redo implementation.
  final List<EditorState> _redoStack = [];

  @override
  EditorState build() => const EditorState();

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Deep-clones [s] for storage on the undo/redo stacks.
  ///
  /// [EditorState.clips] is a fresh `List` on every mutation, but [Clip]
  /// itself has non-`final` fields (trim points, transform) — nothing in
  /// this file mutates them in place today (everything goes through
  /// [Clip.copyWith]), but a snapshot shouldn't silently depend on that
  /// staying true forever. Cloning each [Clip] (and its caption list, same
  /// reasoning) means the stacks own independent copies that a later
  /// mutation — in-place or not — can never reach back and corrupt.
  EditorState _snapshot(EditorState s) => EditorState(
        clips: s.clips.map(_cloneClip).toList(growable: false),
        selectedId: s.selectedId,
      );

  Clip _cloneClip(Clip c) => c.copyWith(
        captions: List.of(c.captions),
        keyframes: c.keyframes
            .map((property, kfs) => MapEntry(property, List.of(kfs))),
      );

  /// Routes a state change through undo history: snapshots the current state
  /// onto the undo stack (capped at [_historyLimit]), clears the redo stack,
  /// then applies [f]. Every content-mutating method below goes through this
  /// single chokepoint instead of duplicating the push logic.
  void _mutate(EditorState Function(EditorState) f) {
    _undoStack.add(_snapshot(state));
    if (_undoStack.length > _historyLimit) _undoStack.removeAt(0);
    _redoStack.clear();
    state = f(state);
  }

  /// Reverts to the state before the last mutation. No-op if there is none.
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot(state));
    if (_redoStack.length > _historyLimit) _redoStack.removeAt(0);
    state = _undoStack.removeLast();
  }

  /// Re-applies the last state undone by [undo]. No-op if there is none.
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot(state));
    if (_undoStack.length > _historyLimit) _undoStack.removeAt(0);
    state = _redoStack.removeLast();
  }

  /// Replaces the timeline with a project's clips (used when opening a
  /// project). This resets undo/redo history rather than being undoable
  /// itself — "undo" after opening a different project shouldn't resurrect
  /// whatever was on the timeline before it.
  void loadClips(List<Clip> clips) {
    _undoStack.clear();
    _redoStack.clear();
    state = EditorState(
      clips: List.of(clips),
      selectedId: clips.isEmpty ? null : clips.first.id,
    );
  }

  /// Adds [path] as a new clip on the main track. Video files are probed for
  /// their real duration, same as always. Image files have no intrinsic
  /// duration, so they become a fixed-length still clip instead (see
  /// [kImageDefaultDuration]/[kImageSourceDurationCap]) without needing
  /// ffprobe at all. Audio files are not handled here — callers should route
  /// those to `AudioClips.addFromPath` instead (see `browser_panel.dart`'s
  /// import routing).
  Future<void> addClip(String path) async {
    final type = mediaTypeForPath(path);
    final Clip clip;
    if (type == MediaType.image) {
      clip = Clip(
        sourcePath: path,
        sourceDuration: kImageSourceDurationCap,
        outPoint: kImageDefaultDuration,
        mediaType: MediaType.image,
      );
    } else {
      final duration = await ref.read(engineProvider).probeDuration(path);
      clip = Clip(sourcePath: path, sourceDuration: duration, mediaType: type);
    }
    _mutate((s) => s.copyWith(
          clips: [...s.clips, clip],
          selectedId: clip.id,
        ));
  }

  // Selection is navigation, not content, so it isn't pushed onto the undo
  // stack — same treatment as the playhead. Undoing a selection the user
  // just made (rather than the edit they made before it) would be
  // surprising.
  void select(String id) => state = state.copyWith(selectedId: id);

  /// Moves the clip at [oldIndex] to [newIndex] on the single track.
  /// [newIndex] is the target position *after* the clip has been removed
  /// from [oldIndex] — e.g. moving the first of three clips to the end is
  /// `reorder(0, 2)`. Used by drag-to-reorder on the timeline.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.clips.length) return;
    _mutate((s) {
      final clips = [...s.clips];
      final clip = clips.removeAt(oldIndex);
      clips.insert(newIndex.clamp(0, clips.length), clip);
      return s.copyWith(clips: clips);
    });
  }

  /// Sets the trim in/out of the clip with [id] (source seconds), clamped to
  /// the source and to a minimum clip length of 0.1s. Used by the timeline's
  /// trim handles, which drag one edge at a time.
  void setTrim(String id, {double? inPoint, double? outPoint}) {
    final idx = state.clips.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _mutate((s) {
      final clips = [...s.clips];
      final c = clips[idx];
      var newIn = (inPoint ?? c.inPoint).clamp(0.0, c.sourceDuration);
      var newOut = (outPoint ?? c.outPoint).clamp(0.0, c.sourceDuration);
      const minLength = 0.1;
      if (newOut - newIn < minLength) {
        if (inPoint != null) {
          // Dragging the left handle: don't let it pass the right edge.
          newIn = (newOut - minLength).clamp(0.0, c.sourceDuration);
        } else {
          // Dragging the right handle: don't let it pass the left edge.
          newOut = (newIn + minLength).clamp(0.0, c.sourceDuration);
        }
      }
      clips[idx] = c.copyWith(inPoint: newIn, outPoint: newOut);
      return s.copyWith(clips: clips);
    });
  }

  void removeSelected() {
    final id = state.selectedId;
    if (id == null) return;
    _mutate((s) {
      final remaining = s.clips.where((c) => c.id != id).toList();
      return EditorState(
        clips: remaining,
        selectedId: remaining.isEmpty ? null : remaining.last.id,
      );
    });
  }

  /// Sets the trim in/out of the selected clip. Points are source seconds.
  void trimSelected({double? inPoint, double? outPoint}) {
    _mapSelected((c) {
      final newIn = (inPoint ?? c.inPoint).clamp(0.0, c.sourceDuration);
      final newOut = (outPoint ?? c.outPoint).clamp(0.0, c.sourceDuration);
      if (newOut - newIn < 0.05) return c; // keep at least a sliver
      return c.copyWith(inPoint: newIn, outPoint: newOut);
    });
  }

  /// The selected clip's start offset on the timeline, in (speed-adjusted)
  /// timeline seconds — the sum of every earlier clip's [Clip.duration].
  double _selectedClipStart() {
    final idx = state.selectedIndex;
    if (idx < 0) return 0;
    var acc = 0.0;
    for (var i = 0; i < idx; i++) {
      acc += state.clips[i].duration;
    }
    return acc;
  }

  /// The playhead's position *within* the selected clip, in timeline seconds
  /// (0..[Clip.duration]). The playhead ([playheadProvider]) is timeline time;
  /// this maps it to clip-local time for per-clip operations (keyframes,
  /// animation, split). Returns 0 when nothing is selected.
  double _playheadWithinSelected() {
    final c = state.selected;
    if (c == null) return 0;
    return (ref.read(playheadProvider) - _selectedClipStart())
        .clamp(0.0, c.duration);
  }

  /// Splits the selected clip at [timelineSeconds] (a position on the whole
  /// timeline) into two adjacent clips.
  void splitSelectedAt(double timelineSeconds) {
    final idx = state.selectedIndex;
    if (idx < 0) return;
    final c = state.clips[idx];
    // Map the timeline position into this clip's own source time. `within` is
    // in timeline seconds (0..duration); multiplying by speed converts it to
    // source seconds, since duration = (outPoint-inPoint)/speed.
    final within = timelineSeconds - _selectedClipStart();
    final sourceSeconds = c.inPoint + within * c.speed;
    if (sourceSeconds <= c.inPoint + 0.05 ||
        sourceSeconds >= c.outPoint - 0.05) {
      return; // split point outside the usable region
    }
    _mutate((s) {
      // Captions were timed against the old in/out window, so they no longer
      // line up once it is split in two — drop them rather than show stale
      // text. Regenerate per-half if needed.
      final left = c.copyWith(outPoint: sourceSeconds, captions: const []);
      final right = Clip(
        sourcePath: c.sourcePath,
        sourceDuration: c.sourceDuration,
        inPoint: sourceSeconds,
        outPoint: c.outPoint,
      );
      final clips = [...s.clips]
        ..removeAt(idx)
        ..insertAll(idx, [left, right]);
      return s.copyWith(clips: clips, selectedId: left.id);
    });
  }

  /// Sets the playback speed of the selected clip, clamped to a sane range
  /// (0.1x–100x). The timeline length of the clip ([Clip.duration]) updates
  /// automatically since it is derived from the trim and the speed.
  void setSelectedSpeed(double speed) {
    _mapSelected((c) => c.copyWith(speed: speed.clamp(0.1, 100.0)));
  }

  /// Updates volume (0.0–2.0, i.e. 0–200%) and/or fade in/out (seconds) of
  /// the selected clip. Any omitted parameter is left unchanged. Volume is
  /// clamped to 0–2; fades are clamped to non-negative.
  void updateSelectedAudio({double? volume, double? fadeIn, double? fadeOut}) {
    _mapSelected((c) => c.copyWith(
          volume: volume?.clamp(0.0, 2.0),
          fadeIn: fadeIn?.clamp(0.0, double.infinity),
          fadeOut: fadeOut?.clamp(0.0, double.infinity),
        ));
  }

  /// Replaces all captions on the selected clip (e.g. after transcription).
  void setSelectedCaptions(List<Caption> captions) {
    _mapSelected((c) => c.copyWith(captions: captions));
  }

  /// Edits a single caption segment on the selected clip by index.
  void updateSelectedCaption(int index, Caption caption) {
    _mapSelected((c) {
      if (index < 0 || index >= c.captions.length) return c;
      final captions = [...c.captions];
      captions[index] = caption;
      return c.copyWith(captions: captions);
    });
  }

  /// Removes a single caption segment from the selected clip by index.
  void deleteSelectedCaption(int index) {
    _mapSelected((c) {
      if (index < 0 || index >= c.captions.length) return c;
      final captions = [...c.captions]..removeAt(index);
      return c.copyWith(captions: captions);
    });
  }

  /// Updates the transform (scale / position / rotation / opacity / flip) of
  /// the selected clip. Only the provided fields change; the rest are kept.
  ///
  /// If a given property already has keyframes, the new value is instead
  /// inserted/updated as a keyframe at the current playhead (clip-relative —
  /// see [addKeyframe]) rather than overwriting the static field, so an
  /// animated property stays driven entirely by its keyframes. A property
  /// with no keyframes behaves exactly as before this feature existed.
  void updateTransform({
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    double? opacity,
    bool? flipH,
  }) {
    _mapSelected((c) {
      final clipT = _playheadWithinSelected();
      var keyframes = c.keyframes;

      // Writes [value] into [property]'s keyframe list at the current
      // playhead and returns null (meaning "handled, leave the static field
      // alone") if that property already has keyframes; otherwise returns
      // [value] unchanged for the caller to apply to the static field.
      double? apply(String property, double? value) {
        if (value == null) return null;
        final existing = c.keyframes[property];
        if (existing == null || existing.isEmpty) return value;
        final list = List<Keyframe>.of(existing);
        final idx =
            list.indexWhere((k) => (k.timeSec - clipT).abs() < 0.001);
        final kf = Keyframe(timeSec: clipT, value: value);
        if (idx >= 0) {
          list[idx] = kf;
        } else {
          list.add(kf);
        }
        list.sort((a, b) => a.timeSec.compareTo(b.timeSec));
        keyframes = Map<String, List<Keyframe>>.of(keyframes)
          ..[property] = list;
        return null;
      }

      // Guard against a zero/negative scale, which would collapse the
      // ffmpeg filter chain to a zero-size frame.
      final newScale =
          apply(kKeyframeScale, scale?.clamp(0.05, 8.0).toDouble());
      final newPosX =
          apply(kKeyframePosX, posX?.clamp(-2.0, 2.0).toDouble());
      final newPosY =
          apply(kKeyframePosY, posY?.clamp(-2.0, 2.0).toDouble());
      final newRotation = apply(kKeyframeRotation, rotation);
      final newOpacity =
          apply(kKeyframeOpacity, opacity?.clamp(0.0, 1.0).toDouble());

      return c.copyWith(
        scale: newScale,
        posX: newPosX,
        posY: newPosY,
        rotation: newRotation,
        opacity: newOpacity,
        flipH: flipH,
        keyframes: keyframes,
      );
    });
  }

  /// Resets the selected clip's transform back to identity.
  void resetTransform() {
    _mapSelected((c) => c.copyWith(
          scale: 1.0,
          posX: 0.0,
          posY: 0.0,
          rotation: 0.0,
          flipH: false,
        ));
  }

  // ── keyframes ──
  // Per-property animation of the transform fields (see
  // lib/domain/models/keyframe.dart and docs/CAPCUT-SPEC.md §2.6). [property]
  // is one of the `kKeyframe*` constants in clip.dart; [timeSec] is
  // clip-relative (0 = start of the trimmed region) — the inspector's diamond
  // buttons are responsible for converting the playhead into that clip-local
  // time before calling these.

  /// Adds a keyframe for [property] at clip-relative [timeSec] with [value].
  /// If a keyframe already sits within ~1ms of [timeSec] it is replaced
  /// in place rather than duplicated (re-recording at the same instant just
  /// updates the value). The list is kept sorted by time.
  void addKeyframe(String property, double timeSec, double value) {
    _mapSelected((c) => c.copyWith(
        keyframes: _putKeyframe(c.keyframes, property, timeSec, value)));
  }

  /// Removes the keyframe within ~1ms of clip-relative [timeSec] from
  /// [property]'s list, if any. Removing the last keyframe for a property
  /// drops the map entry entirely, reverting it to static (using its current
  /// field value) — same as [clearKeyframes].
  void removeKeyframe(String property, double timeSec) {
    _mapSelected((c) =>
        c.copyWith(keyframes: _dropKeyframe(c.keyframes, property, timeSec)));
  }

  /// Removes every keyframe for [property] on the selected clip, reverting
  /// it to its static field value (the diamond's "clear" affordance).
  void clearKeyframes(String property) {
    _mapSelected((c) {
      if (!c.keyframes.containsKey(property)) return c;
      final keyframes = Map<String, List<Keyframe>>.of(c.keyframes)
        ..remove(property);
      return c.copyWith(keyframes: keyframes);
    });
  }

  /// The inspector diamond button's click handler: records [property]'s
  /// *current* value (interpolated if it's already animated, otherwise its
  /// static field) as a keyframe at the current playhead. No-op if there is
  /// no selected clip.
  void addKeyframeAtPlayhead(String property) {
    final c = state.selected;
    if (c == null) return;
    final t = _playheadWithinSelected();
    addKeyframe(property, t, c.valueAt(property, t));
  }

  // ── clip animation (In/Out/Combo) ──
  // The Animation tab's presets (docs/CAPCUT-SPEC.md §5.5) are implemented
  // entirely as generated keyframes on top of the engine above — no change
  // to FfmpegEngine was needed. [Clip.animationIn]/[Clip.animationOut] just
  // let the UI know which preset (if any) is active per edge.

  /// Applies (or, passing [kAnimNone], clears) [preset] on the selected
  /// clip's "in" edge (`isIn: true`, the first [duration] seconds) or "out"
  /// edge (`isIn: false`, the last [duration] seconds). [duration] is
  /// clamped to [kAnimationMinDuration]..[kAnimationMaxDuration].
  ///
  /// Writes two keyframes on whichever property the preset animates: one at
  /// the clip's outer edge (0 for "in", [Clip.duration] for "out") holding
  /// the animated extreme (e.g. opacity 0 for Fade), and one at the *inner*
  /// edge — [duration] seconds in from the outer edge — holding the
  /// property's current static value. That inner keyframe is what keeps the
  /// rest of the clip unaffected: since [keyframeValueAt] never extrapolates
  /// past the last keyframe, everything beyond it just stays at the static
  /// value, identical to before the animation was applied.
  ///
  /// Re-applying (a different preset, or the same preset with a new
  /// [duration]) first removes exactly the two keyframes the previous preset
  /// on *this* edge wrote, so it never disturbs the other edge or an
  /// unrelated property — see [_applyAnimationToClip].
  void applyAnimation({
    required bool isIn,
    required String preset,
    double duration = kAnimationDefaultDuration,
  }) {
    _mapSelected(
        (c) => _applyAnimationToClip(c, isIn: isIn, preset: preset, duration: duration));
  }

  /// Applies [preset] to *both* edges at once (the Animation tab's "Combo"
  /// sub-tab) as a single undo step.
  void applyComboAnimation({
    required String preset,
    double duration = kAnimationDefaultDuration,
  }) {
    _mapSelected((c) {
      final afterIn =
          _applyAnimationToClip(c, isIn: true, preset: preset, duration: duration);
      return _applyAnimationToClip(afterIn,
          isIn: false, preset: preset, duration: duration);
    });
  }

  // ── color / filter ──

  /// Updates manual brightness/contrast/saturation of the selected clip. Any
  /// omitted parameter is left unchanged. Brightness is clamped to -1..1;
  /// contrast and saturation to 0..3 (ffmpeg's `eq` filter range).
  void updateSelectedColor({
    double? brightness,
    double? contrast,
    double? saturation,
  }) {
    _mapSelected((c) => c.copyWith(
          brightness: brightness?.clamp(-1.0, 1.0).toDouble(),
          contrast: contrast?.clamp(0.0, 3.0).toDouble(),
          saturation: saturation?.clamp(0.0, 3.0).toDouble(),
        ));
  }

  /// Resets the selected clip's manual colour adjustments back to neutral.
  /// Leaves any applied filter preset ([Clip.filterId]) untouched.
  void resetColor() {
    _mapSelected((c) => c.copyWith(
          brightness: 0.0,
          contrast: 1.0,
          saturation: 1.0,
        ));
  }

  /// Sets (or, passing null, clears) the applied filter preset on the
  /// selected clip. [filterId] should be a key of [kColorFilterPresets] or
  /// null.
  void setSelectedFilter(String? filterId) {
    _mapSelected((c) => c.copyWith(filterId: filterId, clearFilterId: filterId == null));
  }

  /// Sets the selected clip's filter strength ([Clip.filterIntensity]),
  /// clamped to 0..1. Meaningful only while [Clip.filterId] is set, but
  /// harmless (and simply ignored on export) otherwise.
  void setSelectedFilterIntensity(double intensity) {
    _mapSelected((c) =>
        c.copyWith(filterIntensity: intensity.clamp(0.0, 1.0).toDouble()));
  }

  // ── effects ──

  /// Sets (or, passing null, clears) the applied video effect on the
  /// selected clip. [effectId] should be a key of [kEffectPresets] (see
  /// `lib/domain/models/effect_presets.dart`) or null.
  void setSelectedEffect(String? effectId) {
    _mapSelected((c) =>
        c.copyWith(effectId: effectId, clearEffectId: effectId == null));
  }

  /// Sets the selected clip's effect strength ([Clip.effectIntensity]),
  /// clamped to 0..1. Meaningful only while [Clip.effectId] is set, but
  /// harmless (and simply ignored on export) otherwise.
  void setSelectedEffectIntensity(double intensity) {
    _mapSelected((c) =>
        c.copyWith(effectIntensity: intensity.clamp(0.0, 1.0).toDouble()));
  }

  // ── transition ──

  /// Sets (or, passing null, clears) the transition that plays entering the
  /// selected clip from the previous one ([Clip.transitionId]), optionally
  /// updating its length ([Clip.transitionDuration], clamped to 0.05–5s).
  void setSelectedTransition(String? transitionId, {double? duration}) {
    _mapSelected((c) => c.copyWith(
          transitionId: transitionId,
          clearTransitionId: transitionId == null,
          transitionDuration: duration?.clamp(0.05, 5.0).toDouble(),
        ));
  }

  // ── AI upscale ──

  /// Applies the result of an AI upscale ([UpscaleService.upscale]'s output)
  /// to the selected clip: swaps its source to [upscaledPath] and resets the
  /// trim to cover the new file in full (the upscaled file *is* exactly the
  /// clip's previous trimmed region, re-encoded — see
  /// `lib/data/upscale/upscale_service.dart`), then records the pre-upscale
  /// source in [Clip.originalSourcePath] (unless one is already recorded,
  /// so re-upscaling an already-upscaled clip doesn't lose the true
  /// original) so [revertUpscale] can restore it later. Routed through
  /// [_mapSelected] like every other clip edit, so it is undoable.
  Future<void> applyUpscale(String upscaledPath) async {
    final duration =
        await ref.read(engineProvider).probeDuration(upscaledPath);
    _mapSelected((c) => c.copyWith(
          sourcePath: upscaledPath,
          sourceDuration: duration,
          inPoint: 0,
          outPoint: duration,
          originalSourcePath: c.originalSourcePath ?? c.sourcePath,
        ));
  }

  /// Reverts the selected clip back to its pre-upscale source
  /// ([Clip.originalSourcePath]), if it has one. The original file's trim
  /// can't be perfectly restored once overwritten (unless undo history still
  /// has it), so this resets to the original file in full rather than
  /// guessing — a safety net, not a substitute for undo. No-op if the
  /// selected clip was never upscaled.
  Future<void> revertUpscale() async {
    final original = state.selected?.originalSourcePath;
    if (original == null) return;
    final duration = await ref.read(engineProvider).probeDuration(original);
    _mapSelected((c) => c.copyWith(
          sourcePath: original,
          sourceDuration: duration,
          inPoint: 0,
          outPoint: duration,
          clearOriginalSourcePath: true,
        ));
  }

  void _mapSelected(Clip Function(Clip) f) {
    final idx = state.selectedIndex;
    if (idx < 0) return;
    _mutate((s) {
      final clips = [...s.clips];
      clips[idx] = f(clips[idx]);
      return s.copyWith(clips: clips);
    });
  }
}

// ── clip animation helpers ──
// Pure functions behind [Editor.applyAnimation]/[Editor.applyComboAnimation]
// — free functions (rather than instance methods) because they only ever
// operate on a plain [Clip] passed in by [Editor._mapSelected], never on
// [Editor]'s own state.

/// The transform property(ies) [preset] animates. Used both to write new
/// keyframes and to know which ones a *previous* preset on the same edge
/// should have cleared.
List<String> _animationProperties(String preset) => switch (preset) {
      kAnimFade => const [kKeyframeOpacity],
      kAnimZoomIn || kAnimZoomOut => const [kKeyframeScale],
      kAnimSlideLeft || kAnimSlideRight => const [kKeyframePosX],
      kAnimSlideUp || kAnimSlideDown => const [kKeyframePosY],
      _ => const [],
    };

/// Writes (or replaces, if one already sits within ~1ms of [timeSec]) a
/// keyframe for [property] at clip-relative [timeSec]. Same logic as
/// [Editor.addKeyframe], factored out so [_applyAnimationToClip] can use it
/// without going through [Editor]'s `_mapSelected`/undo plumbing itself —
/// the caller wraps the whole animation edit in a single mutation instead.
Map<String, List<Keyframe>> _putKeyframe(
  Map<String, List<Keyframe>> keyframes,
  String property,
  double timeSec,
  double value,
) {
  final list = List<Keyframe>.of(keyframes[property] ?? const []);
  final idx = list.indexWhere((k) => (k.timeSec - timeSec).abs() < 0.001);
  final kf = Keyframe(timeSec: timeSec, value: value);
  if (idx >= 0) {
    list[idx] = kf;
  } else {
    list.add(kf);
  }
  list.sort((a, b) => a.timeSec.compareTo(b.timeSec));
  return Map<String, List<Keyframe>>.of(keyframes)..[property] = list;
}

/// Removes the keyframe within ~1ms of clip-relative [timeSec] from
/// [property]'s list, if any — dropping the map entry entirely once its list
/// is empty. Same logic as [Editor.removeKeyframe]; see [_putKeyframe] for
/// why it's factored out as a free function.
Map<String, List<Keyframe>> _dropKeyframe(
  Map<String, List<Keyframe>> keyframes,
  String property,
  double timeSec,
) {
  final list = keyframes[property];
  if (list == null || list.isEmpty) return keyframes;
  final idx = list.indexWhere((k) => (k.timeSec - timeSec).abs() < 0.001);
  if (idx < 0) return keyframes;
  final updated = List<Keyframe>.of(list)..removeAt(idx);
  final result = Map<String, List<Keyframe>>.of(keyframes);
  if (updated.isEmpty) {
    result.remove(property);
  } else {
    result[property] = updated;
  }
  return result;
}

/// The actual work behind [Editor.applyAnimation] for a single edge
/// (`isIn: true` = the clip's start, `false` = its end), as a pure
/// [Clip] -> [Clip] step so [Editor.applyComboAnimation] can chain two calls
/// (in, then out) inside one `_mapSelected`/undo step.
///
/// Always starts by removing the two keyframes the *previous* preset on this
/// same edge wrote (computed from [Clip.animationIn]/[Clip.animationInDuration]
/// or their `...Out` counterparts) — so switching preset, changing duration,
/// or clearing (`preset == kAnimNone`) never leaves stale keyframes behind
/// and never touches the other edge or an unrelated property, even when both
/// edges animate the same property (e.g. Fade applied to both In and Out).
Clip _applyAnimationToClip(
  Clip c, {
  required bool isIn,
  required String preset,
  required double duration,
}) {
  final total = c.duration;
  var keyframes = c.keyframes;

  final prevPreset = isIn ? c.animationIn : c.animationOut;
  if (prevPreset != null) {
    final prevDuration =
        (isIn ? c.animationInDuration : c.animationOutDuration)
            .clamp(0.0, total)
            .toDouble();
    final prevOuter = isIn ? 0.0 : total;
    final prevInner = isIn ? prevDuration : total - prevDuration;
    for (final property in _animationProperties(prevPreset)) {
      keyframes = _dropKeyframe(keyframes, property, prevOuter);
      keyframes = _dropKeyframe(keyframes, property, prevInner);
    }
  }

  final clampedDuration =
      duration.clamp(kAnimationMinDuration, kAnimationMaxDuration).toDouble();

  if (preset == kAnimNone) {
    return c.copyWith(
      keyframes: keyframes,
      clearAnimationIn: isIn,
      clearAnimationOut: !isIn,
      animationInDuration: isIn ? clampedDuration : null,
      animationOutDuration: !isIn ? clampedDuration : null,
    );
  }

  // A clip too short to hold the full requested duration still gets an
  // animation — just squeezed to fit (clamped to the clip's own length)
  // rather than silently doing nothing.
  final dur = clampedDuration.clamp(0.0, total <= 0 ? 0.0 : total).toDouble();
  final outer = isIn ? 0.0 : total;
  final inner = isIn ? dur : total - dur;

  void write(String property, double outerValue, double innerValue) {
    keyframes = _putKeyframe(keyframes, property, outer, outerValue);
    keyframes = _putKeyframe(keyframes, property, inner, innerValue);
  }

  switch (preset) {
    case kAnimFade:
      write(kKeyframeOpacity, 0.0, c.opacity);
    case kAnimZoomIn:
      write(kKeyframeScale, (c.scale * 1.2).clamp(0.05, 8.0).toDouble(),
          c.scale);
    case kAnimZoomOut:
      write(kKeyframeScale, (c.scale * 0.8).clamp(0.05, 8.0).toDouble(),
          c.scale);
    case kAnimSlideLeft:
      write(
          kKeyframePosX,
          (c.posX + (isIn ? 1.0 : -1.0)).clamp(-2.0, 2.0).toDouble(),
          c.posX);
    case kAnimSlideRight:
      write(
          kKeyframePosX,
          (c.posX + (isIn ? -1.0 : 1.0)).clamp(-2.0, 2.0).toDouble(),
          c.posX);
    case kAnimSlideUp:
      write(
          kKeyframePosY,
          (c.posY + (isIn ? 1.0 : -1.0)).clamp(-2.0, 2.0).toDouble(),
          c.posY);
    case kAnimSlideDown:
      write(
          kKeyframePosY,
          (c.posY + (isIn ? -1.0 : 1.0)).clamp(-2.0, 2.0).toDouble(),
          c.posY);
  }

  return c.copyWith(
    keyframes: keyframes,
    animationIn: isIn ? preset : null,
    animationInDuration: isIn ? clampedDuration : null,
    animationOut: !isIn ? preset : null,
    animationOutDuration: !isIn ? clampedDuration : null,
  );
}

/// Export progress, 0..1, or null when not exporting.
@Riverpod(keepAlive: true)
class ExportProgress extends _$ExportProgress {
  @override
  double? build() => null;
  void set(double? value) => state = value;
}

/// Current playhead position of the preview, in source seconds. Written by the
/// preview panel, read by split/trim actions.
@Riverpod(keepAlive: true)
class Playhead extends _$Playhead {
  @override
  double build() => 0;
  void set(double seconds) => state = seconds;
}

/// Whether a WYSIWYG proxy render ([Engine.renderPreview]) is currently in
/// flight. Written by the player panel's "Render preview" button, read by its
/// header to show a busy indicator and disable the button mid-render.
@Riverpod(keepAlive: true)
class PreviewRendering extends _$PreviewRendering {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}
