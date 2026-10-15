// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'whisper_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Local, on-device speech-to-text via [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
///
/// No network calls and no API keys — audio is extracted from the clip with
/// `ffmpeg`, then handed to a whisper.cpp binary on disk. The binary and a
/// ggml model file are expected to already be installed (see
/// [WhisperException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without whisper.cpp.

@ProviderFor(whisperService)
final whisperServiceProvider = WhisperServiceProvider._();

/// Local, on-device speech-to-text via [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
///
/// No network calls and no API keys — audio is extracted from the clip with
/// `ffmpeg`, then handed to a whisper.cpp binary on disk. The binary and a
/// ggml model file are expected to already be installed (see
/// [WhisperException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without whisper.cpp.

final class WhisperServiceProvider
    extends $FunctionalProvider<WhisperService, WhisperService, WhisperService>
    with $Provider<WhisperService> {
  /// Local, on-device speech-to-text via [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
  ///
  /// No network calls and no API keys — audio is extracted from the clip with
  /// `ffmpeg`, then handed to a whisper.cpp binary on disk. The binary and a
  /// ggml model file are expected to already be installed (see
  /// [WhisperException] messages for exact install steps); everything else
  /// about this class degrades gracefully when they are missing so the rest of
  /// the app keeps working on a machine without whisper.cpp.
  WhisperServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'whisperServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$whisperServiceHash();

  @$internal
  @override
  $ProviderElement<WhisperService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WhisperService create(Ref ref) {
    return whisperService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WhisperService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WhisperService>(value),
    );
  }
}

String _$whisperServiceHash() => r'1266930a74c7d76fe63ca3a935a92d3db6e1d2de';
