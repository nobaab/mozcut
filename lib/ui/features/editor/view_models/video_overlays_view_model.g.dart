// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_overlays_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project's picture-in-picture lane.
///
/// Mirrors [AudioClips]/[StickerOverlays] — video overlays are project-scoped
/// (see [VideoOverlay]), not tied to any one clip on the main track, so they
/// get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for the
/// other overlays.

@ProviderFor(VideoOverlays)
final videoOverlaysProvider = VideoOverlaysProvider._();

/// The project's picture-in-picture lane.
///
/// Mirrors [AudioClips]/[StickerOverlays] — video overlays are project-scoped
/// (see [VideoOverlay]), not tied to any one clip on the main track, so they
/// get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for the
/// other overlays.
final class VideoOverlaysProvider
    extends $NotifierProvider<VideoOverlays, List<VideoOverlay>> {
  /// The project's picture-in-picture lane.
  ///
  /// Mirrors [AudioClips]/[StickerOverlays] — video overlays are project-scoped
  /// (see [VideoOverlay]), not tied to any one clip on the main track, so they
  /// get their own notifier rather than living inside the per-clip editor
  /// state. `App` (the launcher view model) loads this from the manifest on
  /// open and copies it back on save, the same pattern it already uses for the
  /// other overlays.
  VideoOverlaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoOverlaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoOverlaysHash();

  @$internal
  @override
  VideoOverlays create() => VideoOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<VideoOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<VideoOverlay>>(value),
    );
  }
}

String _$videoOverlaysHash() => r'79185e24b3afee80ab062515bdfa396116a96599';

/// The project's picture-in-picture lane.
///
/// Mirrors [AudioClips]/[StickerOverlays] — video overlays are project-scoped
/// (see [VideoOverlay]), not tied to any one clip on the main track, so they
/// get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for the
/// other overlays.

abstract class _$VideoOverlays extends $Notifier<List<VideoOverlay>> {
  List<VideoOverlay> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<VideoOverlay>, List<VideoOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<VideoOverlay>, List<VideoOverlay>>,
              List<VideoOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The overlay lane's selected overlay id, or null for none. Separate from
/// the list state above, same treatment as [SelectedAudioClip].

@ProviderFor(SelectedVideoOverlay)
final selectedVideoOverlayProvider = SelectedVideoOverlayProvider._();

/// The overlay lane's selected overlay id, or null for none. Separate from
/// the list state above, same treatment as [SelectedAudioClip].
final class SelectedVideoOverlayProvider
    extends $NotifierProvider<SelectedVideoOverlay, String?> {
  /// The overlay lane's selected overlay id, or null for none. Separate from
  /// the list state above, same treatment as [SelectedAudioClip].
  SelectedVideoOverlayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedVideoOverlayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedVideoOverlayHash();

  @$internal
  @override
  SelectedVideoOverlay create() => SelectedVideoOverlay();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedVideoOverlayHash() =>
    r'1c62d09d4d2ec30c380cae8a713e9df96c566f1d';

/// The overlay lane's selected overlay id, or null for none. Separate from
/// the list state above, same treatment as [SelectedAudioClip].

abstract class _$SelectedVideoOverlay extends $Notifier<String?> {
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
