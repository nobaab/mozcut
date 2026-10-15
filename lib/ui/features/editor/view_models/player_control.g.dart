// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_control.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Command bus for the preview player. Keyboard shortcuts call
/// [togglePlayPause]/[seekBy]; [PlayerPanel] listens and performs the actual
/// play/pause/seek against its media_kit [Player].

@ProviderFor(PlayerControl)
final playerControlProvider = PlayerControlProvider._();

/// Command bus for the preview player. Keyboard shortcuts call
/// [togglePlayPause]/[seekBy]; [PlayerPanel] listens and performs the actual
/// play/pause/seek against its media_kit [Player].
final class PlayerControlProvider
    extends $NotifierProvider<PlayerControl, PlayerCommand?> {
  /// Command bus for the preview player. Keyboard shortcuts call
  /// [togglePlayPause]/[seekBy]; [PlayerPanel] listens and performs the actual
  /// play/pause/seek against its media_kit [Player].
  PlayerControlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerControlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerControlHash();

  @$internal
  @override
  PlayerControl create() => PlayerControl();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayerCommand? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayerCommand?>(value),
    );
  }
}

String _$playerControlHash() => r'41661cf37ab8deed2ed4ecf7e11c682cc28dab9b';

/// Command bus for the preview player. Keyboard shortcuts call
/// [togglePlayPause]/[seekBy]; [PlayerPanel] listens and performs the actual
/// play/pause/seek against its media_kit [Player].

abstract class _$PlayerControl extends $Notifier<PlayerCommand?> {
  PlayerCommand? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PlayerCommand?, PlayerCommand?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlayerCommand?, PlayerCommand?>,
              PlayerCommand?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
