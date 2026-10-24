# MozCut Timeline Behavior Spec

Implementation-ready reference distilled from two production-grade CapCut-style editors, mapped onto MozCut's current Flutter code.

**Reference projects**
- **rea-capcut** — Electron / React / TypeScript CapCut clone. *Most relevant.* Browser Pointer Events + native scroll.
- **concat** — Rust + Slint native editor. *Secondary.* Slint declarative `pointer-event` / `scroll-event` channels.

**Our code under analysis**
- `lib/ui/features/editor/views/timeline_panel.dart` (~1600 lines; clip widgets, scroll/pan `Listener`, ruler, lanes)
- `lib/ui/features/editor/view_models/editor_view_model.dart` (`Editor` notifier: select/reorder/setTrim/split/remove)
- `lib/ui/features/editor/view_models/editor_ui_state.dart` (`TimelineZoom`, playhead, selection providers)
- `lib/ui/features/editor/view_models/editor_shortcuts.dart` (global `HardwareKeyboard` handler)
- `lib/ui/core/widgets/split_handle.dart` (trim/split handle widget)

**The single most important architectural takeaway up front:** both references keep *pan/scroll* and *clip-drag* on **two structurally separate input channels that never arbitrate against each other** — pan/scroll is native wheel/`scroll-event`, clip-drag is explicit pointer-button press. MozCut instead lets a clip's `HorizontalDragGestureRecognizer` and the `Scrollable`'s pan recognizer fight in one gesture arena over the *same* synthetic trackpad pointer, and the clip wins. That is the root of the "two-finger pan moves the clip" bug. Fix = exclude `PointerDeviceKind.trackpad` from clip drag recognizers. Details in [the Immediate Fix section](#immediate-fix-two-finger-horizontal-pan-moving-the-selected-clip).

---

## 1. Pointer / gesture disambiguation (the critical topic)

### How the references do it

**Core principle shared by BOTH references: pan and drag are different *input types*, not two interpretations of one stream.**

| Gesture | rea-capcut routing | concat routing |
|---|---|---|
| Pan / scroll (wheel, trackpad 2-finger) | Native browser scroll on `.tl-scroll {overflow:auto; overscroll-behavior:contain}` (`Timeline.css:106-112`). App never touches it. | `scroll-event` channel; bubbles to ancestor `wheel := TouchArea` in `Lanes` (`lanes.slint:1411`). Clips never implement `scroll-event`. |
| Zoom | `wheel` listener, acts **only if** `ctrlKey\|\|metaKey`, else no `preventDefault` → native scroll (`Timeline.tsx:432-445`) | `scroll-event` with `ctrl/meta` → `zoomed`, anchored at `seconds-at(mouse-x)` (`lanes.slint:1419-1434`) |
| Clip move / trim / marquee / scrub | `onPointerDown` on specific DOM nodes only (`startClip` 1069, trim handles 1217/1251, `startSelection` 1005, `scrub` 826/848) | `pointer-event`+`moved` on each `Clip`'s `TouchArea` (`lanes.slint:555`) |

**Why a trackpad swipe can never hijack a clip drag in the references:**
- rea-capcut: a two-finger trackpad swipe with no button pressed emits **`wheel` events only, never `pointerdown`**. Every drag entry point is gated behind `onPointerDown`, so it is structurally unreachable from a wheel gesture. There is no threshold logic trying to tell pan from drag — the browser routes them through different APIs before app code runs.
- concat: a trackpad swipe fires `scroll-event`; a `Clip` only handles `pointer-event`/`moved`, so the event bubbles straight past it to the ancestor pan handler (`lanes.slint:1409-1410` comment: *"a wheel the clips do not handle bubbles up to here"*).

**Hit zones**
- rea-capcut trim handles: fixed **7px** DOM strips, `.tl-trim-start{left:0}` / `.tl-trim-end{right:0}` (`Timeline.css:358-387`), opacity 0 until hover/selected. Disambiguation is by **which DOM element was hit**, not geometric math. `touch-action:none` is set on `.tl-clip` only (`Timeline.css:253`), never on the scroll/lane background — so panning still works over empty space.
- concat trim edge zone: **6px** (`edge-grab:6px`, `lanes.slint:135,241-243`), cursor → `ew-resize`.

**Click-vs-drag thresholds**
- rea-capcut: Manhattan distance `|dx|+|dy| < 3px` suppresses clip move/trim start (`Timeline.tsx:499-503`); `< 5px` for marquee (`589`). Below → treated as click (select/seek).
- concat: **4px** for clip-body drag (`lanes.slint:657-658`, bug #247: a shaky-hand click reported 1-2px and snapped the clip away). Touch/finger pickup additionally requires an **8px** slop *and* a **400ms hold** (`lanes.slint:646,683-693,1293`) — "as in CapCut".

**Wheel vs trackpad-pan vs pinch (inside the scroll channel)**
- rea-capcut: `ctrlKey||metaKey` on wheel = zoom (browsers set `ctrlKey` synthetically for trackpad pinch); otherwise native scroll. `Timeline.tsx:435-444`.
- concat (`lanes.slint:1412-1461`): hand-tool on → always pan; `ctrl/meta` → zoom at cursor; `shift` → pan on nonzero axis; plain wheel → `delta-x`→horizontal pan **and** `delta-y`→vertical track scroll *from the same event* (fixed from a bug where "a two-finger swipe is never exactly vertical… the old rule sent the whole event sideways on any x at all", `1441-1446`).

### MozCut implementation plan

Our architecture is actually *close* to correct at the container level and *wrong* at the clip level.

- **Keep** the `Listener` → `SingleChildScrollView(controller: _hScroll)` structure (`timeline_panel.dart:299-304`). `_handlePointerSignal` (124-136) and `_handlePanZoomUpdate` (144-162) already route mouse-wheel and trackpad correctly, and `_hScroll` is correctly shared across ruler + all lanes.
- **Fix** the clip widgets so their drag recognizers only accept genuine mouse/touch/stylus drags — see the Immediate Fix section. This single change makes our gesture layer match the references' "separate channels" guarantee.
- **Adopt a click-vs-drag threshold** explicitly rather than relying on Flutter default touch-slop alone: our `_commitReorder` already uses `shift.abs() < 1px` as "was a tap" (`1201-1217`); raise the no-op floor to a real slop of ~4px to match concat and avoid accidental micro-moves.
- **Adopt the "which widget was hit" model** for hit zones (we already do: clip body `GestureDetector` is inset by `_handleWidth=8px`, trim handles are separate `SplitHandle` widgets at `left:0`/`right:0`, `1225-1258`). This is correct; keep it.

---

## 2. Selection model

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Multi-select | Yes — modifier-click (`meta\|ctrl\|shift` → additive, `Timeline.tsx:467`) + marquee drag (`startSelection` 581-627) | Yes — `shift\|ctrl\|meta` → additive (`clip_pressed`, `studio.rs:4968-4985`) + band/marquee (`lib.rs:1157-1175`) |
| Click empty → deselect | Yes, if no marquee drag and not additive, also seeks playhead (`Timeline.tsx:619-623`) | Yes — empty band rect catches no clips → clears (`lib.rs:1157`) |
| Linked clips | Clicking one selects its linked a/v partner group (`linkedIds`, `timelineEdits.ts:9-12`) | No link-on-select (links removed, #265) |
| Locked | Can be visually selected but filtered out of movable set (`Timeline.tsx:481-486`) | Locked clip ignores all pointer events (`studio.rs:4945`) |
| Selection drives | Inspector (clicked clip first), toolbar enable-state, keyboard nudge/delete | Inspector, trim gating (`len<=1`), delete/ripple target, multi-drag group |

### MozCut implementation plan

Our model is **single-select only and fragmented across 4 uncoordinated stores**: `EditorState.selectedId` (`editor_view_model.dart:16`), `selectedAudioClipProvider`, `selectedVideoOverlayProvider`, and a local `_selectedTextOverlayId`. Selection is set on **tap-up** via `Editor.select(id)` (`149`), correctly excluded from undo.

- **Short term:** unify the four selection stores behind one notion of "the selected timeline item" (a typed id: `{lane, id}`). This removes the current bug where selecting a video clip doesn't clear an audio selection.
- **Medium term:** add multi-select (a `Set<SelectionRef>`), driven by modifier-tap (`shift`/`meta`), to enable group move/delete.
- **Deselect-on-empty:** we already null per-lane selection on empty-lane `onTapDown` (overlay 527-531, audio 581-585, text 344-352) — but the **video lane empty tap scrubs instead of deselecting** (`396-401`). Align it: empty-tap should both scrub *and* clear `selectedId` (references do both).

---

## 3. Drag to move / reorder

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Model | Free positioning, overlap allowed (`TIMELINE_EDITING.md:37`) | Free + collision resolution `resolve_moves` lands in nearest gap (`studio.rs:5073-5076`) |
| Snapping while moving | `0`, playhead, every other clip's start+end, tested on **both** dragged edges (`Timeline.tsx:534-540`) | Both edges of **every** moving clip vs non-moving clips+playhead+0 (`snap_shift`, `studio.rs:2678-2702`) |
| Threshold | `8/pps` → constant **8px** (`Timeline.tsx:427`) | `8.0 * seconds_per_pixel` → **8px** (`studio.rs:5039`) |
| Preview vs commit | Live preview in local React state (`displayClip` 234-251); commit on pointerup → `onMoveClips` (555-566) | Live "echo" preview (`5090-5095`); single `Command::MoveClips` on release (`5189-5216`) = one undo step |
| Cross-track | `targetTrack(clientY)` + `canMoveToTrack` kind/lock check (`Timeline.tsx:411-417,125-136`) | `nearest_row` from vertical delta, skips locked rows (`studio.rs:5053-5061`) |
| Layout freeze mid-drag | `frozenLayoutsRef` snapshots lane layout so others don't reflow (`185-271`) | echo/preview only |

### MozCut implementation plan

Current video-track reorder (`_commitReorder`, `timeline_panel.dart:1201-1217`) is **free-form drag, index resolved only on release** by comparing centers → `Editor.reorder` (`155-163`, a list `removeAt`/`insert`). Audio/overlay use `_commitMove` setting absolute `start` from raw pixel delta (`1297-1304`/`1505-1513`) with **no collision prevention and no snapping**.

- **Add snapping** (see §7) to the live `_dragDx` so the preview magnetizes to edges/playhead at an 8px threshold.
- **Keep commit-on-release** — it already gives us one undo entry; good, matches both references.
- **Add live preview reflow carefully:** our single-track video model makes reorder positional; when we add true multi-track, adopt concat's echo-preview + `resolve_moves`-style gap landing.
- **Cross-track:** not applicable until multi-track lands (§8); when it does, gate drops by clip-kind compatibility like `canMoveToTrack`.

---

## 4. Trimming

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Handle zone | 7px DOM strip | 6px edge-grab |
| Min length | `1/fps` (one frame), `model.ts:195` | `MIN_DURATION = 1/60 s` (`studio.rs:89`) |
| Ripple vs overwrite | Overwrite — never moves neighbors (`trimClip` 181-230) | `prefs.magnetic` on → ripples neighbors (infinite bound); off → stops at neighbor via `room_around` (`studio.rs:5108-5118`) |
| Snapping | Same `snap()` as move, excluding own linked group (`Timeline.tsx:505-508`) | `snapped()`, same 8px threshold (`5122,5141`) |
| Left-edge trim | Shifts `start` AND re-anchors `sourceIn += delta*speed` (`model.ts:208-209`) | `start=at; duration-=delta; source_start += delta*speed` (`studio.rs:5131-5134`) |
| Source clamping | Can't trim past original media in/out (`Timeline.tsx:516-525`) | bounded by room/source |
| Keyboard trim | Focused handle + Arrow = ±1 frame, Shift ±1s | n/a |

### MozCut implementation plan

Video trim: `Editor.setTrim` (`editor_view_model.dart:168-189`) clamps in/out to `[0,sourceDuration]`, min length **0.1s** hardcoded, pins the non-dragged edge. It changes only `inPoint`/`outPoint`; because `starts[]` is a running sum (`timeline_panel.dart:230-236`), left-trim implicitly ripples all later clips — an *accidental* consequence of the single-track model, not a mode. Audio/overlay trim (`_trimLeft`/`_trimRight` 1306-1329/1515-1541) explicitly shifts `start` on left-trim so the bar tracks the drag.

- **Make min-length frame-accurate** (`1/fps`) instead of a magic `0.1s`, matching both references.
- **Add trim snapping** (§7) on the dragged edge.
- **Make left-edge source re-anchor explicit & speed-aware** (`sourceIn += delta * speed`) — our code handles position but should confirm source in-point math matches the references for sped-up clips.
- **Decide ripple vs overwrite deliberately** via a `magnetic` preference (see §11) rather than letting the running-sum model force ripple.

---

## 5. Playhead & scrubbing

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Ruler click/drag | `scrub` seeks on pointerdown + every move, **no threshold** (`Timeline.tsx:572-580,826,848`) | `scrub` TouchArea seeks on press + continuous `moved`, no threshold (`lanes.slint:1817-1858`) |
| Track-body click | Empty-lane click seeks (`startSelection.finish` 621); dbl-click clip seeks to its start (1070) | Click (≤4px, not edge, select tool) on clip OR floor scrubs there (`lanes.slint:629-632,1534-1537`) |
| Follow during playback | Auto-scroll keeps playhead ~30% from right edge; **disabled while gesturing** (`Timeline.tsx:446-454`) | 40px edge-zone auto-scroll during scrub/drag (`lanes.slint:1339-1355`) |
| Snap playhead to edges | No | No (scrub lands exactly at pointer) |

### MozCut implementation plan

`_scrubToTimelineSeconds` (`timeline_panel.dart:915-938`) is wired from ruler `onTapDown`/`onHorizontalDragUpdate` (315-323) and video empty-space (395-401); it also best-effort-selects the clip under the click. `_Playhead` is an isolated `ConsumerWidget` (`860-895`, `IgnorePointer`-wrapped) so playback ticks don't repaint clips — good design, keep it.

- **Add auto-scroll-follow during playback** — currently missing; the playhead can run off-screen. Port rea-capcut's rule: when `playing && no active gesture`, nudge `_hScroll` to keep the playhead ~30% from the right edge. The `no active gesture` guard is essential (don't fight the user's manual scroll).
- **Keep "no threshold on ruler scrub"** — matches both references; every ruler press should seek immediately.
- Scrub needs no snapping (both references deliberately omit it).

---

## 6. Zoom

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Inputs | Ctrl/Cmd+wheel ×1.12/0.89; buttons ×1.25; range slider; `+`/`-` keys; Fit | Ctrl/Cmd+wheel `1.0025^(-dy)` clamped `[0.5,2]`/tick; pinch; buttons; keys |
| Anchor | **None** — content resizes under fixed `scrollLeft` (a real UX gap, don't copy) | Cursor-anchored: `left = anchor - (anchor-scroll_left)*(after/before)` (`timeline.rs:258`); keyboard/button anchor = playhead if on-screen else viewport center (`233-246`) |
| Range | `[5,400]` px/s (`Timeline.tsx:210`) | `[0.0005, 1.5]` s/px (`timeline.rs:24-26`) |
| Scroll interaction | zoom `preventDefault`s only when modifier held, never fights native scroll | plain wheel scrolls, never zooms |

### MozCut implementation plan

`TimelineZoom` (`editor_ui_state.dart:70-77`) is px/s clamped `[6,240]`, step ×1.3. Impressively, our wheel/trackpad zoom is **already cursor-anchored** via `zoomAnchoredScrollOffset` (`timeline_panel.dart:92-117,903-913`) — *better than rea-capcut.* Toolbar slider/buttons are not anchored (no cursor).

- **Anchor toolbar zoom to the playhead** (concat's `default_anchor` fallback) so button/slider zoom doesn't jump the view.
- **Add `+`/`-`/`Ctrl+=` keyboard zoom** (missing from our shortcuts, §10).
- Keep clamp + cursor-anchoring; this is our strongest existing area.

---

## 7. Snapping system

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Targets | `0`, playhead, every non-dragged clip's start+end (`Timeline.tsx:418-425`) | `0`, playhead, every non-moving clip's start+end (`studio.rs:2682-2689`) |
| Threshold | 8px (`8/pps`) | 8px (`8*seconds_per_pixel`) |
| Toggle | `snapping` toolbar button | `n` key / tray button (`prefs`) |
| Visual indicator | 1px teal `#3cd9c3` vertical line, full height, z9, `pointer-events:none` (`Timeline.css:508-514`, render 1321-1330) | **None** (silent — a UX gap in concat; don't copy) |

Note the naming trap: rea-capcut's "magnetic" button is *ripple-delete gap-closing*, NOT snap-while-drag; snap is the separate `snapping` toggle.

### MozCut implementation plan

**No snapping exists anywhere in MozCut today** (confirmed by full read). This is the single biggest feature gap vs both references.

- **Build a `SnapEngine`**: given a candidate time + the set of excluded clip ids, return the nearest target within `8 / pixelsPerSecond` seconds. Targets: `0`, playhead, every other clip's start/end (and later: markers, track bounds).
- **Wire it into** move (`_dragDx` preview, §3) and trim (§4).
- **Render a snap line** à la rea-capcut: a 1px full-height colored line at the snapped x, `IgnorePointer`, painted in the lane stack. Store the active snap x in UI state so the `_Playhead`-style isolated widget repaints it cheaply.
- **Add a snap toggle** to `timeline_toolbar.dart` + an `n` shortcut.

---

## 8. Multi-track

### How the references do it

| | rea-capcut | concat |
|---|---|---|
| Order | `project.tracks` array, index 0 = topmost row (`Timeline.tsx:880`) | `order: Vec<TrackId>`, **bottom-first**; `order[0]` composited first, later draws on top (`concat-core/timeline.rs:10-11`) |
| Add | Dropdown picks video/audio/text (`Timeline.tsx:1276-1301`) | `add_track` pushes to end = on top; UI `add-track(bottom)` can also insert at bottom |
| Remove | Confirm dialog if clips present; undo restores track+clips | Cascades: deletes the track's clips (`436-443`) |
| Reorder | Menu ↑/↓ `onTrackMove`, disabled if locked (`1405-1424`) | n/a (explicit order vec) |
| Types | video / audio / text | Track = Video\|Audio; clip kinds richer (video/audio/image/text/filter/shape/sound) — one track mixes kinds |

### MozCut implementation plan

MozCut has **fixed lanes** (text, video, overlay, audio) rather than user-managed tracks. This is a deliberate simplification.

- **Formalize z-order:** pick a convention (recommend concat's explicit, documented order) and ensure the compositor render order matches the visual lane order top-to-bottom.
- **If/when user-added tracks are needed:** model `tracks` as an ordered list with a `kind`, add/remove/reorder via a header menu, and enforce clip-kind compatibility on cross-track drops (§3). Until then, the fixed-lane model is fine and simpler.

---

## 9. Track header controls

### How the references do it

| Control | rea-capcut | concat |
|---|---|---|
| **Lock** | Blocks drag/trim/marquee/rename/delete/move; hides trim handles; shows 🔒 overlay + `cursor:not-allowed`; still selectable (`Timeline.tsx:466,1183,1268-1272`) | Disables ALL gestures (`clip_pressed` early-return 4945; `enabled:!locked` 556) + 45% scrim (`lanes.slint:539-546`) |
| **Hide/visibility** | Toggles `track.hidden`, dims clips via `is-hidden` class; actual render-skip lives in compositor (`Timeline.tsx:1061`) | `visible` render flag only, not interaction-gating |
| **Mute** | Toggles `track.muted`, hidden for text tracks; audio affected in player; badge on clips (`955-970,1129`) | Audio-only render/mix flag |
| **Solo** | Not implemented | Not implemented |
| (size) | — | Row-height menu auto/small/med/large |

Neither reference has solo. Lock is the most load-bearing control: it gates interactivity, not just rendering.

### MozCut implementation plan

Our header icons (lock/visibility/mute/more in `_trackHeader` 647-784) are **plain `Icon` widgets with no `onTap` — purely decorative today.**

- **Wire lock first** (highest value): add per-lane `locked` state; when locked, gate `_ClipSlot`/`_AudioClipSlot`/`_VideoOverlaySlot` drag+trim+select (early-return) and draw a dim scrim. Mirror concat's "disable hit-test + visual cue".
- **Wire mute** → the player/mixer (skip that lane's audio), with a clip badge.
- **Wire visibility** → the compositor (skip render) + dim the clips.
- **Skip solo** (neither reference has it; low priority).

---

## 10. Keyboard shortcuts

### Reference union (what a complete set looks like)

| Key | rea-capcut | concat | Effect |
|---|---|---|---|
| Space | ✓ | ✓ | Play/pause (rea seeks to 0 if at end) |
| Delete/Backspace | ✓ | ✓ | Delete selected |
| Shift+Delete | — | ✓ | **Ripple**-delete |
| Cmd/Ctrl+B | ✓ | ✓ | Split at playhead |
| Cmd/Ctrl+D | ✓ | ✓ | Duplicate |
| Cmd/Ctrl+Z / Shift+Z / Y | ✓ | ✓ | Undo / redo |
| Cmd/Ctrl+C / V | ✓ | ✓ | Copy / paste |
| Cmd/Ctrl+A | ✓ | ✓ | Select all |
| ←/→ | ✓ | ✓ | Seek ±1 frame (Shift = ±1s / ±10 frames) |
| Home/End | ✓ | ✓ | Seek start / end |
| `+` / `-` (Ctrl+=) | ✓ | ✓ | Zoom in/out |
| Alt+←/→ (rea) | ✓ | — | Nudge selected clip ±1 frame (Shift ×10) |
| q / w | — | ✓ | Delete-left / delete-right of playhead (CapCut razor-to-edge) |
| f | — | ✓ | Freeze frame |
| b / h / n / m / s | — | ✓ | Razor tool / hand tool / snap / mute / preview-axis |

### MozCut implementation plan

Current (`editor_shortcuts.dart`, via global `HardwareKeyboard.instance.addHandler` — chosen because clicking a non-focusable clip killed `Shortcuts`-widget focus, comment 10-18): Space, Cmd/Ctrl+B or S = split, Delete/Backspace = remove, Undo/Redo, ←/→ = nudge playhead ±1/30s. **Missing: zoom keys, select-all, copy/paste/duplicate, ripple-delete, clip nudge, snap toggle.**

- Keep the global-handler approach (it correctly dodges the focus problem).
- Add, in priority order: `Ctrl+=/-` zoom, `Shift+←/→` = ±1s seek, `Ctrl+C/V/D`, `Ctrl+A`, `Shift+Delete` ripple-delete, `n` snap toggle.

---

## 11. Extras

| Feature | rea-capcut | concat | MozCut plan |
|---|---|---|---|
| **Ripple delete** | "magnetic" toggle governs delete-time gap closing + linked-pair guard (`store.ts:298-346`) | `shift+delete` → `ripple_delete_selected` (`studio.rs:8032`); locked clips filtered out | Add a ripple-delete command; bind to `Shift+Delete` |
| **Magnetic timeline** | Toggle = *delete gap-closing only*, NOT drag magnetism (naming trap, `TIMELINE_EDITING.md:37`) | **Persisted preference**; affects trim bounds + ripples moves/trims (`timeline.rs:55-57`) | Add a persisted `magnetic` pref driving ripple on delete/trim; keep it distinct from *snap* |
| **Markers** | Not implemented | Only keyframe "key-marks" on ruler (`studio.rs:1868-1926`), not project markers | Defer; low priority |
| **Overwrite vs insert** | 3 modes (`insert`/`overwrite`/`overlay`) for source-panel drops (`timelineEdits.ts:82-122`); plain DnD = simple place | No explicit mode; `resolve_moves` is insert-like | Defer until source-preview placement exists |
| **Linked A/V** | Fully linked: select/move/trim/split/delete together via `linkId` (`timelineEdits.ts`) | **Deliberately unlinked** (#265): detached audio is its own clip | Pick one model; linked-A/V (rea's) is more CapCut-faithful |
| **Transitions** | — | Drag-resize transition on seam (`Gesture::TransitionResize`, `studio.rs:4955`) | Defer |

---

## Immediate fix: two-finger horizontal pan moving the selected clip

### Root cause (exact)

**Lines:** `timeline_panel.dart:1230-1237` (video clip), duplicated at **1345-1352** (`_AudioClipSlot`) and **1557-1564** (`_VideoOverlaySlot`).

```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: widget.onTap,
  onHorizontalDragStart: (_) => setState(() => _dragDx = 0),
  onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
  onHorizontalDragEnd: (_) => _commitReorder(),
  onHorizontalDragCancel: () => setState(() => _dragDx = 0),
  child: _ClipBar(...),
)
```

**Mechanism:**
1. On macOS, Flutter surfaces a trackpad two-finger swipe as `PointerPanZoom*` events and **converts them into a synthetic pointer-down+move stream** so ordinary `DragGestureRecognizer`s can consume them. This is exactly how `Scrollable` gets trackpad panning "for free" — its internal `HorizontalDragGestureRecognizer` lists `PointerDeviceKind.trackpad` in `supportedDevices`.
2. The clip body's `GestureDetector.onHorizontalDrag*` creates a `HorizontalDragGestureRecognizer` with **no `supportedDevices` restriction**, so it *also* accepts the trackpad-synthesized pointer.
3. When the swipe starts **over a clip**, both recognizers enter the same gesture arena for that synthetic pointer: the child clip recognizer (hit-tested first, so added to the arena first) and the ancestor `Scrollable`'s recognizer (added second). Both accept once movement passes slop; the **child reaches `resolve(accepted)` first and wins outright** — the arena's rule is first-to-accept wins, there is no "ancestor wins ties". The `Scrollable`'s pan is rejected.
4. Result: the clip's `onHorizontalDragUpdate` fires, `_dragDx` accumulates, the clip slides, and the view never pans — the observed bug.

The comment at `timeline_panel.dart:138-143` assumed `SingleChildScrollView` "already handles" horizontal trackpad pan. That holds **only over empty lane space** (the `Positioned.fill` `GestureDetector`s at 395-401/523-532/577-586 register only `onTapDown`, no drag recognizer, so nothing competes). It breaks precisely when the swipe begins on top of a clip.

### Exact fix

Restrict each clip drag recognizer to real pointer-drag devices, excluding `trackpad`, so a two-finger swipe has no competing recognizer and the ancestor `Scrollable` wins by default.

Replace the bare `GestureDetector.onHorizontalDrag*` at **1230-1237 / 1345-1352 / 1557-1564** with a `RawGestureDetector` whose `HorizontalDragGestureRecognizer` is built with:

```dart
RawGestureDetector(
  behavior: HitTestBehavior.opaque,
  gestures: {
    HorizontalDragGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
      () => HorizontalDragGestureRecognizer(
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          // PointerDeviceKind.trackpad deliberately OMITTED
        },
      ),
      (r) => r
        ..onStart = (_) => setState(() => _dragDx = 0)
        ..onUpdate = (d) => setState(() => _dragDx += d.delta.dx)
        ..onEnd = (_) => _commitReorder()
        ..onCancel = () => setState(() => _dragDx = 0),
    ),
  },
  // keep onTap via a TapGestureRecognizer in the same gestures map,
  // or leave the existing onTap on a plain GestureDetector wrapping the child.
  child: _ClipBar(...),
)
```

Same four callbacks, same `_dragDx` logic — a drop-in swap. Apply to all three slot widgets. (`onTap` for selection is pointer/touch/mouse and unaffected; keep it, e.g. via a `TapGestureRecognizer` in the same map or an inner `GestureDetector`.)

This mirrors the references exactly: after the fix, a trackpad swipe over a clip has no clip-level recognizer to claim it, so it flows to `_hScroll` — the same "separate channels" guarantee rea-capcut and concat get structurally.

**Verify:** two-finger horizontal swipe over a selected clip pans the view (does not move the clip); single-finger touch / click-drag with the mouse still moves the clip; trim handles (separate `SplitHandle`) unaffected.

---

## Prioritized implementation roadmap

Highest-impact-lowest-risk first. Each item is one coherent change.

1. **Fix the trackpad-pan bug** (§Immediate Fix). ~15 lines across 3 slot widgets, no model changes, unblocks the core interaction complaint. **Do this first.**
2. **Unify selection** into one `SelectionRef{lane,id}` store (§2), replacing the 4 fragmented stores. Low risk, removes cross-lane selection bugs, prerequisite for group ops.
3. **Add a `SnapEngine` + snap line + toggle** (§7). Biggest missing feature; self-contained; wire into move and trim. Threshold `8 / pixelsPerSecond`, targets `{0, playhead, other clip edges}`.
4. **Playhead auto-scroll-follow during playback** (§5), guarded by "no active gesture". Small, high perceived-quality win.
5. **Expand keyboard shortcuts** (§10): zoom keys, `Shift+←/→`, copy/paste/duplicate, select-all, ripple-delete. Additive, low risk.
6. **Frame-accurate min length + trim snapping + explicit left-edge source re-anchor** (§4). Correctness polish.
7. **Wire track-header Lock** (§9): gate drag/trim/select + scrim. Then mute (mixer) and visibility (compositor).
8. **Anchor toolbar/keyboard zoom to playhead** (§6). Our wheel zoom is already cursor-anchored; close the gap for button/slider.
9. **Ripple-delete + magnetic preference** (§11), distinct from snap. Persisted pref driving ripple on delete/trim.
10. **Multi-select → group move/delete**, then **multi-track** with cross-track drops (§3, §8). Largest surface area; do last.
