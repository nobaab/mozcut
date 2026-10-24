// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sticker_overlays_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project's emoji sticker overlays.
///
/// Mirrors [TextOverlays] exactly — stickers are project-scoped (see
/// [StickerOverlay]), not tied to any one clip, so they get their own
/// notifier rather than living inside the per-clip editor state. `App` (the
/// launcher view model) loads this from the manifest on open and copies it
/// back on save, the same pattern it already uses for text overlays.

@ProviderFor(StickerOverlays)
final stickerOverlaysProvider = StickerOverlaysProvider._();

/// The project's emoji sticker overlays.
///
/// Mirrors [TextOverlays] exactly — stickers are project-scoped (see
/// [StickerOverlay]), not tied to any one clip, so they get their own
/// notifier rather than living inside the per-clip editor state. `App` (the
/// launcher view model) loads this from the manifest on open and copies it
/// back on save, the same pattern it already uses for text overlays.
final class StickerOverlaysProvider
    extends $NotifierProvider<StickerOverlays, List<StickerOverlay>> {
  /// The project's emoji sticker overlays.
  ///
  /// Mirrors [TextOverlays] exactly — stickers are project-scoped (see
  /// [StickerOverlay]), not tied to any one clip, so they get their own
  /// notifier rather than living inside the per-clip editor state. `App` (the
  /// launcher view model) loads this from the manifest on open and copies it
  /// back on save, the same pattern it already uses for text overlays.
  StickerOverlaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stickerOverlaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stickerOverlaysHash();

  @$internal
  @override
  StickerOverlays create() => StickerOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<StickerOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<StickerOverlay>>(value),
    );
  }
}

String _$stickerOverlaysHash() => r'fbd5c82f8adae84dc1739d8332316ec1c7351fe9';

/// The project's emoji sticker overlays.
///
/// Mirrors [TextOverlays] exactly — stickers are project-scoped (see
/// [StickerOverlay]), not tied to any one clip, so they get their own
/// notifier rather than living inside the per-clip editor state. `App` (the
/// launcher view model) loads this from the manifest on open and copies it
/// back on save, the same pattern it already uses for text overlays.

abstract class _$StickerOverlays extends $Notifier<List<StickerOverlay>> {
  List<StickerOverlay> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<StickerOverlay>, List<StickerOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<StickerOverlay>, List<StickerOverlay>>,
              List<StickerOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
