import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/export_settings.dart';

void main() {
  group('ExportSettings defaults', () {
    test('reproduce the export pipeline\'s original, hardcoded behaviour',
        () {
      const settings = ExportSettings();
      expect(settings.videoCodecName, 'libx264');
      expect(settings.crf, 18);
      expect(settings.fileExtension, 'mp4');
      expect(settings.scaleFilter, isNull);
      expect(
        settings.toFfmpegArgs(),
        ['-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-c:a', 'aac'],
      );
    });
  });

  group('resolution', () {
    test('null width/height means no scale filter', () {
      const settings = ExportSettings();
      expect(settings.scaleFilter, isNull);
    });

    test('both dimensions set', () {
      const settings = ExportSettings(width: 1920, height: 1080);
      expect(settings.scaleFilter, 'scale=1920:1080');
    });

    test('only height set keeps aspect via -2 for width', () {
      const settings = ExportSettings(height: 720);
      expect(settings.scaleFilter, 'scale=-2:720');
    });

    test('only width set keeps aspect via -2 for height', () {
      const settings = ExportSettings(width: 3840);
      expect(settings.scaleFilter, 'scale=3840:-2');
    });
  });

  group('frame rate', () {
    test('null fps omits -r', () {
      const settings = ExportSettings();
      expect(settings.toFfmpegArgs().contains('-r'), isFalse);
    });

    test('whole-number fps renders without decimals', () {
      const settings = ExportSettings(fps: 30);
      final args = settings.toFfmpegArgs();
      expect(args[args.indexOf('-r') + 1], '30');
    });
  });

  group('codec + quality -> crf', () {
    test('h264 low/recommended/high', () {
      expect(const ExportSettings(quality: ExportQuality.low).crf, 28);
      expect(
          const ExportSettings(quality: ExportQuality.recommended).crf, 18);
      expect(const ExportSettings(quality: ExportQuality.high).crf, 12);
    });

    test('hevc uses a different (higher) crf scale than h264', () {
      const low = ExportSettings(codec: ExportCodec.hevc, quality: ExportQuality.low);
      const rec = ExportSettings(
          codec: ExportCodec.hevc, quality: ExportQuality.recommended);
      const high =
          ExportSettings(codec: ExportCodec.hevc, quality: ExportQuality.high);
      expect(low.crf, 31);
      expect(rec.crf, 21);
      expect(high.crf, 15);
      expect(rec.videoCodecName, 'libx265');
    });
  });

  group('format', () {
    test('mp4 and mov map to the matching extension', () {
      expect(const ExportSettings(format: ExportFormat.mp4).fileExtension,
          'mp4');
      expect(const ExportSettings(format: ExportFormat.mov).fileExtension,
          'mov');
    });
  });

  group('toFfmpegArgs full mapping', () {
    test('combines codec, crf, fps and audio codec in order', () {
      const settings = ExportSettings(
        width: 1920,
        height: 1080,
        fps: 24,
        codec: ExportCodec.hevc,
        quality: ExportQuality.high,
        format: ExportFormat.mov,
      );
      expect(settings.scaleFilter, 'scale=1920:1080');
      expect(
        settings.toFfmpegArgs(),
        [
          '-c:v', 'libx265',
          '-preset', 'medium',
          '-crf', '15',
          '-r', '24',
          '-c:a', 'aac',
        ],
      );
      expect(settings.fileExtension, 'mov');
    });
  });
}
