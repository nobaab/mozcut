import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/upscale/upscale_service.dart';
import '../../../../domain/models/clip.dart';
import 'editor_view_model.dart';

part 'upscale_view_model.g.dart';

/// Progress of an in-flight AI upscale run (see [UpscaleService.upscale]):
/// human-readable [status] text, 0..1 [progress], and whether one is running
/// at all. The inspector's AI Upscale section uses this to show a busy state
/// with a progress bar and Cancel button.
class UpscaleState {
  const UpscaleState({this.status, this.progress = 0, this.isRunning = false});

  final String? status;
  final double progress;
  final bool isRunning;

  UpscaleState copyWith({String? status, double? progress, bool? isRunning}) =>
      UpscaleState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        isRunning: isRunning ?? this.isRunning,
      );
}

@Riverpod(keepAlive: true)
class Upscale extends _$Upscale {
  /// The cancel handle for the currently running [run], if any — [cancel]
  /// stops whatever this points at. Cleared once [run] finishes (success,
  /// failure, or cancellation) so a stray late `cancel()` call is a no-op.
  UpscaleCancelToken? _cancelToken;

  @override
  UpscaleState build() => const UpscaleState();

  /// Upscales [clip] to roughly [targetWidth]x[targetHeight] and, on success,
  /// applies the result to the timeline via [Editor.applyUpscale]. Reports
  /// progress/status through [state] as it runs. A second call while one is
  /// already running is a no-op — use [cancel] to stop the current run
  /// first. Rethrows whatever [UpscaleService.upscale] throws (including on
  /// cancellation, as an [UpscaleException] with [upscaleCancelledMessage])
  /// after resetting back to idle, so the caller (the UI) can show it.
  Future<void> run(
    Clip clip, {
    required int targetWidth,
    required int targetHeight,
  }) async {
    if (state.isRunning) return;

    final service = ref.read(upscaleServiceProvider);
    final token = UpscaleCancelToken();
    _cancelToken = token;
    state = const UpscaleState(isRunning: true, status: 'Starting…');
    try {
      final outputPath = await service.cacheFilePath(
        clip,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final upscaledPath = await service.upscale(
        clip: clip,
        outputPath: outputPath,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        onStatus: (s) => state = state.copyWith(status: s),
        onProgress: (p) => state = state.copyWith(progress: p),
        cancel: token,
      );
      await ref.read(editorProvider.notifier).applyUpscale(upscaledPath);
    } finally {
      _cancelToken = null;
      state = const UpscaleState();
    }
  }

  /// Stops the run in progress, if any. The pending [run] call then throws
  /// an [UpscaleException] with [upscaleCancelledMessage].
  void cancel() => _cancelToken?.cancel();
}
