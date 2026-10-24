import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/media_type.dart';
import 'audio_clips_view_model.dart';
import 'editor_view_model.dart';

/// Imports [paths] via the Import button and drag-and-drop share: video and
/// image files become a [Clip] on the main track (`Editor.addClip` already
/// branches on [MediaType] for the image case); audio files become an
/// `AudioClip` on the project's audio lane instead. One chokepoint so both
/// call sites (the media browser's Import button and any `DropTarget`) can
/// never drift on how a dropped/picked file is routed.
///
/// [onError] is called once per file that fails to import, with a
/// human-readable message — callers typically show it in a SnackBar.
Future<void> importMediaPaths(
  WidgetRef ref,
  Iterable<String> paths, {
  required void Function(String message) onError,
}) async {
  for (final path in paths) {
    final name = path.split(RegExp(r'[/\\]')).last;
    try {
      if (mediaTypeForPath(path) == MediaType.audio) {
        await ref.read(audioClipsProvider.notifier).addFromPath(path);
      } else {
        await ref.read(editorProvider.notifier).addClip(path);
      }
    } catch (e) {
      onError('Could not import $name: $e');
    }
  }
}
