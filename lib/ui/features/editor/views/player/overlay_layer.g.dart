// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'overlay_layer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A cache of still poster frames (keyed by source path) for picture-in-picture
/// overlays — the "poster-frame tier (a)" from spec §4: rather than spin up a
/// second live decoder per PiP, the preview shows one cached still frame of the
/// overlay, which is cheap and good enough for placement. The accurate preview
/// proxy (§6) still renders the real moving PiP.

@ProviderFor(PipPosters)
final pipPostersProvider = PipPostersProvider._();

/// A cache of still poster frames (keyed by source path) for picture-in-picture
/// overlays — the "poster-frame tier (a)" from spec §4: rather than spin up a
/// second live decoder per PiP, the preview shows one cached still frame of the
/// overlay, which is cheap and good enough for placement. The accurate preview
/// proxy (§6) still renders the real moving PiP.
final class PipPostersProvider
    extends $NotifierProvider<PipPosters, Map<String, String>> {
  /// A cache of still poster frames (keyed by source path) for picture-in-picture
  /// overlays — the "poster-frame tier (a)" from spec §4: rather than spin up a
  /// second live decoder per PiP, the preview shows one cached still frame of the
  /// overlay, which is cheap and good enough for placement. The accurate preview
  /// proxy (§6) still renders the real moving PiP.
  PipPostersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pipPostersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pipPostersHash();

  @$internal
  @override
  PipPosters create() => PipPosters();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$pipPostersHash() => r'e35236ea404a918281b4939cec62a0815c3cd2fd';

/// A cache of still poster frames (keyed by source path) for picture-in-picture
/// overlays — the "poster-frame tier (a)" from spec §4: rather than spin up a
/// second live decoder per PiP, the preview shows one cached still frame of the
/// overlay, which is cheap and good enough for placement. The accurate preview
/// proxy (§6) still renders the real moving PiP.

abstract class _$PipPosters extends $Notifier<Map<String, String>> {
  Map<String, String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<String, String>, Map<String, String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, String>, Map<String, String>>,
              Map<String, String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
