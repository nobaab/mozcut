import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/ui/features/editor/views/stickers_panel.dart';

void main() {
  testWidgets('shows the emoji category by default with a populated grid',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StickersPanel())),
    );

    expect(find.text('😀'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('switching category shows image-sticker placeholders',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StickersPanel())),
    );

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    expect(find.text('😀'), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
  });

  testWidgets('tapping a sticker shows a coming-soon snackbar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StickersPanel())),
    );

    await tester.tap(find.text('😀'));
    await tester.pump();

    expect(find.text('Placing stickers — coming soon'), findsOneWidget);
  });

  testWidgets('searching filters the grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StickersPanel())),
    );

    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'star');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
