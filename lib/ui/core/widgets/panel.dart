import 'package:flutter/material.dart';

import '../app_colors.dart';

/// A titled panel: a small header strip with an optional trailing widget, and a
/// body below. The building block of the editor's docked look (media bin,
/// inspector, timeline), so every panel wears the same header and surface.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padBody = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(padBody ? 10 : 0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
