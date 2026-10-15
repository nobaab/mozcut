// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'text_overlays_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project's text/title overlays.
///
/// Overlays are project-scoped (see [TextOverlay]), not tied to any one clip,
/// so — like [Project.clips] vs. `Editor` — they get their own notifier
/// rather than living inside the per-clip editor state. `App` (the launcher
/// view model) loads this from the manifest on open and copies it back on
/// save, the same pattern it already uses for clips.

@ProviderFor(TextOverlays)
final textOverlaysProvider = TextOverlaysProvider._();

/// The project's text/title overlays.
///
/// Overlays are project-scoped (see [TextOverlay]), not tied to any one clip,
/// so — like [Project.clips] vs. `Editor` — they get their own notifier
/// rather than living inside the per-clip editor state. `App` (the launcher
/// view model) loads this from the manifest on open and copies it back on
/// save, the same pattern it already uses for clips.
final class TextOverlaysProvider
    extends $NotifierProvider<TextOverlays, List<TextOverlay>> {
  /// The project's text/title overlays.
  ///
  /// Overlays are project-scoped (see [TextOverlay]), not tied to any one clip,
  /// so — like [Project.clips] vs. `Editor` — they get their own notifier
  /// rather than living inside the per-clip editor state. `App` (the launcher
  /// view model) loads this from the manifest on open and copies it back on
  /// save, the same pattern it already uses for clips.
  TextOverlaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'textOverlaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$textOverlaysHash();

  @$internal
  @override
  TextOverlays create() => TextOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<TextOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<TextOverlay>>(value),
    );
  }
}

String _$textOverlaysHash() => r'2cd726a59d054a96b85c1652ce34ed7899e7d958';

/// The project's text/title overlays.
///
/// Overlays are project-scoped (see [TextOverlay]), not tied to any one clip,
/// so — like [Project.clips] vs. `Editor` — they get their own notifier
/// rather than living inside the per-clip editor state. `App` (the launcher
/// view model) loads this from the manifest on open and copies it back on
/// save, the same pattern it already uses for clips.

abstract class _$TextOverlays extends $Notifier<List<TextOverlay>> {
  List<TextOverlay> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<TextOverlay>, List<TextOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<TextOverlay>, List<TextOverlay>>,
              List<TextOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
