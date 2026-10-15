import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/ui/features/editor/view_models/thumbnails_view_model.dart';

/// Pure tests of the timeline filmstrip/waveform sizing math — no ffmpeg, no
/// widgets, no Riverpod container. See test/timeline_widget_test.dart for the
/// widget-level coverage (filmstrip/waveform rendering with a fake engine).
void main() {
  group('thumbnailCountForWidth', () {
    test('zero/negative width returns the minimum count', () {
      expect(thumbnailCountForWidth(0), 1);
      expect(thumbnailCountForWidth(-50), 1);
    });

    test('wider bars request more thumbnails', () {
      final narrow = thumbnailCountForWidth(100);
      final wide = thumbnailCountForWidth(1000);
      expect(wide, greaterThan(narrow));
    });

    test('count is clamped to [minCount, maxCount]', () {
      expect(
          thumbnailCountForWidth(1,
              bucketPx: 1, minCount: 3, maxCount: 10),
          3);
      expect(
          thumbnailCountForWidth(100000,
              bucketPx: 1, minCount: 1, maxCount: 10),
          10);
    });

    test('bucketing makes small width changes produce the same count '
        '(the zoom-change debounce)', () {
      // Two widths inside the same 48px bucket must agree exactly, so the
      // underlying Riverpod provider key (and therefore its cached result)
      // doesn't change for sub-bucket jitter (e.g. scrolling, a tiny zoom
      // nudge).
      final a = thumbnailCountForWidth(500);
      final b = thumbnailCountForWidth(500 + 10);
      expect(a, b);
    });

    test('crossing a bucket boundary can change the count', () {
      final low = thumbnailCountForWidth(48, bucketPx: 48);
      final high = thumbnailCountForWidth(48 * 5, bucketPx: 48);
      expect(high, greaterThan(low));
    });

    test('matches the expected tile-count formula for a known case', () {
      // thumbHeight=64, aspect=16/9 -> tileWidth = 64 * 16/9 ≈ 113.78.
      // bucketPx=48 -> bucket(960) = 960 (already a multiple of 48).
      // count = ceil(960 / 113.78) = ceil(8.44) = 9.
      expect(thumbnailCountForWidth(960), 9);
    });
  });

  group('waveformWidthForBarWidth', () {
    test('zero/negative width returns one bucket', () {
      expect(waveformWidthForBarWidth(0), 64);
      expect(waveformWidthForBarWidth(-10), 64);
    });

    test('rounds down to the nearest bucket, minimum one bucket', () {
      expect(waveformWidthForBarWidth(10, bucketPx: 64), 64);
      expect(waveformWidthForBarWidth(130, bucketPx: 64), 128);
      expect(waveformWidthForBarWidth(192, bucketPx: 64), 192);
    });

    test('small width changes within a bucket produce the same width', () {
      final a = waveformWidthForBarWidth(500);
      final b = waveformWidthForBarWidth(510);
      expect(a, b);
    });
  });
}
