/// The Audio panel's built-in "Sound effects" catalogue.
///
/// MozCut can't ship licensed music or sound effects, so instead of bundling
/// audio files this catalogue describes a handful of short tones/effects
/// *synthesized* entirely by ffmpeg's `lavfi` virtual input devices (sine
/// waves, coloured noise) — there is nothing to license because nothing is
/// shipped; the bytes are generated on first use. `FfmpegEngine.generateSfx`
/// renders (and disk-caches) the matching file for a given [SfxPreset.id].
///
/// Kept as plain data + a pure [SfxPreset.buildArgs] method (no `Process`
/// calls here) so the id -> ffmpeg-command mapping can be unit tested without
/// a real ffmpeg binary — see test/sfx_presets_test.dart.
library;

/// Groups the catalogue for the Audio panel's category chips.
enum SfxCategory {
  /// Clean, sustained tones — useful as beeps/alerts/countdown pips.
  tone,

  /// Short, shaped effects (clicks, pops, whooshes, impacts) for transitions.
  sfx,
}

/// One generated sound effect / tone.
class SfxPreset {
  const SfxPreset({
    required this.id,
    required this.label,
    required this.category,
    required this.duration,
    required this.lavfiSource,
    this.audioFilter,
  });

  /// Stable lookup key, also used as the cached output file's name (see
  /// `FfmpegEngine.generateSfx`) — e.g. `beep` -> `sfx_beep.wav`.
  final String id;

  /// Display name shown in the Audio panel's grid.
  final String label;

  final SfxCategory category;

  /// Rendered clip length, in seconds.
  final double duration;

  /// The ffmpeg `-f lavfi -i <...>` source expression that generates the raw
  /// signal: a `sine=...` tone or an `anoisesrc=...` coloured-noise burst.
  final String lavfiSource;

  /// Optional `-af` filter chain layered on top of [lavfiSource] (fades,
  /// band-pass) that shapes the raw signal into something that actually
  /// sounds like the effect it's named for (e.g. a fade-out turns a flat sine
  /// tone into a "pop").
  final String? audioFilter;

  /// The full ffmpeg argv that renders this preset to [outputPath]. Pure and
  /// deterministic — spawns nothing; the caller runs the process.
  List<String> buildArgs(String outputPath) => [
        '-y',
        '-f', 'lavfi',
        '-i', lavfiSource,
        if (audioFilter != null) ...['-af', audioFilter!],
        '-t', duration.toStringAsFixed(3),
        outputPath,
      ];
}

/// The full built-in catalogue, in the order the Audio panel's grid shows
/// them. Every [SfxPreset.id] here must be unique — see
/// test/sfx_presets_test.dart.
const kSfxPresets = <SfxPreset>[
  SfxPreset(
    id: 'beep',
    label: 'Beep',
    category: SfxCategory.tone,
    duration: 1.0,
    lavfiSource: 'sine=frequency=880:duration=1',
  ),
  SfxPreset(
    id: 'tick',
    label: 'Metronome tick',
    category: SfxCategory.tone,
    duration: 0.08,
    lavfiSource: 'sine=frequency=1500:duration=0.08',
    audioFilter: 'afade=t=out:st=0.02:d=0.06',
  ),
  SfxPreset(
    id: 'click',
    label: 'Click',
    category: SfxCategory.sfx,
    duration: 0.05,
    lavfiSource: 'sine=frequency=2500:duration=0.05',
    audioFilter: 'afade=t=out:st=0.01:d=0.04',
  ),
  SfxPreset(
    id: 'pop',
    label: 'Pop',
    category: SfxCategory.sfx,
    duration: 0.18,
    lavfiSource: 'sine=frequency=1000:duration=0.18',
    audioFilter: 'afade=t=out:st=0.02:d=0.16',
  ),
  SfxPreset(
    id: 'whoosh',
    label: 'Whoosh',
    category: SfxCategory.sfx,
    duration: 0.6,
    lavfiSource: 'anoisesrc=duration=0.6:color=pink:amplitude=0.9',
    audioFilter:
        'afade=t=in:d=0.08,afade=t=out:st=0.4:d=0.2,highpass=f=200,lowpass=f=5000',
  ),
  SfxPreset(
    id: 'boom',
    label: 'Boom',
    category: SfxCategory.sfx,
    duration: 1.2,
    lavfiSource: 'sine=frequency=55:duration=1.2',
    audioFilter: 'afade=t=out:st=0.2:d=1.0',
  ),
];
