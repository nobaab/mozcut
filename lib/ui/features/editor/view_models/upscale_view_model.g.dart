// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upscale_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Upscale)
final upscaleProvider = UpscaleProvider._();

final class UpscaleProvider extends $NotifierProvider<Upscale, UpscaleState> {
  UpscaleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'upscaleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$upscaleHash();

  @$internal
  @override
  Upscale create() => Upscale();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpscaleState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpscaleState>(value),
    );
  }
}

String _$upscaleHash() => r'183cff5adae5e685295bec8a7dd547e5e2901ffa';

abstract class _$Upscale extends $Notifier<UpscaleState> {
  UpscaleState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UpscaleState, UpscaleState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UpscaleState, UpscaleState>,
              UpscaleState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
