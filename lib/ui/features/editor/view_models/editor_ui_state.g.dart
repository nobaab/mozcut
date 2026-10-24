// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editor_ui_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LeftTab)
final leftTabProvider = LeftTabProvider._();

final class LeftTabProvider extends $NotifierProvider<LeftTab, EditorLeftTab> {
  LeftTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leftTabProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leftTabHash();

  @$internal
  @override
  LeftTab create() => LeftTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorLeftTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorLeftTab>(value),
    );
  }
}

String _$leftTabHash() => r'f5b0ce79cd81f6b36d97e1685bae08c0aedd3538';

abstract class _$LeftTab extends $Notifier<EditorLeftTab> {
  EditorLeftTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EditorLeftTab, EditorLeftTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorLeftTab, EditorLeftTab>,
              EditorLeftTab,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(RightTab)
final rightTabProvider = RightTabProvider._();

final class RightTabProvider
    extends $NotifierProvider<RightTab, EditorRightTab> {
  RightTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rightTabProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rightTabHash();

  @$internal
  @override
  RightTab create() => RightTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorRightTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorRightTab>(value),
    );
  }
}

String _$rightTabHash() => r'6e488e3078f1705e5353819e10016a35faffa17b';

abstract class _$RightTab extends $Notifier<EditorRightTab> {
  EditorRightTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EditorRightTab, EditorRightTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorRightTab, EditorRightTab>,
              EditorRightTab,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(VideoSub)
final videoSubProvider = VideoSubProvider._();

final class VideoSubProvider extends $NotifierProvider<VideoSub, VideoSubTab> {
  VideoSubProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoSubProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoSubHash();

  @$internal
  @override
  VideoSub create() => VideoSub();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoSubTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoSubTab>(value),
    );
  }
}

String _$videoSubHash() => r'86da96a6899515c19d9a61edef1234c6c91ba7cc';

abstract class _$VideoSub extends $Notifier<VideoSubTab> {
  VideoSubTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VideoSubTab, VideoSubTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VideoSubTab, VideoSubTab>,
              VideoSubTab,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Timeline zoom, in pixels per second.

@ProviderFor(TimelineZoom)
final timelineZoomProvider = TimelineZoomProvider._();

/// Timeline zoom, in pixels per second.
final class TimelineZoomProvider
    extends $NotifierProvider<TimelineZoom, double> {
  /// Timeline zoom, in pixels per second.
  TimelineZoomProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timelineZoomProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timelineZoomHash();

  @$internal
  @override
  TimelineZoom create() => TimelineZoom();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$timelineZoomHash() => r'7ed72e33347835b602879b272d4dc8b595b49789';

/// Timeline zoom, in pixels per second.

abstract class _$TimelineZoom extends $Notifier<double> {
  double build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<double, double>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double, double>,
              double,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether dragging/trimming a clip magnetizes to nearby snap targets (`0`,
/// the playhead, other clips'/audio-clips'/overlays' edges — see
/// `lib/ui/features/editor/timeline_snap.dart`). Defaults on, matching both
/// CapCut-style reference editors (docs/TIMELINE-BEHAVIOR.md §7). Toggled by
/// the timeline toolbar's snap button and the `n` keyboard shortcut.

@ProviderFor(SnapEnabled)
final snapEnabledProvider = SnapEnabledProvider._();

/// Whether dragging/trimming a clip magnetizes to nearby snap targets (`0`,
/// the playhead, other clips'/audio-clips'/overlays' edges — see
/// `lib/ui/features/editor/timeline_snap.dart`). Defaults on, matching both
/// CapCut-style reference editors (docs/TIMELINE-BEHAVIOR.md §7). Toggled by
/// the timeline toolbar's snap button and the `n` keyboard shortcut.
final class SnapEnabledProvider extends $NotifierProvider<SnapEnabled, bool> {
  /// Whether dragging/trimming a clip magnetizes to nearby snap targets (`0`,
  /// the playhead, other clips'/audio-clips'/overlays' edges — see
  /// `lib/ui/features/editor/timeline_snap.dart`). Defaults on, matching both
  /// CapCut-style reference editors (docs/TIMELINE-BEHAVIOR.md §7). Toggled by
  /// the timeline toolbar's snap button and the `n` keyboard shortcut.
  SnapEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'snapEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$snapEnabledHash();

  @$internal
  @override
  SnapEnabled create() => SnapEnabled();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$snapEnabledHash() => r'2078b181360a503e9b0bb98f08f058abce26604a';

/// Whether dragging/trimming a clip magnetizes to nearby snap targets (`0`,
/// the playhead, other clips'/audio-clips'/overlays' edges — see
/// `lib/ui/features/editor/timeline_snap.dart`). Defaults on, matching both
/// CapCut-style reference editors (docs/TIMELINE-BEHAVIOR.md §7). Toggled by
/// the timeline toolbar's snap button and the `n` keyboard shortcut.

abstract class _$SnapEnabled extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The timeline position (timeline seconds) the active drag/trim is currently
/// snapped to, or null when nothing is snapped. Written by the per-clip
/// move/trim handlers in `timeline_panel.dart` while a gesture is in
/// progress; read only by the isolated snap-line widget there, the same
/// "watch just this, not the whole timeline" treatment `Playhead`/`_Playhead`
/// get — so the magnetic line can appear/disappear every drag frame without
/// rebuilding every clip bar, filmstrip and waveform.

@ProviderFor(SnapIndicator)
final snapIndicatorProvider = SnapIndicatorProvider._();

/// The timeline position (timeline seconds) the active drag/trim is currently
/// snapped to, or null when nothing is snapped. Written by the per-clip
/// move/trim handlers in `timeline_panel.dart` while a gesture is in
/// progress; read only by the isolated snap-line widget there, the same
/// "watch just this, not the whole timeline" treatment `Playhead`/`_Playhead`
/// get — so the magnetic line can appear/disappear every drag frame without
/// rebuilding every clip bar, filmstrip and waveform.
final class SnapIndicatorProvider
    extends $NotifierProvider<SnapIndicator, double?> {
  /// The timeline position (timeline seconds) the active drag/trim is currently
  /// snapped to, or null when nothing is snapped. Written by the per-clip
  /// move/trim handlers in `timeline_panel.dart` while a gesture is in
  /// progress; read only by the isolated snap-line widget there, the same
  /// "watch just this, not the whole timeline" treatment `Playhead`/`_Playhead`
  /// get — so the magnetic line can appear/disappear every drag frame without
  /// rebuilding every clip bar, filmstrip and waveform.
  SnapIndicatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'snapIndicatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$snapIndicatorHash();

  @$internal
  @override
  SnapIndicator create() => SnapIndicator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double?>(value),
    );
  }
}

String _$snapIndicatorHash() => r'3d3340574ad64a1f77ddbedd763ea3de5945599b';

/// The timeline position (timeline seconds) the active drag/trim is currently
/// snapped to, or null when nothing is snapped. Written by the per-clip
/// move/trim handlers in `timeline_panel.dart` while a gesture is in
/// progress; read only by the isolated snap-line widget there, the same
/// "watch just this, not the whole timeline" treatment `Playhead`/`_Playhead`
/// get — so the magnetic line can appear/disappear every drag frame without
/// rebuilding every clip bar, filmstrip and waveform.

abstract class _$SnapIndicator extends $Notifier<double?> {
  double? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<double?, double?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double?, double?>,
              double?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the preview is currently playing. Written by [PlayerPanel] from
/// its media_kit player's `playing` stream; read by the timeline to drive
/// auto-scroll-follow during playback (keeping the playhead on-screen — see
/// `_TimelinePanelState._followPlayhead` in `timeline_panel.dart`) without
/// the timeline needing any direct reference to the player.

@ProviderFor(IsPlaying)
final isPlayingProvider = IsPlayingProvider._();

/// Whether the preview is currently playing. Written by [PlayerPanel] from
/// its media_kit player's `playing` stream; read by the timeline to drive
/// auto-scroll-follow during playback (keeping the playhead on-screen — see
/// `_TimelinePanelState._followPlayhead` in `timeline_panel.dart`) without
/// the timeline needing any direct reference to the player.
final class IsPlayingProvider extends $NotifierProvider<IsPlaying, bool> {
  /// Whether the preview is currently playing. Written by [PlayerPanel] from
  /// its media_kit player's `playing` stream; read by the timeline to drive
  /// auto-scroll-follow during playback (keeping the playhead on-screen — see
  /// `_TimelinePanelState._followPlayhead` in `timeline_panel.dart`) without
  /// the timeline needing any direct reference to the player.
  IsPlayingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isPlayingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isPlayingHash();

  @$internal
  @override
  IsPlaying create() => IsPlaying();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isPlayingHash() => r'ef340fd9b89f3848471efabf65d9433901a51816';

/// Whether the preview is currently playing. Written by [PlayerPanel] from
/// its media_kit player's `playing` stream; read by the timeline to drive
/// auto-scroll-follow during playback (keeping the playhead on-screen — see
/// `_TimelinePanelState._followPlayhead` in `timeline_panel.dart`) without
/// the timeline needing any direct reference to the player.

abstract class _$IsPlaying extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Panels)
final panelsProvider = PanelsProvider._();

final class PanelsProvider extends $NotifierProvider<Panels, PanelSizes> {
  PanelsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'panelsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$panelsHash();

  @$internal
  @override
  Panels create() => Panels();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PanelSizes value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PanelSizes>(value),
    );
  }
}

String _$panelsHash() => r'd677edf28c2962b7e54f2e7daffb99ec304a293b';

abstract class _$Panels extends $Notifier<PanelSizes> {
  PanelSizes build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PanelSizes, PanelSizes>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PanelSizes, PanelSizes>,
              PanelSizes,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
