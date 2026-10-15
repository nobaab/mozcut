// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(projectStore)
final projectStoreProvider = ProjectStoreProvider._();

final class ProjectStoreProvider
    extends $FunctionalProvider<ProjectStore, ProjectStore, ProjectStore>
    with $Provider<ProjectStore> {
  ProjectStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectStoreHash();

  @$internal
  @override
  $ProviderElement<ProjectStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectStore create(Ref ref) {
    return projectStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectStore>(value),
    );
  }
}

String _$projectStoreHash() => r'414cd4fb045c4d4ef4db824ad2941440124d3c92';

/// The machine's recent projects, newest first. Invalidate to refresh.

@ProviderFor(recents)
final recentsProvider = RecentsProvider._();

/// The machine's recent projects, newest first. Invalidate to refresh.

final class RecentsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecentProject>>,
          List<RecentProject>,
          FutureOr<List<RecentProject>>
        >
    with
        $FutureModifier<List<RecentProject>>,
        $FutureProvider<List<RecentProject>> {
  /// The machine's recent projects, newest first. Invalidate to refresh.
  RecentsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentsHash();

  @$internal
  @override
  $FutureProviderElement<List<RecentProject>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RecentProject>> create(Ref ref) {
    return recents(ref);
  }
}

String _$recentsHash() => r'a425ab381632f271dc4c91b22ca523482cdb5afb';
