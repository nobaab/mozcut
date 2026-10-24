import 'package:flutter/material.dart';

import '../../../../core/app_colors.dart';
import 'player_geometry.dart';

/// Values written back by a gizmo drag. Only the fields the active handle
/// changes are non-null.
class GizmoTransform {
  const GizmoTransform({this.scale, this.posX, this.posY, this.rotation});
  final double? scale;
  final double? posX;
  final double? posY;
  final double? rotation;
}

/// The interactive transform gizmo for the selected clip (spec §3): a rotated
/// bounding box with 4 corner grips (uniform scale), a rotate handle on a stem
/// above the top edge, and body-drag to move. Geometry is fraction/normalized
/// (via [gizmoGeometry]); grips are axis-aligned squares placed at the rotated
/// corners; pointer mapping is absolute (computed from the press origin each
/// move) so a drag against the moving box doesn't drift — concat's model.
///
/// The draw values ([scale]/[posX]/[posY]/[rotationDeg]) are supplied by the
/// parent, which also owns the in-progress preview: [onPreview] fires every
/// move with the new value(s) and [onCommit] fires once on pointer-up, which is
/// where the parent calls `Editor.updateTransform` (a single undo step).
class GizmoLayer extends StatefulWidget {
  const GizmoLayer({
    super.key,
    required this.scale,
    required this.posX,
    required this.posY,
    required this.rotationDeg,
    required this.displayW,
    required this.displayH,
    required this.onPreview,
    required this.onCommit,
  });

  final double scale;
  final double posX;
  final double posY;
  final double rotationDeg;
  final double displayW;
  final double displayH;
  final void Function(GizmoTransform) onPreview;
  final void Function(GizmoTransform) onCommit;

  @override
  State<GizmoLayer> createState() => _GizmoLayerState();
}

class _GizmoLayerState extends State<GizmoLayer> {
  GizmoHit _mode = GizmoHit.none;
  late Offset _startPointer;
  late double _startScale, _startPosX, _startPosY, _startRot;
  GizmoTransform? _last;

  GizmoGeometry get _geometry => gizmoGeometry(
        scale: widget.scale,
        posX: widget.posX,
        posY: widget.posY,
        rotationDeg: widget.rotationDeg,
        displayW: widget.displayW,
        displayH: widget.displayH,
      );

  void _onStart(DragStartDetails d) {
    final g = _geometry;
    _mode = gizmoHitTest(d.localPosition, g);
    _startPointer = d.localPosition;
    _startScale = widget.scale;
    _startPosX = widget.posX;
    _startPosY = widget.posY;
    _startRot = widget.rotationDeg;
    _last = null;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_mode == GizmoHit.none) return;
    // The center is fixed for scale/rotate (it only moves on a body drag), so
    // recompute it from the *start* transform for those modes.
    final startGeo = gizmoGeometry(
      scale: _startScale,
      posX: _startPosX,
      posY: _startPosY,
      rotationDeg: _startRot,
      displayW: widget.displayW,
      displayH: widget.displayH,
    );
    final p = d.localPosition;
    final GizmoTransform t;
    switch (_mode) {
      case GizmoHit.body:
        final (nx, ny) = posFromDrag(
          startPosX: _startPosX,
          startPosY: _startPosY,
          deltaPx: p - _startPointer,
          displayW: widget.displayW,
          displayH: widget.displayH,
        );
        t = GizmoTransform(posX: nx, posY: ny);
      case GizmoHit.rotate:
        t = GizmoTransform(
          rotation: rotationDegFromDrag(
            center: startGeo.center,
            start: _startPointer,
            current: p,
            startDeg: _startRot,
          ),
        );
      case GizmoHit.corner0:
      case GizmoHit.corner1:
      case GizmoHit.corner2:
      case GizmoHit.corner3:
        t = GizmoTransform(
          scale: scaleFromDrag(
            center: startGeo.center,
            start: _startPointer,
            current: p,
            startScale: _startScale,
          ),
        );
      case GizmoHit.none:
        return;
    }
    _last = t;
    widget.onPreview(t);
  }

  void _onEnd(DragEndDetails d) {
    if (_mode != GizmoHit.none && _last != null) widget.onCommit(_last!);
    _mode = GizmoHit.none;
    _last = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onStart,
      onPanUpdate: _onUpdate,
      onPanEnd: _onEnd,
      child: CustomPaint(
        size: Size(widget.displayW, widget.displayH),
        painter: _GizmoPainter(_geometry),
      ),
    );
  }
}

class _GizmoPainter extends CustomPainter {
  _GizmoPainter(this.g);
  final GizmoGeometry g;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..color = Colors.white;
    final gripStroke = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final corners = [for (var i = 0; i < 4; i++) g.corner(i)];

    // Bounding outline.
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(path, line);

    // Rotate stem + handle.
    final topMid = Offset(
      (corners[0].dx + corners[1].dx) / 2,
      (corners[0].dy + corners[1].dy) / 2,
    );
    canvas.drawLine(topMid, g.rotateHandle, line);
    canvas.drawCircle(g.rotateHandle, 6, fill);
    canvas.drawCircle(g.rotateHandle, 6, gripStroke);

    // Corner grips.
    for (final c in corners) {
      final rect = Rect.fromCenter(center: c, width: 12, height: 12);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, gripStroke);
    }
  }

  @override
  bool shouldRepaint(_GizmoPainter old) =>
      old.g.center != g.center ||
      old.g.hw != g.hw ||
      old.g.hh != g.hh ||
      old.g.rotationRad != g.rotationRad;
}
