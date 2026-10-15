// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'captions_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Status text of an in-flight caption-generation run (e.g. "Extracting
/// audio…", "Transcribing…"), or null when idle. The captions panel uses this
/// to show a busy state while [WhisperService.transcribe] runs.

@ProviderFor(CaptionGeneration)
final captionGenerationProvider = CaptionGenerationProvider._();

/// Status text of an in-flight caption-generation run (e.g. "Extracting
/// audio…", "Transcribing…"), or null when idle. The captions panel uses this
/// to show a busy state while [WhisperService.transcribe] runs.
final class CaptionGenerationProvider
    extends $NotifierProvider<CaptionGeneration, String?> {
  /// Status text of an in-flight caption-generation run (e.g. "Extracting
  /// audio…", "Transcribing…"), or null when idle. The captions panel uses this
  /// to show a busy state while [WhisperService.transcribe] runs.
  CaptionGenerationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'captionGenerationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$captionGenerationHash();

  @$internal
  @override
  CaptionGeneration create() => CaptionGeneration();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$captionGenerationHash() => r'c2bf11e15c907a874b93cf1c0a3dd1ce904ec397';

/// Status text of an in-flight caption-generation run (e.g. "Extracting
/// audio…", "Transcribing…"), or null when idle. The captions panel uses this
/// to show a busy state while [WhisperService.transcribe] runs.

abstract class _$CaptionGeneration extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
