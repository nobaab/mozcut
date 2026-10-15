import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/engine/ffmpeg_engine.dart';
import '../../../../domain/models/caption.dart';
import '../../../../domain/models/clip.dart';

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

  Clip _cloneClip(Clip c) => c.copyWith(captions: List.of(c.captions));

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

  Future<void> addClip(String path) async {
    final duration = await ref.read(engineProvider).probeDuration(path);
    final clip = Clip(sourcePath: path, sourceDuration: duration);
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

  /// Splits the selected clip at [sourceSeconds] into two adjacent clips.
  void splitSelectedAt(double sourceSeconds) {
    final idx = state.selectedIndex;
    if (idx < 0) return;
    final c = state.clips[idx];
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

  /// Updates the transform (scale / position / rotation / flip) of the
  /// selected clip. Only the provided fields change; the rest are kept.
  void updateTransform({
    double? scale,
    double? posX,
    double? posY,
    double? rotation,
    bool? flipH,
  }) {
    _mapSelected((c) => c.copyWith(
          // Guard against a zero/negative scale, which would collapse the
          // ffmpeg filter chain to a zero-size frame.
          scale: scale?.clamp(0.05, 8.0).toDouble(),
          posX: posX?.clamp(-2.0, 2.0).toDouble(),
          posY: posY?.clamp(-2.0, 2.0).toDouble(),
          rotation: rotation,
          flipH: flipH,
        ));
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
