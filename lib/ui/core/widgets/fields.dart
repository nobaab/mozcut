import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';

/// A text input at the app's standard control height, with an optional leading
/// icon and hint. Use for search boxes and single-line text entry.
class VTextField extends StatelessWidget {
  const VTextField({
    super.key,
    this.controller,
    this.hint,
    this.icon,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.controlHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
          prefixIcon: icon == null ? null : Icon(icon, size: AppSpacing.iconSize),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          filled: true,
          fillColor: AppColors.well,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// A compact labelled numeric field (e.g. the inspector's X / Y / Rotate / fps).
/// A fixed height so rows of them align. Purely presentational — wire [onChanged]
/// and pass the current [value] as text.
class VNumberField extends StatelessWidget {
  const VNumberField({
    super.key,
    required this.value,
    this.prefix,
    this.suffix,
    this.controller,
    this.onChanged,
    this.width,
  });

  final String value;
  final String? prefix;
  final String? suffix;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final editable = controller != null || onChanged != null;
    return SizedBox(
      width: width,
      height: AppSpacing.controlHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.well,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            if (prefix != null)
              Text('$prefix ',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4))),
            Expanded(
              child: editable
                  ? TextField(
                      controller: controller,
                      onChanged: onChanged,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                      ),
                    )
                  : Text(value, style: const TextStyle(fontSize: 12)),
            ),
            if (suffix != null)
              Text(suffix!,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }
}
