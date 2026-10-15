import 'package:flutter/material.dart';

/// A labelled icon button for the editor toolbar. Disabled when [onPressed] is
/// null, which is how the toolbar greys out actions with no selection.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      ),
    );
  }
}
