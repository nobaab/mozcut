// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Editor)
final editorProvider = EditorProvider._();

final class EditorProvider extends $NotifierProvider<Editor, EditorState> {
  EditorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'editorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$editorHash();

  @$internal
  @override
  Editor create() => Editor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorState>(value),
    );
  }
}

String _$editorHash() => r'fa0ca61c95c1509d17b87658a1d31e7b8a2684c6';

abstract class _$Editor extends $Notifier<EditorState> {
  EditorState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EditorState, EditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorState, EditorState>,
              EditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Export progress, 0..1, or null when not exporting.

@ProviderFor(ExportProgress)
final exportProgressProvider = ExportProgressProvider._();

/// Export progress, 0..1, or null when not exporting.
final class ExportProgressProvider
    extends $NotifierProvider<ExportProgress, double?> {
  /// Export progress, 0..1, or null when not exporting.
  ExportProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportProgressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportProgressHash();

  @$internal
  @override
  ExportProgress create() => ExportProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double?>(value),
    );
  }
}

String _$exportProgressHash() => r'59a58ee4ebdeb79b9ae631aced1ea54fa9cb1376';

/// Export progress, 0..1, or null when not exporting.

abstract class _$ExportProgress extends $Notifier<double?> {
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

/// Current playhead position of the preview, in source seconds. Written by the
/// preview panel, read by split/trim actions.

@ProviderFor(Playhead)
final playheadProvider = PlayheadProvider._();

/// Current playhead position of the preview, in source seconds. Written by the
/// preview panel, read by split/trim actions.
final class PlayheadProvider extends $NotifierProvider<Playhead, double> {
  /// Current playhead position of the preview, in source seconds. Written by the
  /// preview panel, read by split/trim actions.
  PlayheadProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playheadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playheadHash();

  @$internal
  @override
  Playhead create() => Playhead();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$playheadHash() => r'424b41f0b2eb0034da01df211086044556fba9af';

/// Current playhead position of the preview, in source seconds. Written by the
/// preview panel, read by split/trim actions.

abstract class _$Playhead extends $Notifier<double> {
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
