import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'state/app_state.dart';
import 'ui/editor_page.dart';
import 'ui/start_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit needs this once before any Player is created.
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: VidkaatApp()));
}

class VidkaatApp extends StatelessWidget {
  const VidkaatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vidkaat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF17181C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0568FD),
          surface: Color(0xFF1F2026),
        ),
      ),
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
