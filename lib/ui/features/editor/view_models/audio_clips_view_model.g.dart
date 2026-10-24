// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_clips_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project's audio lane.
///
/// Audio clips are project-scoped (see [AudioClip]), not tied to any one
/// clip on the main track — like [Project.textOverlays]/[stickerOverlays],
/// they get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for
/// overlays.

@ProviderFor(AudioClips)
final audioClipsProvider = AudioClipsProvider._();

/// The project's audio lane.
///
/// Audio clips are project-scoped (see [AudioClip]), not tied to any one
/// clip on the main track — like [Project.textOverlays]/[stickerOverlays],
/// they get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for
/// overlays.
final class AudioClipsProvider
    extends $NotifierProvider<AudioClips, List<AudioClip>> {
  /// The project's audio lane.
  ///
  /// Audio clips are project-scoped (see [AudioClip]), not tied to any one
  /// clip on the main track — like [Project.textOverlays]/[stickerOverlays],
  /// they get their own notifier rather than living inside the per-clip editor
  /// state. `App` (the launcher view model) loads this from the manifest on
  /// open and copies it back on save, the same pattern it already uses for
  /// overlays.
  AudioClipsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioClipsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioClipsHash();

  @$internal
  @override
  AudioClips create() => AudioClips();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AudioClip> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AudioClip>>(value),
    );
  }
}

String _$audioClipsHash() => r'bfb851fbe6e064d5efd528adfad42319173671f6';

/// The project's audio lane.
///
/// Audio clips are project-scoped (see [AudioClip]), not tied to any one
/// clip on the main track — like [Project.textOverlays]/[stickerOverlays],
/// they get their own notifier rather than living inside the per-clip editor
/// state. `App` (the launcher view model) loads this from the manifest on
/// open and copies it back on save, the same pattern it already uses for
/// overlays.

abstract class _$AudioClips extends $Notifier<List<AudioClip>> {
  List<AudioClip> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<AudioClip>, List<AudioClip>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AudioClip>, List<AudioClip>>,
              List<AudioClip>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The audio lane's selected clip id, or null for none. Separate from the
/// list state above so selecting a clip doesn't itself count as an edit to
/// save/undo — same treatment as `Editor`'s own `selectedId`/`Playhead`.

@ProviderFor(SelectedAudioClip)
final selectedAudioClipProvider = SelectedAudioClipProvider._();

/// The audio lane's selected clip id, or null for none. Separate from the
/// list state above so selecting a clip doesn't itself count as an edit to
/// save/undo — same treatment as `Editor`'s own `selectedId`/`Playhead`.
final class SelectedAudioClipProvider
    extends $NotifierProvider<SelectedAudioClip, String?> {
  /// The audio lane's selected clip id, or null for none. Separate from the
  /// list state above so selecting a clip doesn't itself count as an edit to
  /// save/undo — same treatment as `Editor`'s own `selectedId`/`Playhead`.
  SelectedAudioClipProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedAudioClipProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedAudioClipHash();

  @$internal
  @override
  SelectedAudioClip create() => SelectedAudioClip();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedAudioClipHash() => r'084721b5ad9f10538da07cd0459197cabf523efc';

/// The audio lane's selected clip id, or null for none. Separate from the
/// list state above so selecting a clip doesn't itself count as an edit to
/// save/undo — same treatment as `Editor`'s own `selectedId`/`Playhead`.

abstract class _$SelectedAudioClip extends $Notifier<String?> {
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
