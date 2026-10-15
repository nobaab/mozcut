import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidkaat/ui/features/editor/views/effects_panel.dart';

void main() {
  testWidgets('effects panel renders an effect name', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    expect(find.text('Gaussian Blur'), findsOneWidget);
  });

  testWidgets('category chip filters the grid', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    await tester.tap(find.text('Blur'));
    await tester.pumpAndSettle();

    expect(find.text('Gaussian Blur'), findsOneWidget);
    expect(find.text('Chroma Key'), findsNothing);
  });

  testWidgets('tapping an effect shows a coming-soon snackbar',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );

    await tester.tap(find.text('Sharpen'));
    await tester.pump();

    expect(find.text('Sharpen — coming soon'), findsOneWidget);
  });
}
