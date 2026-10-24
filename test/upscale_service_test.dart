import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/data/upscale/upscale_service.dart';

/// Pure-logic tests for the AI upscale pipeline — no realesrgan-ncnn-vulkan
/// binary required. These cover the parts of upscale_service.dart that don't
/// spawn a process: cache-key hashing, base-resolution/scale math, fps
/// parsing, chunking, frame-number extraction, and model-name resolution.
void main() {
  group('baseFrameDimensions', () {
    test('divides target by scale', () {
      final dims = baseFrameDimensions(
          targetWidth: 1920, targetHeight: 1080, scale: 4);
      expect(dims.$1, 480);
      expect(dims.$2, 270);
    });

    test('rounds down to even dimensions', () {
      final dims = baseFrameDimensions(
          targetWidth: 1921, targetHeight: 1081, scale: 4);
      // 1921/4 = 480.25 -> floor 480 (already even)
      // 1081/4 = 270.25 -> floor 270 (already even)
      expect(dims.$1 % 2, 0);
      expect(dims.$2 % 2, 0);
    });

    test('rounds an odd floor down to the next even number', () {
      final dims =
          baseFrameDimensions(targetWidth: 1930, targetHeight: 1090, scale: 4);
      // 1930/4 = 482.5 -> floor 482 (even, kept)
      // 1090/4 = 272.5 -> floor 272 (even, kept)
      expect(dims.$1, 482);
      expect(dims.$2, 272);
    });

    test('never produces a dimension below 2', () {
      final dims =
          baseFrameDimensions(targetWidth: 2, targetHeight: 2, scale: 100);
      expect(dims.$1, greaterThanOrEqualTo(2));
      expect(dims.$2, greaterThanOrEqualTo(2));
    });
  });

  group('chunkFrames', () {
    test('splits frames into chunks of the given size', () {
      final frames = List.generate(10, (i) => 'frame_$i.png');
      final chunks = chunkFrames(frames, 3);
      expect(chunks.length, 4);
      expect(chunks[0], ['frame_0.png', 'frame_1.png', 'frame_2.png']);
      expect(chunks.last, ['frame_9.png']);
    });

    test('a chunk size covering every frame returns one chunk', () {
      final frames = List.generate(5, (i) => 'frame_$i.png');
      final chunks = chunkFrames(frames, 100);
      expect(chunks, [frames]);
    });

    test('non-positive chunk size returns everything as one chunk', () {
      final frames = List.generate(5, (i) => 'frame_$i.png');
      expect(chunkFrames(frames, 0), [frames]);
      expect(chunkFrames(frames, -1), [frames]);
    });

    test('empty frame list returns no chunks', () {
      expect(chunkFrames(const [], 10), isEmpty);
    });
  });

  group('parseFrameRate', () {
    test('parses a fractional frame rate', () {
      expect(parseFrameRate('30000/1001'), closeTo(29.97, 0.01));
    });

    test('parses a whole-number fraction', () {
      expect(parseFrameRate('30/1'), 30.0);
    });

    test('parses a bare number', () {
      expect(parseFrameRate('24'), 24.0);
    });

    test('falls back to 30fps for unparseable input', () {
      expect(parseFrameRate(''), 30.0);
      expect(parseFrameRate('garbage'), 30.0);
      expect(parseFrameRate('1/0'), 30.0);
    });
  });

  group('frameNumberFromPath', () {
    test('extracts the numeric sequence from a frame filename', () {
      expect(frameNumberFromPath('/tmp/chunk/frame_00000042.png'), 42);
    });

    test('works with backslash paths', () {
      expect(frameNumberFromPath(r'C:\tmp\chunk\frame_00000007.png'), 7);
    });

    test('defaults to 1 when no digits are present', () {
      expect(frameNumberFromPath('/tmp/chunk/frame.png'), 1);
    });
  });

  group('resolveModelName', () {
    test('appends the scale suffix to the default animevideov3 model', () {
      expect(resolveModelName('realesr-animevideov3', 4),
          'realesr-animevideov3-x4');
      expect(resolveModelName('realesr-animevideov3', 2),
          'realesr-animevideov3-x2');
    });

    test('leaves an already-suffixed model name unchanged', () {
      expect(resolveModelName('realesr-animevideov3-x3', 4),
          'realesr-animevideov3-x3');
    });

    test('passes through any other model name unchanged', () {
      expect(resolveModelName('realesrgan-x4plus', 4), 'realesrgan-x4plus');
    });
  });

  group('computeUpscaleCacheKey', () {
    _Params params({
      String sourcePath = '/a.mp4',
      double inPoint = 0,
      double outPoint = 10,
      int targetWidth = 1920,
      int targetHeight = 1080,
      int scale = 4,
      String model = 'realesr-animevideov3',
    }) =>
        _Params(
          sourcePath: sourcePath,
          inPoint: inPoint,
          outPoint: outPoint,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          scale: scale,
          model: model,
        );

    test('is deterministic for the same inputs', () {
      final p = params();
      expect(p.key(), p.key());
    });

    test('returns a fixed-length hex string (not Object.hashCode, which is '
        'randomized per isolate)', () {
      expect(params().key().length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(params().key()), isTrue);
    });

    test('changes when the source path changes', () {
      expect(params().key(), isNot(params(sourcePath: '/b.mp4').key()));
    });

    test('changes when the trim region changes', () {
      expect(params().key(), isNot(params(inPoint: 1).key()));
      expect(params().key(), isNot(params(outPoint: 11).key()));
    });

    test('changes when the target resolution changes', () {
      expect(params().key(), isNot(params(targetWidth: 3840).key()));
      expect(params().key(), isNot(params(targetHeight: 2160).key()));
    });

    test('changes when scale or model changes', () {
      expect(params().key(), isNot(params(scale: 2).key()));
      expect(params().key(), isNot(params(model: 'realesrgan-x4plus').key()));
    });
  });

  test('UpscaleException.toString returns the message', () {
    final e = UpscaleException('binary not found');
    expect(e.toString(), 'binary not found');
  });

  group('UpscaleCancelToken', () {
    test('starts out not cancelled', () {
      expect(UpscaleCancelToken().isCancelled, isFalse);
    });

    test('cancel() marks it cancelled', () {
      final token = UpscaleCancelToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });
}

class _Params {
  const _Params({
    required this.sourcePath,
    required this.inPoint,
    required this.outPoint,
    required this.targetWidth,
    required this.targetHeight,
    required this.scale,
    required this.model,
  });

  final String sourcePath;
  final double inPoint;
  final double outPoint;
  final int targetWidth;
  final int targetHeight;
  final int scale;
  final String model;

  String key() => computeUpscaleCacheKey(
        sourcePath: sourcePath,
        inPoint: inPoint,
        outPoint: outPoint,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        scale: scale,
        model: model,
      );
}
