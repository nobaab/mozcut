import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/editor_ui_state.dart';
import '../view_models/editor_view_model.dart';
import '../view_models/player_control.dart';

/// Keyboard shortcuts for the editor.
///
/// Earlier this used a [Focus] node, but on desktop a single click on a
/// non-focusable widget (a clip's [GestureDetector], a plain button) moves or
/// clears the primary focus, and key events are dispatched up the ancestor
/// chain of *whatever currently has focus* — so after one click the editor's
/// Focus node stopped receiving anything and every shortcut died. Instead this
/// registers a handler directly on [HardwareKeyboard], which sees every key
/// event regardless of what (if anything) is focused. [_textFieldHasFocus]
/// still bails out whenever a text field owns focus, so typing is never
/// hijacked.
class EditorShortcuts extends ConsumerStatefulWidget {
  const EditorShortcuts({super.key, required this.child});

  final Widget child;

  /// One frame at 30fps — matches the player's timecode.
  static const double nudgeSeconds = 1 / 30;

  @override
  ConsumerState<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends ConsumerState<EditorShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  /// Returns true to consume the event (so it isn't also delivered elsewhere).
  bool _handleKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Never hijack typing: once a text field owns focus, let the event go
    // to it (and its own built-in editing shortcuts) untouched.
    if (_textFieldHasFocus()) return false;

    for (final entry in _bindings(context, ref).entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return true;
      }
    }
    return false;
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
          _undo(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          _undo(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          () => _redo(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyZ,
          control: true, shift: true): () => _redo(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          _redo(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () =>
          _redo(context, ref),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => ref
          .read(playerControlProvider.notifier)
          .seekBy(-EditorShortcuts.nudgeSeconds),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => ref
          .read(playerControlProvider.notifier)
          .seekBy(EditorShortcuts.nudgeSeconds),
      // Shift+arrow seeks a full second rather than a frame — bound
      // separately from the plain arrow bindings above (SingleActivator's
      // `shift: false` default means those only match with Shift released,
      // so there's no ambiguity between the two).
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          ref.read(playerControlProvider.notifier).seekBy(-1.0),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          ref.read(playerControlProvider.notifier).seekBy(1.0),
      // Zoom. Bound on both the plain "=" key (Ctrl/Cmd+=, no shift) and its
      // shifted "+" counterpart — on a US keyboard, Shift+Equal is reported
      // as LogicalKeyboardKey.add (a distinct logical key, not `equal` with a
      // shift flag), so both must be registered to cover "Ctrl/Cmd + = (and
      // +)" from the spec.
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
          ref.read(timelineZoomProvider.notifier).zoomIn(),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          ref.read(timelineZoomProvider.notifier).zoomIn(),
      const SingleActivator(LogicalKeyboardKey.add, meta: true, shift: true):
          () => ref.read(timelineZoomProvider.notifier).zoomIn(),
      const SingleActivator(LogicalKeyboardKey.add,
          control: true, shift: true): () =>
          ref.read(timelineZoomProvider.notifier).zoomIn(),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
          ref.read(timelineZoomProvider.notifier).zoomOut(),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          ref.read(timelineZoomProvider.notifier).zoomOut(),
      // Duplicate the selected clip.
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
          ref.read(editorProvider.notifier).duplicateSelected(),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
          ref.read(editorProvider.notifier).duplicateSelected(),
      // Ripple-delete — bound only with Shift held, so it never collides
      // with the plain Delete binding above.
      const SingleActivator(LogicalKeyboardKey.delete, shift: true): () =>
          ref.read(editorProvider.notifier).rippleDeleteSelected(),
      // Toggle timeline snapping.
      const SingleActivator(LogicalKeyboardKey.keyN): () =>
          ref.read(snapEnabledProvider.notifier).toggle(),
    };
  }

  void _split(WidgetRef ref) {
    final playhead = ref.read(playheadProvider);
    ref.read(editorProvider.notifier).splitSelectedAt(playhead);
  }

  void _undo(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorProvider.notifier);
    if (!notifier.canUndo) {
      _showSnack(context, 'Nothing to undo');
      return;
    }
    notifier.undo();
  }

  void _redo(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorProvider.notifier);
    if (!notifier.canRedo) {
      _showSnack(context, 'Nothing to redo');
      return;
    }
    notifier.redo();
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Shows the shortcut reference the title bar's "Shortcuts" button opens.
void showEditorShortcutsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: const SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShortcutRow('Space', 'Play / pause'),
            _ShortcutRow('⌘/Ctrl + B, or S', 'Split clip at playhead'),
            _ShortcutRow('Delete / Backspace', 'Remove selected clip'),
            _ShortcutRow('Shift + Delete', 'Ripple-delete selected clip'),
            _ShortcutRow('⌘/Ctrl + D', 'Duplicate selected clip'),
            _ShortcutRow('⌘/Ctrl + Z', 'Undo'),
            _ShortcutRow('⌘/Ctrl + Shift + Z, or Ctrl/⌘ + Y', 'Redo'),
            _ShortcutRow('← / →', 'Nudge playhead 1 frame'),
            _ShortcutRow('Shift + ← / →', 'Seek 1 second'),
            _ShortcutRow('⌘/Ctrl + = (or +)', 'Zoom timeline in'),
            _ShortcutRow('⌘/Ctrl + -', 'Zoom timeline out'),
            _ShortcutRow('N', 'Toggle snapping'),
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
