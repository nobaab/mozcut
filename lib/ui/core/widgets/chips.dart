import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';

/// A selectable pill — tabs, sub-tabs, presets, filter chips. One consistent
/// height and shape so rows of them line up everywhere.
class VChip extends StatelessWidget {
  const VChip({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.18)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.controlHeight / 2),
        side: BorderSide(
            color: selected ? AppColors.accent : AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.controlHeight / 2),
        child: Container(
          height: AppSpacing.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 15,
                    color: selected ? AppColors.accent : Colors.white70),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.accent : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
