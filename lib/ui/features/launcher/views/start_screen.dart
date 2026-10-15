import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/project/project_store.dart';
import '../../../../domain/models/project.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/launcher_view_model.dart';
import 'new_project_dialog.dart';

/// The launcher: everything you can do before a project is open. A heading,
/// a grid whose first card starts a new project, and a poster card for every
/// project this machine has opened. Modelled on Concat's start screen.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  static const double _minCard = 220;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF131418),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading
              Row(
                children: [
                  const Text('✂️  Vidkaat',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  VButton(
                    label: 'Open from disk',
                    icon: Icons.folder_open,
                    onPressed: () => _openFromDisk(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Projects',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Everything you have opened on this machine.',
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 24),

              Expanded(
                child: recents.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Could not load recents: $e')),
                  data: (list) => _grid(context, ref, list),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<RecentProject> list) {
    return LayoutBuilder(builder: (context, c) {
      final cols = ((c.maxWidth + _gap) / (_minCard + _gap)).floor().clamp(1, 8);
      final cardW = (c.maxWidth - (cols - 1) * _gap) / cols;
      final cardH = cardW * 9 / 16 + 78;

      return SingleChildScrollView(
        child: Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            SizedBox(
              width: cardW,
              height: cardH,
              child: _NewProjectCard(
                  onTap: () => showNewProjectDialog(context)),
            ),
            for (final r in list)
              SizedBox(
                width: cardW,
                height: cardH,
                child: _PosterCard(
                  project: r,
                  onOpen: () => _open(context, ref, r.path),
                  onForget: () =>
                      ref.read(appProvider.notifier).forget(r.path),
                ),
              ),
          ],
        ),
      );
    });
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String path) async {
    try {
      await ref.read(appProvider.notifier).openRecent(path);
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not open: $e');
    }
  }

  Future<void> _openFromDisk(BuildContext context, WidgetRef ref) async {
    await FilePicker.skipEntitlementsChecks();
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Open a Vidkaat project folder');
    if (dir == null) return;
    if (context.mounted) await _open(context, ref, dir);
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F2026),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 32, color: Color(0xFF0568FD)),
              SizedBox(height: 10),
              Text('New Project',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.project,
    required this.onOpen,
    required this.onForget,
  });

  final RecentProject project;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final poster = project.posterPath;
    final hasPoster = poster != null && File(poster).existsSync();

    return Material(
      color: const Color(0xFF1F2026),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Poster
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: const Color(0xFF0C0D10),
                      child: hasPoster
                          ? Image.file(File(poster),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => _filmIcon())
                          : _filmIcon(),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _ForgetButton(onForget: onForget),
                    ),
                  ],
                ),
              ),
              // Meta
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(project.video.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12)),
                    Text(project.when,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filmIcon() => Center(
        child: Icon(Icons.movie_outlined,
            color: Colors.white.withValues(alpha: 0.25), size: 32),
      );
}

class _ForgetButton extends StatelessWidget {
  const _ForgetButton({required this.onForget});
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onForget,
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.close, size: 14, color: Colors.white70),
        ),
      ),
    );
  }
}
