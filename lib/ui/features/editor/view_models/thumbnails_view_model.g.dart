// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnails_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
/// used to paint the timeline's filmstrip. Resolves to an empty list while
/// loading or if extraction isn't possible — the timeline keeps its
/// solid-colour placeholder bar in either case, so this never throws.
///
/// `keepAlive` (matching every other provider in this app — see
/// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
/// `@riverpod` default `autoDispose`: a request is keyed on
/// `(clip, count, height)`, and both [Clip] and the bucketing in
/// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
/// recurs across rebuilds/scrolling, so once extracted it should just stay
/// cached for the rest of the editing session rather than being thrown away
/// (and re-run) the instant a clip bar briefly stops being watched — e.g.
/// while another clip is being dragged over it.

@ProviderFor(clipFilmstrip)
final clipFilmstripProvider = ClipFilmstripFamily._();

/// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
/// used to paint the timeline's filmstrip. Resolves to an empty list while
/// loading or if extraction isn't possible — the timeline keeps its
/// solid-colour placeholder bar in either case, so this never throws.
///
/// `keepAlive` (matching every other provider in this app — see
/// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
/// `@riverpod` default `autoDispose`: a request is keyed on
/// `(clip, count, height)`, and both [Clip] and the bucketing in
/// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
/// recurs across rebuilds/scrolling, so once extracted it should just stay
/// cached for the rest of the editing session rather than being thrown away
/// (and re-run) the instant a clip bar briefly stops being watched — e.g.
/// while another clip is being dragged over it.

final class ClipFilmstripProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
  /// used to paint the timeline's filmstrip. Resolves to an empty list while
  /// loading or if extraction isn't possible — the timeline keeps its
  /// solid-colour placeholder bar in either case, so this never throws.
  ///
  /// `keepAlive` (matching every other provider in this app — see
  /// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
  /// `@riverpod` default `autoDispose`: a request is keyed on
  /// `(clip, count, height)`, and both [Clip] and the bucketing in
  /// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
  /// recurs across rebuilds/scrolling, so once extracted it should just stay
  /// cached for the rest of the editing session rather than being thrown away
  /// (and re-run) the instant a clip bar briefly stops being watched — e.g.
  /// while another clip is being dragged over it.
  ClipFilmstripProvider._({
    required ClipFilmstripFamily super.from,
    required (Clip, int, int) super.argument,
  }) : super(
         retry: null,
         name: r'clipFilmstripProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipFilmstripHash();

  @override
  String toString() {
    return r'clipFilmstripProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    final argument = this.argument as (Clip, int, int);
    return clipFilmstrip(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipFilmstripProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipFilmstripHash() => r'b73cc5c26a8d69ccbcc638a1e17e90d91cd59249';

/// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
/// used to paint the timeline's filmstrip. Resolves to an empty list while
/// loading or if extraction isn't possible — the timeline keeps its
/// solid-colour placeholder bar in either case, so this never throws.
///
/// `keepAlive` (matching every other provider in this app — see
/// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
/// `@riverpod` default `autoDispose`: a request is keyed on
/// `(clip, count, height)`, and both [Clip] and the bucketing in
/// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
/// recurs across rebuilds/scrolling, so once extracted it should just stay
/// cached for the rest of the editing session rather than being thrown away
/// (and re-run) the instant a clip bar briefly stops being watched — e.g.
/// while another clip is being dragged over it.

final class ClipFilmstripFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<String>>, (Clip, int, int)> {
  ClipFilmstripFamily._()
    : super(
        retry: null,
        name: r'clipFilmstripProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Filmstrip thumbnail paths for [clip] ([count] of them, [height] tall),
  /// used to paint the timeline's filmstrip. Resolves to an empty list while
  /// loading or if extraction isn't possible — the timeline keeps its
  /// solid-colour placeholder bar in either case, so this never throws.
  ///
  /// `keepAlive` (matching every other provider in this app — see
  /// `editor_ui_state.dart`/`editor_view_model.dart`) rather than the
  /// `@riverpod` default `autoDispose`: a request is keyed on
  /// `(clip, count, height)`, and both [Clip] and the bucketing in
  /// [thumbnailCountForWidth]/[waveformWidthForBarWidth] mean the *same* key
  /// recurs across rebuilds/scrolling, so once extracted it should just stay
  /// cached for the rest of the editing session rather than being thrown away
  /// (and re-run) the instant a clip bar briefly stops being watched — e.g.
  /// while another clip is being dragged over it.

  ClipFilmstripProvider call(Clip clip, int count, int height) =>
      ClipFilmstripProvider._(argument: (clip, count, height), from: this);

  @override
  String toString() => r'clipFilmstripProvider';
}

/// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
/// while loading / if the clip has no audio (or rendering otherwise fails).
/// `keepAlive` for the same reason as [clipFilmstrip].

@ProviderFor(clipWaveform)
final clipWaveformProvider = ClipWaveformFamily._();

/// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
/// while loading / if the clip has no audio (or rendering otherwise fails).
/// `keepAlive` for the same reason as [clipFilmstrip].

final class ClipWaveformProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
  /// while loading / if the clip has no audio (or rendering otherwise fails).
  /// `keepAlive` for the same reason as [clipFilmstrip].
  ClipWaveformProvider._({
    required ClipWaveformFamily super.from,
    required (Clip, int, int) super.argument,
  }) : super(
         retry: null,
         name: r'clipWaveformProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipWaveformHash();

  @override
  String toString() {
    return r'clipWaveformProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as (Clip, int, int);
    return clipWaveform(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipWaveformProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipWaveformHash() => r'e3dab64c59e281fc427cc57162723e50a30e6b78';

/// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
/// while loading / if the clip has no audio (or rendering otherwise fails).
/// `keepAlive` for the same reason as [clipFilmstrip].

final class ClipWaveformFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String?>, (Clip, int, int)> {
  ClipWaveformFamily._()
    : super(
        retry: null,
        name: r'clipWaveformProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Waveform PNG path for [clip]'s trimmed audio ([width]x[height]), or null
  /// while loading / if the clip has no audio (or rendering otherwise fails).
  /// `keepAlive` for the same reason as [clipFilmstrip].

  ClipWaveformProvider call(Clip clip, int width, int height) =>
      ClipWaveformProvider._(argument: (clip, width, height), from: this);

  @override
  String toString() => r'clipWaveformProvider';
}

/// Waveform PNG path for an [AudioClip]'s trimmed region, for the audio
/// lane's clip bars. [Engine.waveformPng] only knows about [Clip], so this
/// adapts the audio clip's source/trim into a throwaway [Clip] with the same
/// `(sourcePath, inPoint, outPoint)` — the cache key [FfmpegEngine] uses for
/// waveform PNGs — so this reuses the exact same on-disk cache as the main
/// track's clip waveforms rather than needing a parallel one. `keepAlive` for
/// the same reason as [clipWaveform].

@ProviderFor(audioClipWaveform)
final audioClipWaveformProvider = AudioClipWaveformFamily._();

/// Waveform PNG path for an [AudioClip]'s trimmed region, for the audio
/// lane's clip bars. [Engine.waveformPng] only knows about [Clip], so this
/// adapts the audio clip's source/trim into a throwaway [Clip] with the same
/// `(sourcePath, inPoint, outPoint)` — the cache key [FfmpegEngine] uses for
/// waveform PNGs — so this reuses the exact same on-disk cache as the main
/// track's clip waveforms rather than needing a parallel one. `keepAlive` for
/// the same reason as [clipWaveform].

final class AudioClipWaveformProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// Waveform PNG path for an [AudioClip]'s trimmed region, for the audio
  /// lane's clip bars. [Engine.waveformPng] only knows about [Clip], so this
  /// adapts the audio clip's source/trim into a throwaway [Clip] with the same
  /// `(sourcePath, inPoint, outPoint)` — the cache key [FfmpegEngine] uses for
  /// waveform PNGs — so this reuses the exact same on-disk cache as the main
  /// track's clip waveforms rather than needing a parallel one. `keepAlive` for
  /// the same reason as [clipWaveform].
  AudioClipWaveformProvider._({
    required AudioClipWaveformFamily super.from,
    required (AudioClip, int, int) super.argument,
  }) : super(
         retry: null,
         name: r'audioClipWaveformProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$audioClipWaveformHash();

  @override
  String toString() {
    return r'audioClipWaveformProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as (AudioClip, int, int);
    return audioClipWaveform(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is AudioClipWaveformProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$audioClipWaveformHash() => r'f4221c61c920a58aea136c9f853bbb33cda8d960';

/// Waveform PNG path for an [AudioClip]'s trimmed region, for the audio
/// lane's clip bars. [Engine.waveformPng] only knows about [Clip], so this
/// adapts the audio clip's source/trim into a throwaway [Clip] with the same
/// `(sourcePath, inPoint, outPoint)` — the cache key [FfmpegEngine] uses for
/// waveform PNGs — so this reuses the exact same on-disk cache as the main
/// track's clip waveforms rather than needing a parallel one. `keepAlive` for
/// the same reason as [clipWaveform].

final class AudioClipWaveformFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String?>, (AudioClip, int, int)> {
  AudioClipWaveformFamily._()
    : super(
        retry: null,
        name: r'audioClipWaveformProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Waveform PNG path for an [AudioClip]'s trimmed region, for the audio
  /// lane's clip bars. [Engine.waveformPng] only knows about [Clip], so this
  /// adapts the audio clip's source/trim into a throwaway [Clip] with the same
  /// `(sourcePath, inPoint, outPoint)` — the cache key [FfmpegEngine] uses for
  /// waveform PNGs — so this reuses the exact same on-disk cache as the main
  /// track's clip waveforms rather than needing a parallel one. `keepAlive` for
  /// the same reason as [clipWaveform].

  AudioClipWaveformProvider call(AudioClip clip, int width, int height) =>
      AudioClipWaveformProvider._(argument: (clip, width, height), from: this);

  @override
  String toString() => r'audioClipWaveformProvider';
}
