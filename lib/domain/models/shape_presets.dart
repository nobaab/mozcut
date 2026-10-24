/// The Stickers panel's built-in "Shapes" catalogue: a handful of plain,
/// ORIGINAL geometric outlines — never a copyrighted character, logo or
/// piece of art — rendered on demand as transparent PNGs by ffmpeg (`color`
/// as a zero-input transparent source, then `drawbox`/`geq` to paint the
/// outline), the same on-demand-and-cache approach [kSfxPresets] uses for
/// built-in sound effects. See `FfmpegEngine.generateShape`.
///
/// Kept as plain data + a pure [ShapePreset.buildArgs] method (no `Process`
/// calls here) so the id -> ffmpeg-command mapping can be unit tested without
/// a real ffmpeg binary — see test/shape_presets_test.dart.
///
/// Every shape is drawn white-on-transparent at a fixed [kShapeCanvasSize]
/// square canvas; `StickerOverlay.size`/`x`/`y` (the same fields an imported
/// image sticker uses) then scale/place it like any other image sticker.
library;

/// The square canvas (in pixels) every generated shape PNG is rendered at.
/// Square is simplest — `StickerOverlay.size` is a fraction of the output
/// frame's *height*, and ffmpeg's `overlay` preserves this PNG's own aspect
/// ratio when scaling it, so a non-square shape (the arrow, the speech
/// bubble) still renders correctly even though its canvas is square: the
/// shape just doesn't fill every edge of that square.
const kShapeCanvasSize = 512;

/// One built-in generated shape.
class ShapePreset {
  const ShapePreset({
    required this.id,
    required this.label,
    required this.vfFilter,
  });

  /// Stable lookup key, also used as the cached output file's name (see
  /// `FfmpegEngine.generateShape`) — e.g. `circle` -> `shape_circle.png`.
  final String id;

  /// Display name shown in the Stickers panel's Shapes grid.
  final String label;

  /// The ffmpeg `-vf` filter chain that paints this shape, white-on-
  /// transparent, onto the zero-input `color=c=black@0.0:...` source
  /// [buildArgs] feeds it. Every shape uses `format=rgba` first so the
  /// alpha channel this relies on actually exists, then either `drawbox`
  /// (the rectangle) or `geq` (everything else — `geq`'s per-pixel
  /// expressions are how a circle/triangle/ellipse outline gets drawn
  /// without a vector-graphics dependency: `st`/`ld` are ffmpeg's eval-API
  /// scratch registers, limited to indices 0-9, which is why every
  /// expression below stays inside that range).
  final String vfFilter;

  /// The full ffmpeg argv that renders this preset to [outputPath] as a
  /// [kShapeCanvasSize]-square transparent PNG. Pure and deterministic —
  /// spawns nothing; the caller runs the process.
  List<String> buildArgs(String outputPath) => [
        '-y',
        '-f', 'lavfi',
        '-i',
        'color=c=black@0.0:s=${kShapeCanvasSize}x$kShapeCanvasSize:d=1',
        '-vf', vfFilter,
        '-frames:v', '1',
        '-update', '1',
        outputPath,
      ];
}

/// The full built-in catalogue, in the order the Stickers panel's Shapes grid
/// shows them. Every [ShapePreset.id] here must be unique — see
/// test/shape_presets_test.dart.
///
/// Geometry notes (all on a 512x512 canvas):
/// - `rectangle`: a 400x400 outline inset 56px, 16px thick — plain `drawbox`.
/// - `circle`: a ring of radius 200, 16px thick, via `hypot` distance-from-
///   center.
/// - `arrow`: a shaft rectangle (a plain in-range test, `gte`/`lte`) plus a
///   solid triangular head (a standard "same sign on all three edges"
///   point-in-triangle test) pointing right.
/// - `speech_bubble`: an ellipse outline (normalized-distance test) with a
///   small solid triangular tail at the bottom — same point-in-triangle test
///   as the arrow head, different vertices.
const kShapePresets = <ShapePreset>[
  ShapePreset(
    id: 'rectangle',
    label: 'Rectangle',
    vfFilter: 'format=rgba,'
        'drawbox=x=56:y=56:w=400:h=400:color=white@1.0:t=16',
  ),
  ShapePreset(
    id: 'circle',
    label: 'Circle',
    vfFilter: 'format=rgba,'
        "geq=r=255:g=255:b=255:"
        "a='if(lt(abs(hypot(X-256,Y-256)-200),16),255,0)'",
  ),
  ShapePreset(
    id: 'arrow',
    label: 'Arrow',
    vfFilter: 'format=rgba,'
        "geq=r=255:g=255:b=255:a='"
        'st(0,(X-260)*(166-346)-(260-260)*(Y-346));'
        'st(1,(X-452)*(346-256)-(260-452)*(Y-256));'
        'st(2,(X-260)*(256-166)-(452-260)*(Y-166));'
        'st(3,max(lt(ld(0),0),max(lt(ld(1),0),lt(ld(2),0))));'
        'st(4,max(gt(ld(0),0),max(gt(ld(1),0),gt(ld(2),0))));'
        'st(5,gte(X,60)*lte(X,280)*gte(Y,226)*lte(Y,286));'
        "if(eq(ld(3)*ld(4),0),255,if(eq(ld(5),1),255,0))'",
  ),
  ShapePreset(
    id: 'speech_bubble',
    label: 'Speech bubble',
    vfFilter: 'format=rgba,'
        "geq=r=255:g=255:b=255:a='"
        'st(0,((X-256)/200)*((X-256)/200)+((Y-220)/150)*((Y-220)/150));'
        'st(1,(X-180)*(380-460)-(160-180)*(Y-460));'
        'st(2,(X-260)*(460-380)-(180-260)*(Y-380));'
        'st(3,(X-160)*(380-380)-(260-160)*(Y-380));'
        'st(4,max(lt(ld(1),0),max(lt(ld(2),0),lt(ld(3),0))));'
        'st(5,max(gt(ld(1),0),max(gt(ld(2),0),gt(ld(3),0))));'
        "max(if(lt(abs(ld(0)-1),0.08),255,0),"
        "if(eq(ld(4)*ld(5),0),255,0))'",
  ),
];
