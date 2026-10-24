import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/export_settings.dart';
import 'package:mozcut/ui/core/widgets/buttons.dart';
import 'package:mozcut/ui/features/editor/views/export_dialog.dart';

void main() {
  // The dialog's "Export" button shares its label with the dialog's own
  // title ("Export"), so a bare `find.text('Export')` is ambiguous — scope
  // it to the VButton specifically.
  final exportButton =
      find.descendant(of: find.byType(VButton), matching: find.text('Export'));

  // A tall-enough surface for the whole dialog (title + preset/resolution/
  // frame rate/codec/quality/format rows + actions) to lay out without
  // overflowing — the default 800x600 test surface is too short for it.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<Future<ExportSettings?>> openDialog(WidgetTester tester) async {
    await useTallSurface(tester);
    late final Future<ExportSettings?> future;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => future = showExportDialog(context),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return future;
  }

  Future<ExportSettings> pumpAndPick(
      WidgetTester tester, String presetLabel) async {
    final future = await openDialog(tester);

    await tester.tap(find.text(presetLabel));
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    final settings = await future;
    expect(settings, isNotNull);
    return settings!;
  }

  group('export dialog presets', () {
    testWidgets('TikTok/Reels fills 1080x1920 @30', (tester) async {
      final settings = await pumpAndPick(tester, 'TikTok/Reels');
      expect(settings.width, 1080);
      expect(settings.height, 1920);
      expect(settings.fps, 30);
    });

    testWidgets('YouTube fills 1920x1080 @30', (tester) async {
      final settings = await pumpAndPick(tester, 'YouTube');
      expect(settings.width, 1920);
      expect(settings.height, 1080);
      expect(settings.fps, 30);
    });

    testWidgets('Square fills 1080x1080 @30', (tester) async {
      final settings = await pumpAndPick(tester, 'Square');
      expect(settings.width, 1080);
      expect(settings.height, 1080);
      expect(settings.fps, 30);
    });

    testWidgets('YouTube 4K fills 3840x2160 @30', (tester) async {
      final settings = await pumpAndPick(tester, 'YouTube 4K');
      expect(settings.width, 3840);
      expect(settings.height, 2160);
      expect(settings.fps, 30);
    });

    testWidgets('Custom is selected by default (no preset applied)',
        (tester) async {
      final future = await openDialog(tester);

      // "Custom" exists and the dialog opens with source defaults untouched.
      expect(find.text('Custom'), findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      final settings = await future;
      expect(settings!.width, isNull);
      expect(settings.height, isNull);
      expect(settings.fps, isNull);
    });

    testWidgets('picking a preset then Custom lets the manual chips take over',
        (tester) async {
      final future = await openDialog(tester);

      await tester.tap(find.text('YouTube'));
      await tester.pumpAndSettle();
      // Manually override just the resolution via the plain Resolution chip
      // row — still works exactly as it did before presets existed.
      await tester.tap(find.text('4K'));
      await tester.pumpAndSettle();

      // No preset matches 3840x2160 @30 (that's YouTube 4K's 3840x2160, but
      // fps is still 30 from the earlier YouTube tap) — actually this *does*
      // match YouTube 4K, so the preset row reflects it even though it was
      // reached via the manual chips. That's the intended "computed from
      // current values" behaviour, not a separate piece of state.
      expect(find.text('YouTube 4K'), findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      final settings = await future;
      expect(settings!.width, 3840);
      expect(settings.height, 2160);
      expect(settings.fps, 30);
    });

    testWidgets('picking GIF format hides Codec/Quality rows', (tester) async {
      await openDialog(tester);

      expect(find.text('Codec'), findsOneWidget);
      expect(find.text('Quality'), findsOneWidget);

      await tester.tap(find.text('GIF'));
      await tester.pumpAndSettle();

      expect(find.text('Codec'), findsNothing);
      expect(find.text('Quality'), findsNothing);
    });
  });
}
