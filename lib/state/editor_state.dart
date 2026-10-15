import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/engine/engine.dart';
import '../core/engine/ffmpeg_engine.dart';
import '../core/models/clip.dart';

/// The single engine instance for the app. Swap the implementation here (e.g.
/// to a Rust-backed engine) and nothing else changes.
final engineProvider = Provider<Engine>((ref) => FfmpegEngine());

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

class EditorController extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  /// Replaces the timeline with a project's clips (used when opening a project).
  void loadClips(List<Clip> clips) {
    state = EditorState(
      clips: List.of(clips),
      selectedId: clips.isEmpty ? null : clips.first.id,
    );
  }

  Future<void> addClip(String path) async {
    final engine = ref.read(engineProvider);
    final duration = await engine.probeDuration(path);
    final clip = Clip(sourcePath: path, sourceDuration: duration);
    state = state.copyWith(
      clips: [...state.clips, clip],
      selectedId: clip.id,
    );
  }

  void select(String id) => state = state.copyWith(selectedId: id);

  void removeSelected() {
    final id = state.selectedId;
    if (id == null) return;
    final remaining = state.clips.where((c) => c.id != id).toList();
    state = EditorState(
      clips: remaining,
      selectedId: remaining.isEmpty ? null : remaining.last.id,
    );
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
    final left = c.copyWith(outPoint: sourceSeconds);
    final right = Clip(
      sourcePath: c.sourcePath,
      sourceDuration: c.sourceDuration,
      inPoint: sourceSeconds,
      outPoint: c.outPoint,
    );
    final clips = [...state.clips]
      ..removeAt(idx)
      ..insertAll(idx, [left, right]);
    state = state.copyWith(clips: clips, selectedId: left.id);
  }

  void _mapSelected(Clip Function(Clip) f) {
    final idx = state.selectedIndex;
    if (idx < 0) return;
    final clips = [...state.clips];
    clips[idx] = f(clips[idx]);
    state = state.copyWith(clips: clips);
  }
}

final editorProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);

/// Export progress, 0..1, or null when not exporting.
final exportProgressProvider = StateProvider<double?>((ref) => null);

/// Current playhead position of the preview, in source seconds. Written by the
/// preview panel, read by split/trim actions.
final playheadProvider = StateProvider<double>((ref) => 0);
