import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import 'browser_panel.dart';
import 'feature_rail.dart';
import 'inspector_panel.dart';
import 'player_panel.dart';
import 'timeline_panel.dart';
import 'timeline_toolbar.dart';
import 'title_bar.dart';

/// The editor shell, laid out like CapCut: a title bar on top; a left column
/// with the feature rail over its browser; the player in the centre; the
/// inspector on the right; and the timeline toolbar + timeline across the
/// bottom.
class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  static const _leftWidth = 380.0;
  static const _rightWidth = 300.0;
  static const _timelineHeight = 220.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: const [
          EditorTitleBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _leftWidth,
                  child: Column(
                    children: [
                      FeatureRail(),
                      Expanded(child: BrowserPanel()),
                    ],
                  ),
                ),
                _VDivider(),
                Expanded(child: PlayerPanel()),
                _VDivider(),
                SizedBox(width: _rightWidth, child: InspectorPanel()),
              ],
            ),
          ),
          TimelineToolbar(),
          SizedBox(height: _timelineHeight, child: TimelinePanel()),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: AppColors.line);
}
