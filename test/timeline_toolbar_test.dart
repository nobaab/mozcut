import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/ui/features/editor/view_models/editor_ui_state.dart';
import 'package:mozcut/ui/features/editor/views/timeline_toolbar.dart';

/// Covers the timeline toolbar's snap toggle (see docs/TIMELINE-BEHAVIOR.md
/// §7) — the other tools already have coverage via `editor_shortcuts_test
/// .dart`/`timeline_widget_test.dart`'s view-model-level tests.
void main() {
  testWidgets('tapping the snap button toggles snapEnabledProvider',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TimelineToolbar())),
      ),
    );

    expect(container.read(snapEnabledProvider), isTrue);

    await tester.tap(find.byIcon(Icons.align_horizontal_center));
    await tester.pump();
    expect(container.read(snapEnabledProvider), isFalse);

    await tester.tap(find.byIcon(Icons.align_horizontal_center));
    await tester.pump();
    expect(container.read(snapEnabledProvider), isTrue);
  });
}
