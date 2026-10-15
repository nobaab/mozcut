import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/domain/models/text_overlay.dart';
import 'package:vidkaat/ui/features/editor/view_models/text_overlays_view_model.dart';

void main() {
  group('TextOverlay', () {
    test('survives a JSON round-trip', () {
      final overlay = TextOverlay(
        text: 'Hello, world!',
        start: 1.25,
        end: 4.5,
        fontSize: 0.12,
        color: '#FF0000',
        alignment: TextOverlayAlignment.right,
        x: 0.75,
        y: 0.2,
      );

      final restored = TextOverlay.fromJson(overlay.toJson());

      expect(restored.id, overlay.id);
      expect(restored.text, 'Hello, world!');
      expect(restored.start, 1.25);
      expect(restored.end, 4.5);
      expect(restored.fontSize, 0.12);
      expect(restored.color, '#FF0000');
      expect(restored.alignment, TextOverlayAlignment.right);
      expect(restored.x, 0.75);
      expect(restored.y, 0.2);
      expect(restored, overlay);
    });

    test('fromJson fills in defaults for an old/partial manifest', () {
      final restored = TextOverlay.fromJson({
        'id': 'x',
        'text': 'Hi',
        'start': 0.0,
        'end': 2.0,
      });

      expect(restored.fontSize, 0.08);
      expect(restored.color, '#FFFFFF');
      expect(restored.alignment, TextOverlayAlignment.center);
      expect(restored.x, 0.5);
      expect(restored.y, 0.85);
    });

    test('copyWith only overrides given fields and keeps the id', () {
      final overlay = TextOverlay(text: 'Hi', start: 0, end: 2);
      final edited = overlay.copyWith(text: 'Hi there', fontSize: 0.2);

      expect(edited.id, overlay.id);
      expect(edited.text, 'Hi there');
      expect(edited.fontSize, 0.2);
      expect(edited.start, 0);
      expect(edited.end, 2);
    });

    test('duration is end minus start, never negative', () {
      expect(TextOverlay(text: 'a', start: 1, end: 4).duration, 3);
      expect(TextOverlay(text: 'a', start: 4, end: 1).duration, 0);
    });
  });

  group('TextOverlays notifier', () {
    late ProviderContainer container;
    late TextOverlays notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(textOverlaysProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(container.read(textOverlaysProvider), isEmpty);
    });

    test('add appends a default overlay and returns it', () {
      final added = notifier.add();
      final state = container.read(textOverlaysProvider);

      expect(state.length, 1);
      expect(state.first, added);
      expect(added.text, isNotEmpty);
    });

    test('update replaces the overlay at the given index', () {
      notifier.add();
      notifier.add();
      final second = container.read(textOverlaysProvider)[1];

      notifier.update(1, second.copyWith(text: 'Edited'));

      expect(container.read(textOverlaysProvider)[1].text, 'Edited');
      expect(container.read(textOverlaysProvider)[0].text,
          isNot('Edited'));
    });

    test('update ignores an out-of-range index', () {
      notifier.add();
      final before = container.read(textOverlaysProvider);
      notifier.update(5, before.first.copyWith(text: 'nope'));
      expect(container.read(textOverlaysProvider), before);
    });

    test('removeAt deletes the overlay at the given index', () {
      notifier.add();
      notifier.add();
      notifier.removeAt(0);
      expect(container.read(textOverlaysProvider).length, 1);
    });

    test('removeAt ignores an out-of-range index', () {
      notifier.add();
      notifier.removeAt(99);
      expect(container.read(textOverlaysProvider).length, 1);
    });

    test('load replaces the whole list (used when opening a project)', () {
      notifier.add();
      final fresh = [
        TextOverlay(text: 'From manifest', start: 0, end: 3),
      ];
      notifier.load(fresh);
      expect(container.read(textOverlaysProvider), fresh);
    });
  });
}
