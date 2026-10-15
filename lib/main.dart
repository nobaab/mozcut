import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'ui/core/app_theme.dart';
import 'ui/features/editor/views/editor_page.dart';
import 'ui/features/launcher/view_models/launcher_view_model.dart';
import 'ui/features/launcher/views/start_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit needs this once before any Player is created.
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: MozCutApp()));
}

class MozCutApp extends StatelessWidget {
  const MozCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MozCut',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _Root(),
    );
  }
}

/// Shows the launcher until a project is open, then the editor.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(appProvider);
    return project == null ? const StartScreen() : const EditorPage();
  }
}
