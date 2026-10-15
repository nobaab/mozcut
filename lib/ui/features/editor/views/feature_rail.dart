import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../view_models/editor_ui_state.dart';

/// The row of feature tabs down the top-left — Import, Audio, Text, Stickers,
/// Effects, Transitions, Captions, Filters, … — exactly CapCut's rail. Picking
/// one changes the browser panel below it.
class FeatureRail extends ConsumerWidget {
  const FeatureRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(leftTabProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            for (final tab in EditorLeftTab.values)
              _RailItem(
                tab: tab,
                active: tab == active,
                onTap: () => ref.read(leftTabProvider.notifier).set(tab),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem(
      {required this.tab, required this.active, required this.onTap});

  final EditorLeftTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : Colors.white.withValues(alpha: 0.7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(tab.label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
