import 'package:flutter/material.dart';

import '../app_colors.dart';

/// A draggable divider between two panels. [axis] is the line's direction:
/// `Axis.vertical` draws a vertical line you drag left/right (resizing panels
/// side by side); `Axis.horizontal` draws a horizontal line you drag up/down.
/// [onDrag] receives the pointer delta along the resize direction.
class SplitHandle extends StatefulWidget {
  const SplitHandle({super.key, required this.axis, required this.onDrag});

  final Axis axis;
  final ValueChanged<double> onDrag;

  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    final line = Container(
      width: vertical ? 1 : double.infinity,
      height: vertical ? double.infinity : 1,
      color: _hover ? AppColors.accent : AppColors.line,
    );

    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate:
            vertical ? (d) => widget.onDrag(d.delta.dx) : null,
        onVerticalDragUpdate:
            vertical ? null : (d) => widget.onDrag(d.delta.dy),
        child: SizedBox(
          width: vertical ? 8 : double.infinity,
          height: vertical ? double.infinity : 8,
          child: Center(child: line),
        ),
      ),
    );
  }
}
