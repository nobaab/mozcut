import 'package:flutter_test/flutter_test.dart';
import 'package:mozcut/domain/models/clip.dart';
import 'package:mozcut/ui/features/editor/views/player/player_geometry.dart';

/// Covers the pure compositor/gizmo math (docs/PLAYER-BEHAVIOR.md §3, §5.1):
/// the clip-at-playhead lookup, the source-time mapping, and the three-way
/// px↔normalized↔model conversions the transform gizmo relies on. No widgets or
/// media engine involved.
void main() {
  group('clipAt / sourceTimeOf (spec §5.1)', () {
    final clips = [
      Clip(sourcePath: '/a.mp4', sourceDuration: 10), // timeline [0, 10)
      Clip(sourcePath: '/b.mp4', sourceDuration: 10), // timeline [10, 20)
      Clip(sourcePath: '/c.mp4', sourceDuration: 10), // timeline [20, 30)
    ];

    test('returns null for an empty timeline', () {
      expect(clipAt(0, const []), isNull);
    });

    test('finds the clip spanning the playhead and its start offset', () {
      expect(clipAt(0, clips)!.$1.sourcePath, '/a.mp4');
      expect(clipAt(0, clips)!.$2, 0);

      expect(clipAt(5, clips)!.$1.sourcePath, '/a.mp4');
      expect(clipAt(12, clips)!.$1.sourcePath, '/b.mp4');
      expect(clipAt(12, clips)!.$2, 10);
      expect(clipAt(25, clips)!.$1.sourcePath, '/c.mp4');
      expect(clipAt(25, clips)!.$2, 20);
    });

    test('a boundary belongs to the clip that starts there', () {
      // t == 10 is the first instant of clip b (half-open [start, start+dur)).
      expect(clipAt(10, clips)!.$1.sourcePath, '/b.mp4');
      expect(clipAt(20, clips)!.$1.sourcePath, '/c.mp4');
    });

    test('past the end clamps to the last clip (never black)', () {
      final hit = clipAt(999, clips)!;
      expect(hit.$1.sourcePath, '/c.mp4');
      expect(hit.$2, 20);
    });

    test('sourceTime = inPoint + (t - clipStart) * speed', () {
      final c = Clip(sourcePath: '/a.mp4', sourceDuration: 20, inPoint: 2);
      // clip starts at timeline 4, playhead at 7 → 3s into the clip.
      expect(sourceTimeOf(c, 4, 7), closeTo(2 + 3, 1e-9));

      final fast = Clip(
          sourcePath: '/a.mp4', sourceDuration: 20, inPoint: 1, speed: 2.0);
      // 3 timeline seconds into a 2x clip = 6 source seconds.
      expect(sourceTimeOf(fast, 0, 3), closeTo(1 + 6, 1e-9));
    });

    test('duration accounts for speed, so clipAt crosses at the sped-up edge',
        () {
      final sped = [
        Clip(sourcePath: '/a.mp4', sourceDuration: 10, speed: 2.0), // dur 5
        Clip(sourcePath: '/b.mp4', sourceDuration: 10), // starts at 5
      ];
      expect(clipAt(4, sped)!.$1.sourcePath, '/a.mp4');
      expect(clipAt(5, sped)!.$1.sourcePath, '/b.mp4');
    });
  });

  group('gizmo geometry & conversions (spec §3.2)', () {
    const dW = 400.0, dH = 200.0; // cx=200, cy=100

    test('identity transform: box fills the canvas, centered', () {
      final g = gizmoGeometry(
          scale: 1, posX: 0, posY: 0, rotationDeg: 0, displayW: dW, displayH: dH);
      expect(g.center, const Offset(200, 100));
      expect(g.hw, 200);
      expect(g.hh, 100);
      // Corners at the canvas edges.
      expect(g.corner(0), const Offset(0, 0)); // TL
      expect(g.corner(2), const Offset(400, 200)); // BR
    });

    test('posX/posY offset the center by a fraction of the half-size', () {
      final g = gizmoGeometry(
          scale: 1,
          posX: 0.5,
          posY: -1,
          rotationDeg: 0,
          displayW: dW,
          displayH: dH);
      // center = (cx + posX*cx, cy + posY*cy) = (200+100, 100-100)
      expect(g.center, const Offset(300, 0));
    });

    test('hitTest: center is body, a corner is its grip, the stem is rotate',
        () {
      final g = gizmoGeometry(
          scale: 0.5,
          posX: 0,
          posY: 0,
          rotationDeg: 0,
          displayW: dW,
          displayH: dH);
      expect(gizmoHitTest(g.center, g), GizmoHit.body);
      expect(gizmoHitTest(g.corner(1), g), GizmoHit.corner1);
      expect(gizmoHitTest(g.rotateHandle, g), GizmoHit.rotate);
      expect(gizmoHitTest(const Offset(-100, -100), g), GizmoHit.none);
    });

    test('scaleFromDrag scales by the pointer-distance ratio', () {
      final center = const Offset(200, 100);
      final start = const Offset(300, 100); // distance 100
      final current = const Offset(400, 100); // distance 200
      expect(
        scaleFromDrag(
            center: center, start: start, current: current, startScale: 1),
        closeTo(2.0, 1e-9),
      );
    });

    test('scaleFromDrag clamps to the model range', () {
      final center = Offset.zero;
      expect(
        scaleFromDrag(
            center: center,
            start: const Offset(100, 0),
            current: const Offset(10000, 0),
            startScale: 1),
        8.0,
      );
    });

    test('rotationDegFromDrag adds the swept angle to the start rotation', () {
      final center = const Offset(0, 0);
      // start pointing right (0°), drag to pointing down (+90° clockwise in
      // screen coords where y grows downward).
      expect(
        rotationDegFromDrag(
            center: center,
            start: const Offset(100, 0),
            current: const Offset(0, 100),
            startDeg: 10),
        closeTo(100, 1e-6),
      );
    });

    test('posFromDrag maps a pixel delta back to normalized units', () {
      // cx=200, cy=100 → a +100px x drag = +0.5 posX; +50px y = +0.5 posY.
      final (nx, ny) = posFromDrag(
        startPosX: 0,
        startPosY: 0,
        deltaPx: const Offset(100, 50),
        displayW: dW,
        displayH: dH,
      );
      expect(nx, closeTo(0.5, 1e-9));
      expect(ny, closeTo(0.5, 1e-9));
    });

    test('posFromDrag clamps to the model range', () {
      final (nx, ny) = posFromDrag(
        startPosX: 0,
        startPosY: 0,
        deltaPx: const Offset(100000, -100000),
        displayW: dW,
        displayH: dH,
      );
      expect(nx, 2.0);
      expect(ny, -2.0);
    });
  });
}
