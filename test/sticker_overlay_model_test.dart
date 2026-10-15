import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/sticker_overlay.dart';
import 'package:mozcut/ui/features/editor/view_models/sticker_overlays_view_model.dart';

void main() {
  group('StickerOverlay', () {
    test('survives a JSON round-trip', () {
      final sticker = StickerOverlay(
        emoji: '🔥',
        start: 1.25,
        end: 4.5,
        size: 0.2,
        x: 0.75,
        y: 0.2,
      );

      final restored = StickerOverlay.fromJson(sticker.toJson());

      expect(restored.id, sticker.id);
      expect(restored.emoji, '🔥');
      expect(restored.start, 1.25);
      expect(restored.end, 4.5);
      expect(restored.size, 0.2);
      expect(restored.x, 0.75);
      expect(restored.y, 0.2);
      expect(restored, sticker);
    });

    test('fromJson fills in defaults for an old/partial manifest', () {
      final restored = StickerOverlay.fromJson({
        'id': 'x',
        'emoji': '🎉',
        'start': 0.0,
        'end': 2.0,
      });

      expect(restored.size, 0.12);
      expect(restored.x, 0.5);
      expect(restored.y, 0.5);
    });

    test('copyWith only overrides given fields and keeps the id', () {
      final sticker = StickerOverlay(emoji: '😀', start: 0, end: 2);
      final edited = sticker.copyWith(emoji: '😎', size: 0.3);

      expect(edited.id, sticker.id);
      expect(edited.emoji, '😎');
      expect(edited.size, 0.3);
      expect(edited.start, 0);
      expect(edited.end, 2);
    });

    test('duration is end minus start, never negative', () {
      expect(StickerOverlay(emoji: '🔥', start: 1, end: 4).duration, 3);
      expect(StickerOverlay(emoji: '🔥', start: 4, end: 1).duration, 0);
    });
  });

  group('StickerOverlays notifier', () {
    late ProviderContainer container;
    late StickerOverlays notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(stickerOverlaysProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(container.read(stickerOverlaysProvider), isEmpty);
    });

    test('add appends a default sticker with the given emoji and returns it',
        () {
      final added = notifier.add('🔥');
      final state = container.read(stickerOverlaysProvider);

      expect(state.length, 1);
      expect(state.first, added);
      expect(added.emoji, '🔥');
    });

    test('update replaces the sticker at the given index', () {
      notifier.add('😀');
      notifier.add('😎');
      final second = container.read(stickerOverlaysProvider)[1];

      notifier.update(1, second.copyWith(emoji: '🎉'));

      expect(container.read(stickerOverlaysProvider)[1].emoji, '🎉');
      expect(container.read(stickerOverlaysProvider)[0].emoji, isNot('🎉'));
    });

    test('update ignores an out-of-range index', () {
      notifier.add('😀');
      final before = container.read(stickerOverlaysProvider);
      notifier.update(5, before.first.copyWith(emoji: 'nope'));
      expect(container.read(stickerOverlaysProvider), before);
    });

    test('removeAt deletes the sticker at the given index', () {
      notifier.add('😀');
      notifier.add('😎');
      notifier.removeAt(0);
      expect(container.read(stickerOverlaysProvider).length, 1);
    });

    test('removeAt ignores an out-of-range index', () {
      notifier.add('😀');
      notifier.removeAt(99);
      expect(container.read(stickerOverlaysProvider).length, 1);
    });

    test('load replaces the whole list (used when opening a project)', () {
      notifier.add('😀');
      final fresh = [
        StickerOverlay(emoji: 'From manifest', start: 0, end: 3),
      ];
      notifier.load(fresh);
      expect(container.read(stickerOverlaysProvider), fresh);
    });
  });
}
