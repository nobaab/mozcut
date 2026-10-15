import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/ui/features/editor/view_models/sticker_overlays_view_model.dart';
import 'package:mozcut/ui/features/editor/views/stickers_panel.dart';

void main() {
  Widget harness() => const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StickersPanel())),
      );

  testWidgets('shows the emoji category by default with a populated grid',
      (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('😀'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('switching category shows image-sticker placeholders',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    expect(find.text('😀'), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
  });

  testWidgets('tapping a non-emoji sticker shows a coming-soon snackbar',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.image_outlined).first);
    await tester.pump();

    expect(find.text('Placing stickers — coming soon'), findsOneWidget);
  });

  testWidgets(
      'tapping an emoji adds it to the project and lists it below',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StickersPanel())),
      ),
    );

    await tester.tap(find.text('😀'));
    await tester.pump();

    expect(find.text('Added 😀 to the project'), findsOneWidget);
    expect(container.read(stickerOverlaysProvider).length, 1);
    expect(container.read(stickerOverlaysProvider).first.emoji, '😀');
  });

  testWidgets('searching filters the grid', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'star');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
