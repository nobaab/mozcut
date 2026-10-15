import 'package:flutter/material.dart';

/// A collapsible section header (Transform, Blend, Source…) with an optional
/// checkbox and trailing widget. One style for every inspector section.
class VSectionHeader extends StatelessWidget {
  const VSectionHeader(
    this.title, {
    super.key,
    this.hasCheckbox = false,
    this.checked = true,
    this.onChecked,
    this.trailing,
  });

  final String title;
  final bool hasCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          if (hasCheckbox)
            SizedBox(
              width: 22,
              child: Checkbox(value: checked, onChanged: onChecked),
            ),
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// A label + value/control row with a fixed label column, so every property
/// row in the inspector lines its values up on the same x.
class VPropertyRow extends StatelessWidget {
  const VPropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 72,
  });

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5))),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
