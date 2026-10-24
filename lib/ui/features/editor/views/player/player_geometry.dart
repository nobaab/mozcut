import 'dart:math' as math;
import 'dart:ui';

import '../../../../../domain/models/clip.dart';

/// Pure geometry/math for the real-time preview compositor and its transform
/// gizmo (docs/PLAYER-BEHAVIOR.md §2.2, §3, §5.1). Kept free of Flutter
/// widgets so every px↔normalized↔model conversion is unit-testable in
/// isolation.

/// The clip under the timeline playhead [t] (timeline seconds) plus that
/// clip's start offset on the timeline, or null if [clips] is empty. Mirrors
/// rea-capcut's `active`/`target` lookup adapted to our single-track concat
/// (spec §5.1). Past the end of the last clip it clamps to the last clip so the
/// monitor still shows a real frame instead of going black.
(Clip clip, double clipStart)? clipAt(double t, List<Clip> clips) {
  if (clips.isEmpty) return null;
  var acc = 0.0;
  for (final c in clips) {
    if (t >= acc && t < acc + c.duration) return (c, acc);
    acc += c.duration;
  }
  return (clips.last, acc - clips.last.duration);
}

/// The source time (seconds into [c.sourcePath]) that corresponds to timeline
/// time [t] for a clip starting at [clipStart] (spec §5.1):
/// `inPoint + (t - clipStart) * speed`.
double sourceTimeOf(Clip c, double clipStart, double t) =>
    c.inPoint + (t - clipStart) * c.speed;

// ── transform gizmo geometry (spec §3) ─────────────────────────────────────

/// Which part of the gizmo a pointer landed on.
enum GizmoHit { none, body, rotate, corner0, corner1, corner2, corner3 }

/// The on-screen geometry of the selection box, in letterboxed player pixels.
/// Built once per frame from the clip's transform; all hit-testing and handle
/// drawing reads from it so the two can never drift (concat's model, spec §3.2).
class GizmoGeometry {
  GizmoGeometry({
    required this.center,
    required this.hw,
    required this.hh,
    required this.rotationRad,
    this.stem = 28,
  });

  /// Box center in player px.
  final Offset center;

  /// Half-width / half-height in player px (before rotation).
  final double hw;
  final double hh;

  /// Rotation in radians, clockwise.
  final double rotationRad;

  /// Length of the rotate-handle stem above the top edge, in px.
  final double stem;

  /// Maps a local (unrotated, center-origin) point into player px using the
  /// same forward-rotate map concat uses (spec §3.2).
  Offset _toPlayer(double lx, double ly) {
    final c = math.cos(rotationRad), s = math.sin(rotationRad);
    return Offset(center.dx + lx * c - ly * s, center.dy + lx * s + ly * c);
  }

  /// Corner 0=TL, 1=TR, 2=BR, 3=BL in player px.
  Offset corner(int i) => switch (i) {
        0 => _toPlayer(-hw, -hh),
        1 => _toPlayer(hw, -hh),
        2 => _toPlayer(hw, hh),
        _ => _toPlayer(-hw, hh),
      };

  /// The rotate grip, on a stem above the top edge's center.
  Offset get rotateHandle => _toPlayer(0, -hh - stem);
}

/// Builds [GizmoGeometry] from model transform values and the letterboxed box
/// size (spec §3.2). `posX`/`posY` are the normalized center offsets (±1 = an
/// edge); the video fills the canvas at `scale == 1`, so half-extents are
/// `scale * displayW/2` and `scale * displayH/2`.
GizmoGeometry gizmoGeometry({
  required double scale,
  required double posX,
  required double posY,
  required double rotationDeg,
  required double displayW,
  required double displayH,
  double stem = 28,
}) {
  final cx = displayW / 2, cy = displayH / 2;
  return GizmoGeometry(
    center: Offset(cx + posX * cx, cy + posY * cy),
    hw: scale * cx,
    hh: scale * cy,
    rotationRad: rotationDeg * math.pi / 180,
    stem: stem,
  );
}

/// Which handle (if any) a pointer at [p] (player px) hits. Hit targets are a
/// few px larger than the drawn grips ("easier to find than it is to see" —
/// concat). Rotate and corners take priority over the body (spec §3.3).
GizmoHit gizmoHitTest(Offset p, GizmoGeometry g, {double grip = 16}) {
  if ((p - g.rotateHandle).distance <= grip) return GizmoHit.rotate;
  for (var i = 0; i < 4; i++) {
    if ((p - g.corner(i)).distance <= grip) {
      return GizmoHit.values[GizmoHit.corner0.index + i];
    }
  }
  // Transform the pointer into the box's local (unrotated) frame and test the
  // rectangle directly.
  final d = p - g.center;
  final c = math.cos(g.rotationRad), s = math.sin(g.rotationRad);
  final lx = d.dx * c + d.dy * s;
  final ly = -d.dx * s + d.dy * c;
  if (lx.abs() <= g.hw && ly.abs() <= g.hh) return GizmoHit.body;
  return GizmoHit.none;
}

/// Uniform scale from a corner drag: `scale0 * dist(cur,center)/dist(start,
/// center)`, clamped to [updateTransform]'s range (spec §3.3). MozCut scale is
/// uniform, so all four corners drive one factor.
double scaleFromDrag({
  required Offset center,
  required Offset start,
  required Offset current,
  required double startScale,
  double minScale = 0.05,
  double maxScale = 8.0,
}) {
  final d0 = (start - center).distance;
  if (d0 < 1e-6) return startScale;
  final d1 = (current - center).distance;
  return (startScale * d1 / d0).clamp(minScale, maxScale);
}

/// Rotation (degrees) from a rotate-handle drag: the change in pointer angle
/// about the center, added to the starting rotation (spec §3.3).
double rotationDegFromDrag({
  required Offset center,
  required Offset start,
  required Offset current,
  required double startDeg,
}) {
  final a0 = math.atan2(start.dy - center.dy, start.dx - center.dx);
  final a1 = math.atan2(current.dy - center.dy, current.dx - center.dx);
  return startDeg + (a1 - a0) * 180 / math.pi;
}

/// New (posX, posY) from a body drag: the pixel delta mapped back into
/// normalized units (`Δpx.x/cx`, `Δpx.y/cy`) and added to the starting
/// position, clamped to [updateTransform]'s range (spec §3.3).
(double posX, double posY) posFromDrag({
  required double startPosX,
  required double startPosY,
  required Offset deltaPx,
  required double displayW,
  required double displayH,
  double minPos = -2.0,
  double maxPos = 2.0,
}) {
  final cx = displayW / 2, cy = displayH / 2;
  return (
    (startPosX + deltaPx.dx / cx).clamp(minPos, maxPos),
    (startPosY + deltaPx.dy / cy).clamp(minPos, maxPos),
  );
}
