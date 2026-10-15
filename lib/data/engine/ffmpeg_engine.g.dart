// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ffmpeg_engine.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's single engine. Swap the implementation here (e.g. to a Rust-backed
/// engine) and nothing else changes.

@ProviderFor(engine)
final engineProvider = EngineProvider._();

/// The app's single engine. Swap the implementation here (e.g. to a Rust-backed
/// engine) and nothing else changes.

final class EngineProvider extends $FunctionalProvider<Engine, Engine, Engine>
    with $Provider<Engine> {
  /// The app's single engine. Swap the implementation here (e.g. to a Rust-backed
  /// engine) and nothing else changes.
  EngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'engineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$engineHash();

  @$internal
  @override
  $ProviderElement<Engine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Engine create(Ref ref) {
    return engine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Engine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Engine>(value),
    );
  }
}

String _$engineHash() => r'462e72be02111e39bed35ef6107f516445bd9673';
