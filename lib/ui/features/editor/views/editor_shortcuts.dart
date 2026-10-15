import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/editor_view_model.dart';
import '../view_models/player_control.dart';

/// Keyboard shortcuts for the editor.
///
/// Wraps the editor body in a [Focus] node that sits above every panel.
/// Flutter dispatches key events starting at whatever currently has focus
/// and bubbles them up through ancestor [Focus] nodes, so a focused text
/// field (search box, caption editor, inspector field, …) always gets first
/// refusal — and on top of that, [_textFieldHasFocus] explicitly bails out
/// whenever a text field owns focus, so none of these bindings ever hijack
/// typing.
class EditorShortcuts extends ConsumerWidget {
  const EditorShortcuts({super.key, required this.child});

  final Widget child;

  /// One frame at 30fps — matches the player's timecode.
  static const double nudgeSeconds = 1 / 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleKey(context, ref, event),
      child: child,
    );
  }

  KeyEventResult _handleKey(
      BuildContext context, WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never hijack typing: once a text field owns focus, let the event go
    // to it (and its own built-in editing shortcuts) untouched.
    if (_textFieldHasFocus()) return KeyEventResult.ignored;

    for (final entry in _bindings(context, ref).entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _textFieldHasFocus() {
    final widget = FocusManager.instance.primaryFocus?.context?.widget;
    return widget is EditableText;
  }

  Map<ShortcutActivator, VoidCallback> _bindings(
      BuildContext context, WidgetRef ref) {
    return {
      const SingleActivator(LogicalKeyboardKey.space): () =>
          ref.read(playerControlProvider.notifier).togglePlayPause(),
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
          _split(ref),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
          _split(ref),
      const SingleActivator(LogicalKeyboardKey.keyS): () => _split(ref),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          ref.read(editorProvider.notifier).removeSelected(),
      const SingleActivator(LogicalKeyboardKey.backspace): () =>
          ref.read(editorProvider.notifier).removeSelected(),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
          _undo(context),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          _undo(context),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          ref.read(playerControlProvider.notifier).seekBy(-nudgeSeconds),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          ref.read(playerControlProvider.notifier).seekBy(nudgeSeconds),
    };
  }

  void _split(WidgetRef ref) {
    final playhead = ref.read(playheadProvider);
    ref.read(editorProvider.notifier).splitSelectedAt(playhead);
  }

  void _undo(BuildContext context) {
    // No undo/redo stack exists yet — this is a placeholder so Cmd/Ctrl+Z
    // does *something* sensible instead of being silently swallowed.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Nothing to undo')));
  }
}

/// Shows the shortcut reference the title bar's "Shortcuts" button opens.
void showEditorShortcutsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: const SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShortcutRow('Space', 'Play / pause'),
            _ShortcutRow('⌘/Ctrl + B, or S', 'Split clip at playhead'),
            _ShortcutRow('Delete / Backspace', 'Remove selected clip'),
            _ShortcutRow('⌘/Ctrl + Z', 'Undo'),
            _ShortcutRow('← / →', 'Nudge playhead'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.keys, this.label);

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(keys,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
