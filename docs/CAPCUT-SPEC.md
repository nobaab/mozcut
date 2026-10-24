# CapCut Desktop — Clean-Room Behavioral Specification

**For: MozCut (independent open-source video editor)**
**Status: Observable-behavior documentation only**
**Compiled: 2026-10-24**

## Preamble — Scope, Method, and Legal Boundary

This is a **clean-room behavioral specification** of CapCut Desktop (Windows/macOS): it describes *observable behavior and UX* so an independent team can reimplement equivalent functionality from scratch. Assembled entirely from public sources — CapCut's official help center, official resource/marketing pages, third-party tutorials/reviews, publicly posted write-ups of the plaintext draft JSON, and general NLE domain knowledge.

**No CapCut source code, binaries, or copyrighted assets were decompiled, disassembled, or reproduced.** Items not confirmed by an official source are marked **(observed/inferred)**.

**Implementer guidance:** adopt the *behavioral patterns, interaction models, taxonomies, and defaults* — NOT CapCut's specific draft field names or file layout. The generic "project = {metadata, canvas, material pool, ordered tracks referencing materials by ID}" architecture is common to all NLEs and is the part worth adopting.

---

## 1. Project / Draft Model

### 1.1 Storage location
| Platform | Default drafts path |
|---|---|
| Windows | `%LocalAppData%\CapCut\User Data\Projects\com.lveditor.draft` |
| macOS | `~/Movies/CapCut/User Data/Projects/com.lveditor.draft` |
| Cache | `…/User Data/Cache` — proxies/AI temp, safe to clear |

- Drafts folder is user-configurable (Settings → Draft → Save to); forward-only.
- Startup scans the save root and maintains a project-list index **separate** from folder contents (can desync). → MozCut: don't hinge availability on a separate index.

### 1.2 Draft folder structure (CapCut International = plaintext JSON)
| File | Purpose |
|---|---|
| `draft_content.json` (Win) / `draft_info.json` (Mac) | Canonical project graph — timeline, tracks, materials, segments, canvas, fps, duration. Authoritative. |
| `draft_meta_info.json` | Home-screen metadata + media registry (id, name, path, cover, timestamps, duration). |
| `draft_cover.jpg` | List thumbnail (timeline frame grab). |
| `draft_agency_config.json` / `draft_biz_config.json` / `draft_settings` | Animation-preset cache / feature flags / per-project UI state. |
| `assets/`, `common_attachment/` | Local media copies (per-draft / shared). |

**Takeaway:** only `draft_content.json` + `draft_meta_info.json` + cover are authoritative; rest is regenerable cache.

### 1.3 Conceptual project graph (generic NLE, not CapCut IP)
- **Material pool + timeline decoupled**: timeline tracks → segments reference materials **by UUID**, not inline. Multiple segments can share a material.
- **Top-level:** project id, name, duration (**microseconds**), fps, canvas (w×h + aspect label).
- **`tracks[]`:** ordered typed lanes (video/audio/text/effect/filter); **array order = z-stacking**.
- **Pools:** separate for video/audio/image/text/effects/animations/transitions/masks/speed-curves/fades. Segments carry timing + transform + crop + speed + keyframes, referencing shared materials.
- **Caution — text:** CapCut stores rich text as JSON-within-JSON with **UTF-16 byte-offset** style ranges (fragile). → MozCut: use a structured **run-list** model instead.

### 1.4 Home screen / recents
- Grid/list: thumbnail + name; duration + last-modified back sort/display.
- Per-tile ⋮ menu: Rename / Duplicate / Delete.
- Trash with ~30-day retention (cloud/web-registered projects). Orphaned drafts often still on disk (index ≠ folder).

### 1.5 Auto-save / versioning / cloud
- Continuous autosave; crash recovery on next launch. Interval not documented.
- **No user-facing version history** — only Trash undelete + autosave.
- Cloud "Space" syncs account-linked drafts across devices (only drafts uploaded; purely-local stays local).

---

## 2. Timeline Behavior

### 2.1 Multi-track
- Track types: video, audio, text, stickers, effects. No hard cap (performance-governed).
- **Main Track** pinned at bottom = primary sequence; everything else overlays above it; **higher track renders on top**.
- Auto-track creation: drag media above content → new overlay video track; new text/sticker/extracted-audio each spawn its own track.
- Per-track header: **Lock / Hide / Mute**. Track height adjustable (scales waveform).

### 2.2 Snapping
- Two independent toggles: **Main Track Magnet** (gap-closing) and **Auto Snapping** (edges/playhead/markers). Yellow **Preview Axis** (skim line) separate from playhead, toggleable.

### 2.3 Split
- **Ctrl/Cmd+B** split at playhead; **Ctrl/Cmd+Shift+B** split all tracks. Toolbar Split flanked by Delete-Left / Delete-Right.
- Splitting video splits its embedded audio too (extract audio first to split independently). Each half independently editable afterward (carries its own copy of the pre-split stack — observed/inferred).

### 2.4 Trim
- Drag white edge handle. On main track, trimming ripples neighbors (per Magnet); overlays may allow gaps. One trim interaction (no separate ripple/overwrite tool). Minimum clip length exists (value undocumented).

### 2.5 Ripple / delete
- Delete/Backspace removes clip, **leaves a gap**.
- **Gap-closing ripple = Main Track only** (via Magnet); does NOT cross overlay/audio tracks (CapCut lacks true multi-track ripple → MozCut improvement opportunity).
- **Q = Delete Left, W = Delete Right.**

### 2.6 Keyframes
- **Diamond icon per parameter** in the right inspector (inline, not a separate kf track).
- Workflow: select clip → playhead → click diamond → move playhead → change value (auto-inserts + interpolates).
- Keyframeable: **Position, Scale, Rotation, Opacity** (official); effect intensity / volume less consistent.
- Interpolation: smooth default; Ease In/Out referenced; no full curve picker documented.
- **Keyframes anchored to absolute timestamps**, not auto-rescaled on speed change (moderate confidence). → MozCut: prefer **clip-relative** keyframes.

### 2.7 Clip visuals
- Video clips show a **filmstrip** of sampled thumbnails (density scales with zoom).
- **No waveform on the main video track by default** — extract/separate audio to see a waveform. Waveform is an edit aid (not exported).

### 2.8 Zoom
- +/- buttons + slider (top-right). Ctrl/Cmd+=/−, Ctrl+scroll, pinch. **Fit timeline = Shift+Z.**

### 2.9 Selection
- Click; Shift+click multi (Select Mode = "A"). `[`/`]` select left/right; Ctrl/Cmd+A select all. Group = Ctrl/Cmd+G; Compound = Alt+G. Marquee select **likely absent** → MozCut improvement.

### 2.10 Drag
- Vertical drag = move track (up into empty = new overlay); horizontal = reorder. Media-bin drop between clips inserts (pushes later); at end appends. Edge = trim, body = move.

### 2.11 Default layering (bottom→top)
Main video → overlay video/image → text → stickers → effects/animations. Higher = on top.

---

## 3. Transform / Adjust (per-clip)

| Property | Default | Range | Notes |
|---|---|---|---|
| Scale | 100% | no documented min/max | slider + numeric + corner handles; proportional by default |
| Position X/Y | centered | — | numeric + drag; units/origin undocumented → MozCut: center-origin |
| Rotation | 0° | signed continuous | numeric + dial + handle; quick R = 90° (single source) |
| Opacity | 100% | 0–100% | slider; clip stays at 0% |
| Crop | full | Free + 1:1/3:4/4:3/16:9/9:16 | non-destructive |
| Blend mode | Normal | 9 modes | Darken, Multiply, Lighten, Screen, Overlay, Soft Light, Hard Light, Difference, Exclusion (only when 2 clips overlap) |

- On-canvas: corner = proportional scale, edge = stretch, Shift+corner = proportional, rotate handle, body-drag = position.
- **Flip:** horizontal "Mirror" one-click; vertical build-dependent.
- **Crop (reframe within clip) ≠ Ratio (whole-project canvas).**

---

## 4. Color / Filters / Adjustment

### 4.1 Adjust parameters
Brightness, Contrast, Exposure, Saturation, **Vibrance** (distinct), Highlights, Shadows, Midtones, Temperature, Tint, Sharpen, Vignette (intensity/size/softness), Fade, Grain. **HSL** sub-tool: 7 base color channels × Hue/Sat/Lum.
- Ranges/defaults **not documented** → MozCut picks its own (tonal = 0 bidirectional; intensity = 0 unidirectional 0–100).

### 4.2 Filters
- Categories: Life, Movies, Scenery, Portrait, Pro, Retro (+ web: Trending/Cinematic/Glitch/AI).
- Apply via "+"; becomes its own timeline layer draggable over clips. **Intensity 0–100** (the one documented numeric range). Filter + manual Adjust stack independently. Global = Adjustment Layer above all tracks. "Apply to all" copies settings.

### 4.3 LUT (desktop-only)
Adjust → LUT → Import; **.cube and .3dl**; hover-preview; double-click applies / "+" makes adjustment layer; intensity slider; persists in library. Not on web/mobile.

### 4.4 Curves & Wheels
RGB + Luma curves; 3-way color wheels (Shadows/Midtones/Highlights).

---

## 5. Effects / Transitions / Stickers / Text

### 5.1 Effects
- **Clip-level** (drag onto clip, bound to its duration) vs **global** (drag onto effects track, independent layer). Adjustment layers span the sequence.
- Categories: Stylize, Distort, Blur, Color Grading, AI Effects; + Trending/Glitch/Retro/Shake/Sparkle/Neon/3D/Lens/Light. **Body Effects** separate top-level (Face/Body).
- Default drop duration: short fixed, resizable (value undocumented).

### 5.2 Transitions
- Place two clips adjacent → drag transition onto the junction. **Consumes footage from BOTH sides** (needs media handles) → MozCut: symmetric crossfade requiring handles.
- Duration adjustable, **max 5s**. Categories: Basic, Camera, Glitch, Light, Overlay, Zoom, Slide, 3D, Blur, Mask, Distort, Trending.

### 5.3 Stickers
- Static + animated; own layer; drag/resize/rotate handles; animation presets Fade/Slide In/Out.

### 5.4 Text
- Add → own track. Templates (lower-thirds/titles). **Animation In/Out/Loop + Combo**, **default 0.5s**, separate in/out durations. Typography: letter/line spacing, alignment. Keyframeable (Pos/Scale/Rot/Opacity). **Decoration:** Stroke, Shadow (color/opacity/blur/distance/angle), background plate. TTS is separate and not live-linked.

### 5.5 Clip Animation tab
Any clip → In/Out/Loop (+Combo), default 0.5s. Presets: Fade, Zoom, Slide.

---

## 6. Speed

- **Normal:** 0.1x–100x, default 1x; slider + numeric; **Keep Pitch** toggle.
- **Curve/Ramp:** presets Montage, Hero, Bullet, Jump Cut, Flash In/Out; custom velocity graph, **up to 10 points**, Curve-mode range caps **10x**.
- **Optical Flow** (smooth slow-mo): interpolates in-between frames; toggle under Speed when rate < normal; target 30/50/60 fps (moderate confidence). Recommend ≥60fps source.
- Effects: duration scales; pitch per Keep-Pitch; keyframes not auto-rescaled (→ MozCut clip-relative).

---

## 7. Audio

- **Volume:** per-clip 0–200%, default 100%; keyframeable; no master bus (only Loudness Normalization batch).
- **Fade in/out:** Basic tab, seconds slider; default/curve undocumented.
- **Beat detection:** right-click audio → Auto Beat Sync (presets Beats 1/Beats 2); diamond markers, draggable, magnetic snap. **Auto Cut** (AI): Music Beat / Voice / Script modes; mobile+desktop, not web.
- **Ducking:** auto-lowers music under speech; version/plan-dependent; no attack/release UI.
- **Voice changer:** presets (Robot, Chipmunk, Elf, Deep, High, Gender swap, Echo, Megaphone, Electronic, Lo-Fi…) + manual Pitch/Speed.
- **Extract audio:** right-click → Extract/Separate → new audio track; source auto-mute undocumented (MozCut: mute source by default).
- **Import formats:** WAV, MP3, AAC, FLAC, WMA.
- **Denoise** (steady noise); **Vocal isolation** (Pro).

---

## 8. Captions / TTS

- **Auto-captions** ("Recognise Subtitles"): Captions → Auto Captions; **pick language first**; async generate→review; optional sound-effect captions.
- **Editing:** inline, auto-save; Split (Ctrl/Cmd+B), Merge up/down; drag blocks to time; min segment ~0.2–0.3s. **Style → "Apply to All Captions"** (auto-caption track only; manual text layers styled individually). Caption templates: Karaoke (Scale/Background/Bounce/ColorChange), Pop-by-word, Typewriter, Bounce.
- **TTS:** Text → type → Text to speech → voice → Generate → new audio clip. Speed 0.5–2.0x, Pitch −12…+12, Keep pitch. Not live-linked to text.
- **Translation:** web Subtitles → Translate (from/to); export SRT/TXT or burn in.

---

## 9. Export

- **Dialog:** name + location + Resolution/FPS/Bitrate; progress %; one-click share TikTok/YouTube (desktop).
- **Resolution:** 480p/720p/1080p/2K/4K; default 1080p (inferred); 2K/4K conditional on OS/RAM/source/HW; Pro-gated when Pro assets present.
- **FPS:** 24/25/30/50/60; default 30 (inferred).
- **Codec:** H.264 / HEVC (no ProRes). Container: MP4 (default) / MOV.
- **Bitrate:** Lower / Recommended / Higher / Custom (Kbps). Color: Rec.709 SDR vs HDR (project settings).
- **Hardware encode** toggle (Settings → Performance). **Audio-only:** MP3/WAV/AAC. **Still frame:** PNG/JPEG. **Range export:** I/O marks or Shift+X.
- **Watermark:** free projects export watermark-free; watermark comes from branded template outro clips / Pro assets (delete the branded clip). Pro needed for watermark-free Pro-asset use + 4K/60.
- **Batch:** single-project multi-variant only; no true multi-project queue.

---

## 10. Keyboard Shortcuts

> In-app panel (Help → Shortcut) is authoritative, searchable, **remappable**. Only `I`, `O`, `Shift+X` are officially confirmed (range export). Rest cross-referenced from third-party sheets (conflict on ~⅓). Adopt High/Medium; design your own for the rest + ship a remappable panel.

**Playback:** Space play/pause · ←/→ frame · ↑/↓ cut point · Home/End · **Shift+Z fit timeline**
**Edit:** Ctrl/Cmd+B split · Ctrl/Cmd+Shift+B split all · Q/W delete left/right · Del delete · Ctrl/Cmd+Z undo · Ctrl/Cmd+Shift+Z redo · Ctrl/Cmd+X/C/V · Ctrl/Cmd+D duplicate · Ctrl/Cmd+A select all · Ctrl/Cmd+G group · **I/O mark in/out · Shift+X range (official)**
**Zoom:** Ctrl/Cmd+=/− · Ctrl+scroll
**File:** Ctrl/Cmd+S save · Ctrl/Cmd+I import · Ctrl/Cmd+E export (conflict)

---

## 11. Preview / Player

- **Scrubbing:** real-time; ←/→ ±1 frame, Shift+←/→ several, Home/End, ↑/↓ cut, Space. Desktop = accurate (web=cloud placeholder, mobile=proxy).
- **Preview zoom:** own zoom (bottom-right: zoom/Ratio/fullscreen), separate from timeline; Fit + 25/50/100/200%; cosmetic. **Alt+Shift+Z fit preview** (vs Shift+Z timeline).
- **Aspect:** Ratio dropdown + project settings; 16:9/9:16/1:1/3:4/4:3; "Original/Adapted" matches first clip; Custom W/H (not saved as named preset). Mid-project change disturbs overlay layout.
- **Playback quality:** **Proxy** 720p/540p (Settings → Performance); independent of export resolution.
- **Full-screen** via icon; **no built-in before/after compare** → MozCut improvement.

---

## Appendix — MozCut improvement opportunities (where CapCut is weak)
True multi-track ripple delete · marquee selection · **clip-relative keyframes that survive speed changes** · structured text run-list (not UTF-16 offset-into-string) · a real before/after compare view · a proper audio mixer/master bus · deterministic paste targeting · true multi-project export queue.

*All claims trace to public sources. Nothing derived from decompilation or reproduction of CapCut code/assets.*
