# PLAYER / PREVIEW behaviour — implementation spec

How CapCut-style editors render the program monitor, and how MozCut should
match them. Written against two references on disk and our current code.

- **rea-capcut** (Electron/React/TS — the closest model to ours):
  `rea-capcut/src/components/Player.tsx`, `rea-capcut/src/editor/previewLayers.ts`.
- **concat** (Rust/Slint — secondary, but has the best transform gizmo):
  `concat/src/crates/concat/ui/workspace/preview-pane.slint`.
- **MozCut today**: `lib/ui/features/editor/views/player_panel.dart`,
  `lib/data/engine/ffmpeg_engine.dart`, `lib/domain/models/clip.dart`.

> **Bottom line:** both references render the preview by **real-time
> compositing** — a live media element at the playhead, transformed and
> layered in the view, letterboxed to the project aspect. Neither renders an
> ffmpeg proxy of the whole timeline the way MozCut does. MozCut should switch
> to real-time compositing and keep the ffmpeg proxy only as an optional,
> explicit "accurate preview" fallback.

---

## 1. How the references render the preview

### 1.1 rea-capcut — a `requestAnimationFrame` canvas compositor

There is **no proxy render**. The player keeps one live media element per clip
and paints the current frame to a 2D canvas every animation frame.

| Concern | Mechanism | Evidence |
|---|---|---|
| One decoder per clip | `sources: Map<clipId, {element, url, …}>`; each clip gets its own `<video>`/`<audio>`/`Image` created on demand | `Player.tsx:54`, `:83–150` |
| The paint loop | `requestAnimationFrame(paint)` runs forever; advances `playhead` by real elapsed time when `playing` | `Player.tsx:185–340` |
| Canvas = project pixels | canvas sized to project w/h·DPR; `ctx.setTransform(factor,…)` where `factor = canvas.width/p.width` | `Player.tsx:214–215`, `:356–363` |
| Letterbox to aspect | display box = `min(size.w, size.h*aspect)` then `/aspect`; canvas drawn at that CSS size | `Player.tsx:341–343` |
| Pick clips at playhead | reverse tracks, filter `clips` by `trackId`, sort by `start`; `active = t≥start && t<start+duration` | `Player.tsx:220–230` |
| Seek the raw clip | `media.currentTime = clip.sourceIn + local*clip.speed` (local = `t-clip.start`); only reseeks if off by >0.15 s playing / ~0 paused | `Player.tsx:247–258` |
| Apply transform | `translate(w/2 + tr.x, h/2 + tr.y) · rotate(deg) · scale(scale·flipX, scale·flipY)` then `drawImage` centered | `Player.tsx:284–328` |
| Opacity | `ctx.globalAlpha = transform.opacity · fade` | `Player.tsx:273`, `:285` |
| Text layer | `textPreviewLayer(clip)` renders the caption to an offscreen canvas, then `drawImage` | `Player.tsx:294–302`, `previewLayers.ts:104–173` |
| Color / crop / chroma / blur | pixel ops in `imagePreviewLayer` + `adjust()` (getImageData → applyColorAdjustments/chromaKey/mask); blur via `ctx.filter="blur()"` | `previewLayers.ts:39–102`, `Player.tsx:293` |
| Audio | WebAudio `GainNode` per clip; gain = `volume·fade`, muted when track/clip muted or inactive | `Player.tsx:169–184`, `:260–270` |

Key consequence: the preview is **instant and always shows the current frame**
because it is just the raw decoder seeked to the right source time, drawn with a
2D transform. Color/chroma/blur are *approximated on the canvas*, not run
through the export filtergraph.

### 1.2 rea-capcut — in-player editing is **move-only**

The player supports **drag-to-move** of the single selected clip, and nothing
else. Scale/rotation are edited in the Inspector, not in the monitor.

- `onPointerDown` on the canvas: only if exactly one clip selected, it is under
  the playhead, and its track is unlocked; captures the pointer, pauses
  playback, stores `drag = {x,y,dx,dy,clip}`. `Player.tsx:365–384`
- `onPointerMove`: `ratio = project.width/displayW; dx = (clientX-startX)·ratio`
  — i.e. screen px → **project px**. Live preview adds `dx/dy` to the transform
  during paint. `Player.tsx:385–391`, `:276–283`
- `onPointerUp`: if moved >2 px, `onUpdateClip(id, { transform: { x:+dx, y:+dy }, … })`
  and shifts any `x`/`y` keyframes by the same delta. `Player.tsx:395–429`

### 1.3 concat — the complete transform gizmo (Rust/Slint)

concat is the better reference for the **gizmo** (handles), even though its
compositor is a native GPU pane fed by Rust. The selection overlay lives in
`preview-pane.slint`:

- Geometry is **fractions of the frame** all the way from Rust, converted to
  pixels once in the view — "the same item draws correctly on a monitor of any
  size; only here does it meet pixels." `preview-pane.slint:214–216`, `:304–308`
- A selected item (`StageItem`) draws: a rotated outline, **4 corner grips**
  (scale), **4 edge grips** (stretch one axis), a **rotation handle** on a stem
  above the top edge, and a live `"<scale>% · <rotation>°"` readout.
  `preview-pane.slint:296–462`
- Grips are **separate, axis-aligned squares placed at the rotated corner
  points** (not children of the rotated box) so each can be an exact hit
  target: forward-rotate map `px(lx,ly)=cx+lx·cos−ly·sin`, `py=cy+lx·sin+ly·cos`.
  `preview-pane.slint:318–327`, `:374–461`
- Grips are numbered 0–3 corners, 4 rotate, 5–8 edges (TRBL); masks reuse the
  same component from 20. Each reports an **absolute** pointer position in
  frame fractions (`px()=(x+mouseX)/stageW`), not a delta, so a drag against a
  moving echo doesn't cancel itself. `preview-pane.slint:263–293`, `:375–461`
- Hit target is a few px larger than the drawn grip ("easier to find than it is
  to see"). `preview-pane.slint:251–257`

Takeaway for MozCut: **adopt concat's gizmo model** (fraction-based geometry,
axis-aligned grips placed at rotated corners, absolute pointer → fraction) and
**rea-capcut's compositor model** (one live decoder, seek-per-frame, draw with
a 2D transform, letterbox to aspect).

---

## 2. Real-time-compositing architecture for MozCut

Replace "render the whole timeline to an ffmpeg proxy and play that"
(`player_panel.dart:257–300`, `_renderPreviewNow`) with a live composite.

### 2.1 Widget tree (inside the existing `AspectRatio` letterbox)

```
Center
 └ AspectRatio(aspectRatio: canvas.w/canvas.h)          // already exists :199
    └ LayoutBuilder  (gives displayW × displayH in px)
       └ Stack
          ├ ColoredBox(black)                            // canvas background
          ├ _VideoLayer   — the Video widget, wrapped in Transform (base clip)
          ├ _OverlayLayer — PiP video overlays (VideoOverlay)      [Positioned]
          ├ _StickerLayer — emoji / image stickers active now      [Positioned]
          ├ _TextLayer    — text overlays active now               [Positioned]
          └ _GizmoLayer   — bounding box + handles for the selection
```

- Keep the **one** `media_kit` `Player`/`VideoController` we already have
  (`player_panel.dart:51–52`). It shows the **clip currently under the
  playhead's raw source** — not a proxy. See §5 for open/seek.
- The `AspectRatio` + `Center` + black `Container` already letterbox correctly
  (`player_panel.dart:179–212`); the canvas-normalized layers sit on top of it.
- `InteractiveViewer` zoom (`_zoom`) stays, but the gizmo must read its matrix
  so hit-testing works while zoomed (or disable gizmo interaction while zoomed > 1).

### 2.2 The base video layer (apply the clip's own transform)

The selected/active clip's `scale/posX/posY/rotation/flipH/opacity` are applied
to the `Video` widget itself, in **canvas-normalized** space:

```dart
// displayW, displayH = letterboxed player box in px (from LayoutBuilder).
// Clip fields are evaluated at the playhead via clip.valueAt(prop, clipT)
// so keyframed transforms animate live (clip.dart:357).
final s   = clip.valueAt(kKeyframeScale, t);
final px  = clip.valueAt(kKeyframePosX,  t) * displayW / 2;   // posX:±1 = half-width
final py  = clip.valueAt(kKeyframePosY,  t) * displayH / 2;
final rot = clip.valueAt(kKeyframeRotation, t) * math.pi / 180;
final op  = clip.valueAt(kKeyframeOpacity, t);

Opacity(opacity: op,
  child: Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..translate(px, py)
      ..rotateZ(rot)
      ..scale(s * (clip.flipH ? -1 : 1), s),   // flipH mirrors X
    child: Video(controller: _controller, controls: NoVideoControls),
  ));
```

This mirrors rea-capcut's `translate(w/2+x,y)·rotate·scale(±flip)` exactly
(`Player.tsx:286–291`), but in MozCut's normalized units. The `Video` widget
itself is already "contain"-fit to the canvas by the `AspectRatio`; `scale=1`
= fit, matching `Clip.scale` semantics (`clip.dart:162`).

### 2.3 What this buys us

- **Instant** preview, always a real frame — kills the "black until a proxy
  decodes" problem (see §7).
- Transform / position / opacity / text / stickers / PiP reflect edits with
  zero render latency (just a `setState`/rebuild).
- The `_timelineSignature` debounce/coalesce machinery
  (`player_panel.dart:220–300`) is no longer needed for transform/overlay
  edits — delete it from the hot path (keep only for the optional proxy, §6).

---

## 3. Interactive transform gizmo spec

A `_GizmoLayer` drawn in the `Stack` over the video, active when a clip (or an
overlay) is selected and the playhead is within its span. Model: concat's
(§1.3) — fraction geometry, axis-aligned grips at rotated corners.

### 3.1 Coordinate spaces and the three-way conversion

| Space | Units | Who uses it |
|---|---|---|
| **player px** | `0..displayW`, `0..displayH` (letterboxed box) | pointer events |
| **canvas-normalized** | center-origin; x,y ∈ `[-1,1]` at the canvas edges | the math layer |
| **model fields** | `Clip.posX/posY` (±1 = half-width), `scale`, `rotation°` | what we write |

Conversions (let `cx=displayW/2`, `cy=displayH/2`):

```
player→norm:   nx = (pxX - cx) / cx ;  ny = (pxY - cy) / cy
norm→player:   pxX = cx + nx*cx    ;  pxY = cy + ny*cy
```

`Clip.posX` **is** the normalized x of the clip center already (because
`posX·displayW/2` is the pixel offset of center from canvas center — §2.2). So
**`posX == nx_center`, `posY == ny_center`** directly. No extra scaling.

### 3.2 Bounding box

The clip's on-screen box = the letterboxed video (full `displayW×displayH` at
`scale=1`) scaled by `scale`, offset by `(posX·cx, posY·cy)`, rotated by
`rotation`. Center in player px: `(cx + posX·cx, cy + posY·cy)`. Half-extents:
`hw = scale·cx`, `hh = scale·cy` (video fills the canvas at scale 1). Corner
points via the same forward-rotate map concat uses:

```
corner(lx,ly) = center + ( lx·cosθ − ly·sinθ , lx·sinθ + ly·cosθ )   // θ = rotation
```

### 3.3 Handles → model fields

| Handle | Hit zone | Gesture math | Writes (via `Editor.updateTransform`) |
|---|---|---|---|
| **Body** (inside box) | box interior | `dnx = Δpx.x/cx`, `dny = Δpx.y/cy`; new `posX = posX₀+dnx`, `posY = posY₀+dny` | `posX`, `posY` |
| **4 corner grips** | ~12 px square at each rotated corner | `scale = scale₀ · dist(pointer,center) / dist(grip₀,center)` (uniform — see note) | `scale` |
| **Rotate handle** | round grip on a stem above top edge | `rotation = atan2(pointer−center) − atan2(grip₀−center) + rotation₀`, in degrees | `rotation` |
| **4 edge grips** *(optional)* | mid-edge squares | one-axis stretch — **but MozCut scale is uniform**, so either map to uniform `scale` or omit | `scale` (or omit) |

Notes
- **Uniform scale only.** The inspector states scale is a single factor, no
  separate X/Y (`inspector_panel.dart:137–139`, "Uniform scale"). So corner
  grips drive one `scale`; edge grips are best **omitted** (or mapped to the
  same uniform `scale`) until the model grows `scaleX/scaleY`.
- **Clamp** to the same ranges `updateTransform` enforces:
  `scale ∈ [0.05, 8.0]`, `posX/posY ∈ [-2, 2]` (`editor_view_model.dart:405–409`).
- **Keyframe-aware for free:** `updateTransform` already redirects a write to a
  keyframe at the playhead when that property is animated
  (`editor_view_model.dart:383–412`). The gizmo just calls it; animation Just
  Works.
- **Live vs commit:** like rea-capcut, apply the delta to a *local* preview
  transform during the drag and call `updateTransform` **on pointer-up**
  (optionally throttled during drag). `rea-capcut` only commits on up
  (`Player.tsx:395–429`); a mid-drag throttle gives smoother keyframe-less feel.
- **Absolute, not incremental**, pointer mapping (concat `:263–272`): compute
  from the current pointer position vs. the press origin each move, so a drag
  against the moving box doesn't drift.
- **Hit target > drawn size** by a few px (concat `:251–257`).
- **Selection source:** `EditorState.selectedId` / `selected`
  (`editor_view_model.dart:17–24`); only show the gizmo when the playhead is
  within `[clipStart, clipStart+duration)` (clip start = `_selectedClipStart`,
  `editor_view_model.dart:263–271`), matching rea-capcut's "under the playhead"
  guard (`Player.tsx:368–373`).

### 3.4 Overlay gizmos (text / sticker / PiP)

Overlays use **top-left-origin fractions 0..1** with a different anchor than
clips (see §4), so the gizmo for an overlay uses a separate mapping:

```
player→frac:  fx = pxX/displayW ;  fy = pxY/displayH      // 0..1
```

- **Move** → writes `overlay.x`, `overlay.y` (= anchor fraction).
- **Corner/edge scale** → `TextOverlay.fontSize`, `StickerOverlay.size`,
  `VideoOverlay.scale` (all height-fractions).
- **Rotate** → `StickerOverlay.rotation`, `VideoOverlay.rotation` (TextOverlay
  has no rotation field today).

---

## 4. Text / sticker / overlay layer rendering

All three overlay kinds are **project-level**, timed on the final concatenated
timeline in seconds (`text_overlay.dart:19–31`, `sticker_overlay.dart:13–27`,
`video_overlay.dart:32–46`). At playhead `t` (timeline seconds), show overlay
`o` iff `o.start ≤ t < o.end` (video overlay: `startTime ≤ t < startTime+duration`).

Render each as a `Positioned`/`Transform` Flutter widget over the video, using
the **frame-fraction** coordinates each model already stores — these are the
exact same fractions ffmpeg burns in on export, so the live preview is WYSIWYG
for placement:

| Overlay | Position | Size | Widget | Fields |
|---|---|---|---|---|
| **Text** | anchor `(x,y)·(displayW,displayH)`, aligned by `alignment` | `fontSize·displayH` px | `Text` with color/align | `text_overlay.dart:55–67` |
| **Sticker (emoji)** | center `(x,y)` | `size·displayH` px glyph | `Text(emoji)` + `rotation` | `sticker_overlay.dart:55–69` |
| **Sticker (image)** | center `(x,y)` | `size·displayH` | `Image.file` + `rotation` | `sticker_overlay.dart:46–69` |
| **PiP video** | center `(posX,posY)` | `scale·displayH`-ish (export uses `scale2ref`) | 2nd `media_kit` player *or* poster frame (see note) | `video_overlay.dart:60–101` |

- Text alignment: `TextOverlayAlignment.{left,center,right}` positions the box
  relative to its anchor (`text_overlay.dart:7–17`), matching rea-capcut's
  `textAlign` + anchor math (`previewLayers.ts:151–162`).
- **PiP caveat:** a second live decoder per PiP is heavy. Pragmatic tiers:
  (a) show a **still poster frame** of the PiP at its current source time
  (cheap, good enough for placement), or (b) a second `media_kit` player only
  while that PiP is selected/being-placed. rea-capcut affords one decoder per
  clip (`Player.tsx:54`) but it's a web `<video>`; media_kit players are
  heavier, so start with (a).
- **Blend modes** (`VideoOverlay.blendMode`, `kBlendModes`) mostly can't be
  reproduced live — Flutter `BlendMode` covers the common ones (`multiply`,
  `screen`, `overlay`) via `BlendMask`/`ColorFiltered`; exotic ones fall back
  to `normal` in preview (see §6).

---

## 5. Playback & seeking across clips

MozCut's main track is a **sequential concat**: clip `i` starts at
`Σ durations[0..i)` (`editor_view_model.dart:261–271`). The playhead
(`playheadProvider`) is in timeline seconds (`:273–282`).

### 5.1 Clip-at-playhead lookup

```dart
(Clip clip, double clipStart)? clipAt(double t, List<Clip> clips) {
  var acc = 0.0;
  for (final c in clips) {
    if (t >= acc && t < acc + c.duration) return (c, acc);
    acc += c.duration;
  }
  return clips.isEmpty ? null : (clips.last, acc - clips.last.duration); // clamp to end
}
// source time inside that clip (mirrors rea-capcut Player.tsx:247):
double sourceTime(Clip c, double clipStart, double t) =>
    c.inPoint + (t - clipStart) * c.speed;
```

This is rea-capcut's `active`/`target` logic (`Player.tsx:230`, `:247`) adapted
to our single-track concat.

### 5.2 media_kit open / seek driver

Drive one player; swap media only when the playhead crosses a clip boundary.

| Event | Action |
|---|---|
| Playhead moves, **same clip** | `_player.seek(Duration(sourceTime))` if `|pos − sourceTime| > ~frame` (rea-capcut uses 0.15 s playing / ~0 paused, `Player.tsx:250–251`) |
| Playhead crosses into a **new clip** | `await _player.open(Media(clip.sourcePath), play: _playing); await _player.seek(sourceTime)` — only when `sourcePath` changes |
| Play/Pause | `_player.playOrPause()` (already wired, `player_panel.dart:127`, `:365`) |
| During playback, clip ends | when `pos ≥ clip.outPoint` (source) → advance playhead to next clip start → triggers open of next clip |
| Speed | `media_kit` `setRate(clip.speed)`; combine with `sourceTime` using `speed` factor |

- **Boundary detection must come from the timeline playhead**, not the raw
  player position, because each clip's player position is *source* time, not
  timeline time. During playback: `timelineT += Δreal`; convert to
  `(clip, clipStart)`; if clip changed → `open`. This is the inverse of what
  `player_panel.dart:80–95` does today (it copies raw player position straight
  to the playhead, which only works because today's player IS the whole proxy).
- Keep the **playhead⇄seek** reconciliation already in
  `player_panel.dart:145–151` (only act on jumps > 200 ms) but base it on
  timeline time and the clip-at-playhead map.
- **Audio lane / overlays during playback:** a single base-clip player won't
  emit the audio-lane clips or PiP audio. For accurate *audio* playback you
  still need either per-lane players or the proxy. Recommend: preview audio =
  base track only (fast path); full mix only in the proxy/export (§6).
- **Gapless transitions (`xfade`) and cross-clip effects** can't be shown by a
  single seeked decoder — preview shows a hard cut; the proxy/export shows the
  real transition (§6).

---

## 6. What stays on the ffmpeg proxy

Keep `Engine.renderPreview` (`ffmpeg_engine.dart:263–322`, 640-wide ultrafast
proxy sharing `_buildFilterGraph`) but **demote it from the default to an
opt-in "Accurate preview / Render preview" action** (the header button at
`player_panel.dart:323–332` already does a forced render — repurpose it).

| Capability | Real-time composite | ffmpeg proxy |
|---|---|---|
| Transform (scale/pos/rotate/flip/opacity) | ✅ live | ✅ |
| Text / sticker / PiP **placement** | ✅ live | ✅ |
| Keyframed transform animation | ✅ (`clip.valueAt`) | ✅ |
| Color filters / eq (brightness/contrast/sat) | ⚠️ approximate via `ColorFiltered`/`ColorFilter.matrix` | ✅ exact |
| Effects (`effectId`: blur/grain/distort) | ⚠️ some via `ImageFiltered` (blur); most no | ✅ exact |
| Speed-changed playback | ⚠️ via `setRate`, audio pitch differs | ✅ exact |
| Transitions (`xfade`) | ❌ hard cut | ✅ |
| Full audio mix (audio lane + PiP + fades) | ❌ base track only | ✅ |
| Blend modes | ⚠️ common ones only | ✅ |

**How CapCut handles the gap:** its DOM/canvas preview approximates color/blur
with CSS/canvas filters (rea-capcut does exactly this —
`previewLayers.ts:39–102` pixel ops, `Player.tsx:293` `ctx.filter="blur()"`)
and accepts that the final export is the source of truth. Mirror that:
approximate color/blur live with Flutter `ColorFiltered`/`ImageFiltered`, and
offer the proxy button for a frame-accurate check / before export.

**Recommendation:** do **not** drop the proxy — keep it as the explicit
"accurate preview" and as the export dry-run — but it must no longer be the
thing the monitor shows by default.

---

## 7. Why our current player is black — diagnosis

Reading `player_panel.dart`, the monitor only ever shows the **ffmpeg proxy**,
and the proxy is produced by a chain with several ways to stay black:

1. **Nothing shows until a proxy exists.** On first clips, `build` computes a
   signature and calls `_scheduleAutoRender` (`:165–176`), which **debounces
   450 ms** (`:244–248`) *then* runs `_renderPreviewNow`. Until that ffmpeg run
   finishes (seconds for a real timeline), `_loadedPath` is null and the
   `Video` widget has no media → **black**. rea-capcut shows a frame on the
   very next animation frame; we show black for the whole render.
2. **`open(play:false)` may not paint a first frame.** `_renderPreviewNow`
   calls `_player.open(Media(path), play: wasPlaying)` (`:283`); when
   `wasPlaying` is false, media_kit/mpv commonly **does not decode/paint frame 0
   until you nudge it**. So even after a successful render the monitor can stay
   black until the user hits play/seek. Fix: after `open(..., play:false)` do a
   tiny `seek(Duration.zero)` (or `seek(resumeAt)`, which we only do when
   `resumeAt>0`, `:284`) to force a decode of the first frame.
3. **Silent render failure also = black.** If `renderPreview` throws (ffmpeg not
   found, bad filtergraph, codec), we show a SnackBar (`:285–290`) but
   `_loadedPath` stays null → **black** monitor behind the toast. Any
   filtergraph edge case makes the whole preview black rather than degrading.
4. **Coalescing can strand the last frame.** If an edit lands mid-render,
   `_renderPending` queues exactly one more (`:294–298`); a burst can leave the
   loaded proxy a step behind, but that shows *stale*, not black — secondary.

Most likely primary cause: **(1)+(2)** — there is simply no live frame source,
so any delay or a non-playing `open` reads as a black monitor. Real-time
compositing (§2) removes (1) and (2) entirely because the `Video` widget is
always bound to a real clip and seeked to the playhead on open.

---

## 8. Prioritized implementation roadmap

| # | Step | Scope | Payoff |
|---|---|---|---|
| **P0** | **Bind the monitor to the raw clip at the playhead.** Replace `_renderPreviewNow` as the default: `clipAt(playhead)` → `open(clip.sourcePath)` on boundary change, `seek(sourceTime)` otherwise (§5). After `open(play:false)`, force `seek` to paint frame 0 (§7.2). | `player_panel.dart` | Kills the black monitor; instant preview |
| **P1** | **Apply the base clip transform** to the `Video` via `Transform`+`Opacity` using `clip.valueAt` at the playhead (§2.2). Letterbox already done. | `player_panel.dart` | WYSIWYG transform, keyframes animate live |
| **P2** | **Overlay layers** (text, sticker, PiP-as-poster) as `Positioned`/`Transform` widgets gated by `start/end` at the playhead (§4). | new `_overlay_layer.dart` | Titles/stickers show live |
| **P3** | **Transform gizmo** for the selected clip: bounding box + corner (scale) + rotate handle + body drag, writing via `Editor.updateTransform`; concat's fraction/rotated-grip model (§1.3, §3). Commit on pointer-up. | new `_gizmo_layer.dart` | Direct manipulation parity with CapCut |
| **P4** | **Cross-clip playback driver**: timeline-time clock advances playhead, crosses boundaries → open next clip; speed via `setRate` (§5.2). | `player_panel.dart` | Multi-clip play without the proxy |
| **P5** | **Overlay gizmos** (text/sticker/PiP): same gizmo, overlay fraction mapping, writes `x/y/size/fontSize/scale/rotation` (§3.4). | `_gizmo_layer.dart` | Place overlays in the monitor |
| **P6** | **Live color/blur approximation** via `ColorFiltered`/`ImageFiltered` for `brightness/contrast/saturation` + blur effects (§6). | layer widgets | Closer WYSIWYG |
| **P7** | **Demote the proxy to opt-in "Accurate preview"** on the header button; it also covers transitions + full audio mix (§6). Remove the auto-render signature hot path. | `player_panel.dart`, `ffmpeg_engine.dart` (unchanged) | Speed, with an accurate fallback |

Dependency order: P0 → P1 → (P2 ∥ P3) → P4 → P5 → P6 → P7. P0 alone fixes the
reported "slow + black" problem; P1–P3 deliver the CapCut feel.
