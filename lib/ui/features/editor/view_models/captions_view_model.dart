import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'captions_view_model.g.dart';

/// Status text of an in-flight caption-generation run (e.g. "Extracting
/// audio…", "Transcribing…"), or null when idle. The captions panel uses this
/// to show a busy state while [WhisperService.transcribe] runs.
@Riverpod(keepAlive: true)
class CaptionGeneration extends _$CaptionGeneration {
  @override
  String? build() => null;

  void set(String? status) => state = status;
}
