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
