// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'launcher_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Orchestrates the app's two screens. `state` is the open project, or null for
/// the launcher. Create / open / close all live here because each touches the
/// store, the editor's clips and the recents list together.

@ProviderFor(App)
final appProvider = AppProvider._();

/// Orchestrates the app's two screens. `state` is the open project, or null for
/// the launcher. Create / open / close all live here because each touches the
/// store, the editor's clips and the recents list together.
final class AppProvider extends $NotifierProvider<App, Project?> {
  /// Orchestrates the app's two screens. `state` is the open project, or null for
  /// the launcher. Create / open / close all live here because each touches the
  /// store, the editor's clips and the recents list together.
  AppProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appHash();

  @$internal
  @override
  App create() => App();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Project? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Project?>(value),
    );
  }
}

String _$appHash() => r'e721f0de7065cae7086a022db7b7f641adc65f9b';

/// Orchestrates the app's two screens. `state` is the open project, or null for
/// the launcher. Create / open / close all live here because each touches the
/// store, the editor's clips and the recents list together.

abstract class _$App extends $Notifier<Project?> {
  Project? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Project?, Project?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Project?, Project?>,
              Project?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
