// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upscale_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Local, on-device AI video upscaling via
/// [Real-ESRGAN (ncnn-vulkan)](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan).
///
/// No network calls and no API keys — frames are extracted from the clip with
/// `ffmpeg`, upscaled frame-by-frame with the `realesrgan-ncnn-vulkan` binary
/// (processed in chunks so disk usage stays bounded on long clips), then
/// re-encoded and muxed back with the original audio. The binary and its
/// bundled model files are expected to already be installed (see
/// [UpscaleException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without Real-ESRGAN.

@ProviderFor(upscaleService)
final upscaleServiceProvider = UpscaleServiceProvider._();

/// Local, on-device AI video upscaling via
/// [Real-ESRGAN (ncnn-vulkan)](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan).
///
/// No network calls and no API keys — frames are extracted from the clip with
/// `ffmpeg`, upscaled frame-by-frame with the `realesrgan-ncnn-vulkan` binary
/// (processed in chunks so disk usage stays bounded on long clips), then
/// re-encoded and muxed back with the original audio. The binary and its
/// bundled model files are expected to already be installed (see
/// [UpscaleException] messages for exact install steps); everything else
/// about this class degrades gracefully when they are missing so the rest of
/// the app keeps working on a machine without Real-ESRGAN.

final class UpscaleServiceProvider
    extends $FunctionalProvider<UpscaleService, UpscaleService, UpscaleService>
    with $Provider<UpscaleService> {
  /// Local, on-device AI video upscaling via
  /// [Real-ESRGAN (ncnn-vulkan)](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan).
  ///
  /// No network calls and no API keys — frames are extracted from the clip with
  /// `ffmpeg`, upscaled frame-by-frame with the `realesrgan-ncnn-vulkan` binary
  /// (processed in chunks so disk usage stays bounded on long clips), then
  /// re-encoded and muxed back with the original audio. The binary and its
  /// bundled model files are expected to already be installed (see
  /// [UpscaleException] messages for exact install steps); everything else
  /// about this class degrades gracefully when they are missing so the rest of
  /// the app keeps working on a machine without Real-ESRGAN.
  UpscaleServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'upscaleServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$upscaleServiceHash();

  @$internal
  @override
  $ProviderElement<UpscaleService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UpscaleService create(Ref ref) {
    return upscaleService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpscaleService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpscaleService>(value),
    );
  }
}

String _$upscaleServiceHash() => r'3679e839d13cd03703728daae65c5758ff573893';
