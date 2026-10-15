import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_control.g.dart';

/// What [PlayerControl] is asking the preview player to do.
enum PlayerCommandType { togglePlayPause, seekBy }

/// A one-shot command from the keyboard shortcuts (or anywhere else) to the
/// preview player. [PlayerPanel] is the only listener and translates it into
/// a real media_kit call — nobody else should read this as state.
class PlayerCommand {
  const PlayerCommand(this.type, this._nonce, {this.seconds});

  final PlayerCommandType type;

  /// Seconds to seek by, relative to the current position. Only set for
  /// [PlayerCommandType.seekBy].
  final double? seconds;

  // Distinguishes otherwise-identical back-to-back commands (e.g. two
  // taps of Space) so Riverpod always notifies listeners.
  final int _nonce;

  @override
  bool operator ==(Object other) =>
      other is PlayerCommand && other._nonce == _nonce;

  @override
  int get hashCode => _nonce;
}

/// Command bus for the preview player. Keyboard shortcuts call
/// [togglePlayPause]/[seekBy]; [PlayerPanel] listens and performs the actual
/// play/pause/seek against its media_kit [Player].
@Riverpod(keepAlive: true)
class PlayerControl extends _$PlayerControl {
  int _nonce = 0;

  @override
  PlayerCommand? build() => null;

  void togglePlayPause() =>
      state = PlayerCommand(PlayerCommandType.togglePlayPause, _nonce++);

  void seekBy(double seconds) => state = PlayerCommand(
        PlayerCommandType.seekBy,
        _nonce++,
        seconds: seconds,
      );
}
