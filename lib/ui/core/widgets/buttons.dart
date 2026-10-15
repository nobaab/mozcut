import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';

/// Button styles across the app. One place so every button is the same height
/// and shape.
enum VButtonVariant {
  /// Filled with the accent — the one primary action on a surface.
  primary,

  /// Outlined / subtle fill — secondary actions.
  secondary,

  /// No background until hover — toolbar-style actions.
  ghost,
}

/// The app's button. Always [AppSpacing.controlHeight] tall, optional leading
/// icon, consistent padding. Disabled when [onPressed] is null.
class VButton extends StatelessWidget {
  const VButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = VButtonVariant.secondary,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final VButtonVariant variant;

  /// Fill the available width (for forms / full-width actions).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppSpacing.iconSize),
          const SizedBox(width: 6),
        ],
        Text(label),
      ],
    );

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
          Size(expand ? double.infinity : 0, AppSpacing.controlHeight)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14)),
      textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm))),
    );

    switch (variant) {
      case VButtonVariant.primary:
        return FilledButton(
          onPressed: onPressed,
          style: style.copyWith(
            backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
          ),
          child: child,
        );
      case VButtonVariant.secondary:
        return OutlinedButton(
          onPressed: onPressed,
          style: style.copyWith(
            side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.line)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          child: child,
        );
      case VButtonVariant.ghost:
        return TextButton(
          onPressed: onPressed,
          style: style.copyWith(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          child: child,
        );
    }
  }
}

/// A square icon button at a single, consistent size, with a tooltip and a
/// hover highlight. Use everywhere an icon is the whole control (toolbars,
/// panel headers, player controls).
class VIconButton extends StatelessWidget {
  const VIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Tints the glyph with the accent (e.g. a toggled-on tool).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: AppSpacing.iconSize),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppSpacing.iconButtonSize,
        minHeight: AppSpacing.iconButtonSize,
      ),
      color: active ? AppColors.accent : Colors.white,
    );
  }
}
