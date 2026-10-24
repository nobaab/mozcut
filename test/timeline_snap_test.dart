import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/audio_clip.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/domain/models/video_overlay.dart';
import 'package:mozcut/ui/features/editor/timeline_snap.dart';

/// Covers the pure snapping math behind the timeline's magnetic drag/trim
/// (see docs/TIMELINE-BEHAVIOR.md §7): nearest-within-threshold, exclusion of
/// the item being dragged, no-target-returns-null, and the 8px-at-any-zoom
/// threshold.
void main() {
  group('snapThresholdSeconds', () {
    test('converts 8 screen pixels to seconds at the given zoom', () {
      expect(snapThresholdSeconds(40), closeTo(0.2, 0.0001)); // 8/40
      expect(snapThresholdSeconds(80), closeTo(0.1, 0.0001)); // 8/80
    });

    test('threshold scales with zoom — halves when pixels-per-second doubles',
        () {
      final low = snapThresholdSeconds(40);
      final high = snapThresholdSeconds(80);
      expect(high, closeTo(low / 2, 0.0001));
    });

    test('is 0 for a non-positive zoom rather than dividing badly', () {
      expect(snapThresholdSeconds(0), 0);
      expect(snapThresholdSeconds(-5), 0);
    });
  });

  group('snapTime', () {
    test('returns the nearest target within the threshold', () {
      expect(snapTime(5.05, [0, 5, 10], 0.1), 5);
      expect(snapTime(9.95, [0, 5, 10], 0.1), 10);
    });

    test('returns null when nothing is within the threshold', () {
      expect(snapTime(5.5, [0, 5, 10], 0.1), isNull);
    });

    test('returns null for an empty target list', () {
      expect(snapTime(5.0, [], 0.1), isNull);
    });

    test('is inclusive at exactly the threshold distance', () {
      expect(snapTime(5.1, [5], 0.1), 5);
    });

    test('picks the closer of two in-range targets', () {
      expect(snapTime(5.03, [5, 5.08], 0.1), 5);
      expect(snapTime(5.07, [5, 5.08], 0.1), 5.08);
    });

    test('ties favour whichever target appears first', () {
      expect(snapTime(5.0, [5.0, 5.0], 0.1), 5.0);
    });
  });

  group('computeClipStarts', () {
    test('each clip starts where the previous one ends', () {
      final clips = [
        Clip(sourcePath: '/a.mp4', sourceDuration: 10, outPoint: 4),
        Clip(sourcePath: '/b.mp4', sourceDuration: 10, outPoint: 6),
        Clip(sourcePath: '/c.mp4', sourceDuration: 10, outPoint: 2),
      ];
      expect(computeClipStarts(clips), [0, 4, 10]);
    });

    test('empty clip list -> empty starts', () {
      expect(computeClipStarts(const []), isEmpty);
    });
  });

  group('collectSnapTargets', () {
    Clip clip(String path, double duration) =>
        Clip(sourcePath: path, sourceDuration: duration, outPoint: duration);

    test('includes 0, the playhead, and every clip edge', () {
      final clips = [clip('/a.mp4', 5), clip('/b.mp4', 3)];
      final targets = collectSnapTargets(playhead: 7, clips: clips);
      expect(targets, containsAll([0, 7, 0, 5, 5, 8]));
    });

    test('excludes the clip being dragged, by id', () {
      final clips = [clip('/a.mp4', 5), clip('/b.mp4', 3)];
      final dragged = clips[0].id;
      final targets = collectSnapTargets(
        playhead: 0,
        clips: clips,
        excludeClipId: dragged,
      );
      // b.mp4's edges (5, 8) remain; a.mp4's own edges (0, 5) are only
      // present once (as 0, from the base targets / b's start) — not
      // double-contributed by the excluded clip.
      expect(targets.where((t) => t == 5).length, 1); // b's start only
      expect(targets, contains(8)); // b's end
    });

    test('includes audio-clip and video-overlay edges, excludable by id', () {
      final audio = AudioClip(
          sourcePath: '/x.mp3', sourceDuration: 10, start: 2, outPoint: 4);
      final overlay = VideoOverlay(
          sourcePath: '/y.mp4', sourceDuration: 10, startTime: 6, outPoint: 1);
      final targets = collectSnapTargets(
        playhead: 0,
        clips: const [],
        audioClips: [audio],
        overlays: [overlay],
      );
      expect(targets, containsAll([2, 6, 6, 7]));

      final excluded = collectSnapTargets(
        playhead: 0,
        clips: const [],
        audioClips: [audio],
        overlays: [overlay],
        excludeAudioClipId: audio.id,
        excludeOverlayId: overlay.id,
      );
      expect(excluded, isNot(contains(2)));
      expect(excluded, isNot(contains(7)));
    });

    test('no items at all -> just 0 and the playhead', () {
      final targets =
          collectSnapTargets(playhead: 3, clips: const []);
      expect(targets, [0, 3]);
    });
  });

  group('snapMove', () {
    test('snaps the leading edge when it is nearer a target', () {
      final result = snapMove(
        start: 4.95,
        duration: 2,
        targets: [5, 20],
        thresholdSeconds: 0.2,
      );
      expect(result, isNotNull);
      expect(result!.start, closeTo(5.0, 0.0001));
      expect(result.lineAt, closeTo(5.0, 0.0001));
    });

    test('snaps the trailing edge when it is nearer a target', () {
      // start=9.9, duration=2 -> end candidate 11.9, close to target 12.
      final result = snapMove(
        start: 9.9,
        duration: 2,
        targets: [0, 12],
        thresholdSeconds: 0.2,
      );
      expect(result, isNotNull);
      expect(result!.start, closeTo(10.0, 0.0001));
      expect(result.lineAt, closeTo(12.0, 0.0001));
    });

    test('returns null when neither edge is in range', () {
      final result = snapMove(
        start: 4.0,
        duration: 2,
        targets: [10, 20],
        thresholdSeconds: 0.2,
      );
      expect(result, isNull);
    });

    test('prefers whichever edge needs the smaller correction', () {
      // Leading edge candidate 4.95 (0.05 off target 5); trailing edge
      // candidate 6.95+... construct so trailing needs a bigger correction.
      final result = snapMove(
        start: 4.95,
        duration: 3,
        targets: [5, 7.5], // leading snaps to 5 (delta .05); trailing to 7.5
        // (candidate end = 7.95, delta .45) — leading should win.
        thresholdSeconds: 0.5,
      );
      expect(result, isNotNull);
      expect(result!.start, closeTo(5.0, 0.0001));
    });
  });
}
