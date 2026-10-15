import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/split_handle.dart';
import '../view_models/editor_ui_state.dart';
import 'browser_panel.dart';
import 'editor_shortcuts.dart';
import 'feature_rail.dart';
import 'inspector_panel.dart';
import 'player_panel.dart';
import 'timeline_panel.dart';
import 'timeline_toolbar.dart';
import 'title_bar.dart';

/// The editor shell, laid out like CapCut: a title bar on top; a left column
/// with the feature rail over its browser; the player in the centre; the
/// inspector on the right; and the timeline toolbar + timeline across the
/// bottom. The three dividers are draggable to resize the panels.
class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizes = ref.watch(panelsProvider);
    final panels = ref.read(panelsProvider.notifier);

    return Scaffold(
      body: EditorShortcuts(
        child: Column(
          children: [
            const EditorTitleBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: sizes.left,
                    child: Column(
                      children: const [
                        FeatureRail(),
                        Expanded(child: BrowserPanel()),
                      ],
                    ),
                  ),
                  SplitHandle(axis: Axis.vertical, onDrag: panels.dragLeft),
                  const Expanded(child: PlayerPanel()),
                  SplitHandle(axis: Axis.vertical, onDrag: panels.dragRight),
                  SizedBox(
                      width: sizes.right, child: const InspectorPanel()),
                ],
              ),
            ),
            SplitHandle(axis: Axis.horizontal, onDrag: panels.dragTimeline),
            const TimelineToolbar(),
            SizedBox(height: sizes.timeline, child: const TimelinePanel()),
          ],
        ),
      ),
    );
  }
}
