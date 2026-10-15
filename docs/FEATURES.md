# MozCut — Feature Catalogue & Roadmap

An exhaustive feature list of the two editors MozCut is modelled on — **CapCut**
(desktop) and **Concat** (the open-source Rust editor) — merged into one reference
so we can build toward feature parity.

**Legend (MozCut column):** ✅ done · 🚧 UI scaffolded (no logic yet) · 🔜 planned · — not started
**Source columns:** ✅ has it · — doesn't / N/A

> Concat's built-in effect/filter/transition/audio catalogue is listed in full in
> the [Appendix](#appendix--concats-built-in-catalogue). Concat is also fully
> scriptable (JSON-RPC, gRPC, MCP, CLI) — a differentiator CapCut lacks.

---

## 1. Import / Media

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Local import (video/audio/image/GIF) | ✅ | ✅ | ✅ |
| Wide format support (MP4/MOV/MKV/WebM/AVI/M4V…) | ✅ | ✅ | ✅ (via FFmpeg) |
| Drag-and-drop import | ✅ | ✅ | 🔜 |
| Media bin / library panel | ✅ | ✅ | 🚧 |
| Probe duration / metadata | ✅ | ✅ | ✅ |
| Proxy mode (low-res for smooth 4K edit) | ✅ | ✅ | 🔜 |
| Hardware-accelerated decode/encode | ✅ | ✅ | 🔜 |
| Screen + webcam recording | ✅ | ✅ (record) | 🔜 |
| Stock video / image / music / SFX library | ✅ | — | 🔜 |
| Stickers / GIPHY | ✅ | — | 🚧 |
| Cloud storage / cross-device sync | ✅ | — | — |
| Brand kit / team spaces | ✅ (Pro) | — | — |
| Favorites / recently used | ✅ | ✅ | 🔜 |

## 2. Timeline Editing

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Multi-track timeline | ✅ | ✅ | 🔜 (single track now) |
| Split at playhead | ✅ | ✅ | ✅ |
| Trim (drag edges / set in-out) | ✅ | ✅ | ✅ (set in/out) |
| Ripple delete / close gap | ✅ | ✅ | 🔜 |
| Delete clip | ✅ | ✅ | ✅ |
| Drag to reorder / move clips | ✅ | ✅ | 🔜 |
| Snapping / magnetic timeline | ✅ | ✅ | 🔜 |
| Markers | ✅ | ✅ | 🔜 |
| Grouping / compound clips | ✅ | ✅ | 🔜 |
| Timeline zoom | ✅ | ✅ | ✅ |
| Playhead / frame-step navigation | ✅ | ✅ | ✅ (playhead) |
| Ruler / timecode | ✅ | ✅ | ✅ |
| Speed (uniform) | ✅ | ✅ | 🔜 |
| Speed curves / ramping | ✅ | ✅ | 🔜 |
| Optical-flow slow motion | ✅ | — | 🔜 |
| Reverse clip | ✅ | ✅ | 🔜 |
| Freeze frame | ✅ | ✅ | 🔜 |
| Keyframes (pos/scale/rot/opacity/volume) | ✅ | ✅ | 🔜 |
| Keyframe curve/graph editor | ✅ | ✅ | 🔜 |
| Replace clip source | ✅ | ✅ | 🔜 |
| Detach / extract audio | ✅ | ✅ | 🔜 |
| Undo / redo | ✅ | ✅ | 🔜 |
| Silence removal / smart cut | ✅ (AI) | — | 🔜 |
| Scene / shot detection | ✅ (AI) | — | 🔜 |

## 3. Video Adjustments

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Transform: scale / position / rotate | ✅ | ✅ | 🚧 |
| Crop | ✅ | ✅ | 🔜 |
| Mirror / flip | ✅ | ✅ | 🔜 |
| Opacity | ✅ | ✅ | 🚧 |
| Blend modes | ✅ | ✅ | 🚧 |
| Shape masks (+ feather / invert) | ✅ | — | 🔜 |
| Chroma key / green screen | ✅ | ✅ (Chroma Key) | 🔜 |
| Luma key | — | ✅ | 🔜 |
| Spill suppression / edge refine | ✅ | ✅ | 🔜 |
| AI background removal / cutout | ✅ | ✅ (person model) | 🔜 |
| Brush-correct the cutout mask | — | ✅ | 🔜 |
| Video stabilization | ✅ | — | 🔜 |
| Motion / body / face tracking | ✅ | — | 🔜 |
| Basic color (bright/contrast/sat/exposure/temp/tint) | ✅ | ✅ | 🔜 |
| HSL | ✅ | — | 🔜 |
| Curves | ✅ | ✅ | 🔜 |
| Color wheels (lift/gamma/gain) | ✅ | ✅ (Color Wheels) | 🔜 |
| LUT import (.cube) / filter presets | ✅ | ✅ (looks from .cube) | 🔜 |
| White balance | ✅ | ✅ | 🔜 |
| Sharpen / vignette / grain / glow / bloom | ✅ | ✅ | 🔜 |
| AI color match | ✅ (Pro) | — | — |

## 4. AI Features

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Auto captions (speech-to-text) | ✅ | ✅ (Whisper, local) | 🚧 |
| Caption translation | ✅ | — | 🔜 |
| Text-to-speech | ✅ | ✅ (Kokoro, local) | 🔜 |
| Voice cloning | ✅ (Pro) | ✅ (Chatterbox) | 🔜 |
| AI voice dubbing | ✅ (Pro) | — | — |
| Background removal / auto-cutout | ✅ | ✅ (local ONNX) | 🔜 |
| Retouch / beauty | ✅ | ✅ (enhance) | 🔜 |
| Auto-reframe (aspect) | ✅ | — | 🔜 |
| AutoCut (auto rough cut) | ✅ | — | 🔜 |
| Script-to-video | ✅ | — | — |
| Long-video → shorts | ✅ | — | 🔜 |
| AI video / image generation | ✅ (Pro) | — | — |
| AI avatars | ✅ (Pro) | — | — |
| AI upscale / enhance | ✅ (Pro) | — | 🔜 |
| Audio denoise / enhance | ✅ | ✅ | 🔜 |
| **Runs 100% locally / offline** | — (cloud) | ✅ | ✅ (goal) |

> **MozCut's edge:** Concat proves CapCut's whole AI bundle can run **locally and
> offline** (Whisper, Kokoro, ONNX cutout). That's our differentiator vs CapCut's
> cloud + paywall model.

## 5. Audio

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Music / SFX library | ✅ | — | 🔜 |
| Extract audio from video | ✅ | ✅ | 🔜 |
| Volume control + keyframes | ✅ | ✅ | 🔜 |
| Fade in / out | ✅ | ✅ | 🔜 |
| Voiceover recording | ✅ | ✅ | 🔜 |
| Beat detection | ✅ | — | 🔜 |
| Audio ducking | ✅ | — | 🔜 |
| Noise reduction / denoise | ✅ | ✅ (Noise Reduction) | 🔜 |
| Voice enhancer | ✅ | ✅ (Enhance Voice) | 🔜 |
| Loudness normalization | ✅ | ✅ (Normalize Loudness) | 🔜 |
| Voice changer / filters | ✅ | ✅ (13 voice/tone fx) | 🔜 |
| Room / space reverb | — | ✅ (Echo/Hall/…) | 🔜 |
| Vocal isolation / remover | ✅ | — | 🔜 |
| Pitch / speed | ✅ | ✅ | 🔜 |
| Audio in editor tab | ✅ | ✅ | 🚧 |

## 6. Text & Captions

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Text boxes + styling (color/size/align/spacing) | ✅ | ✅ | 🚧 |
| Fonts library | ✅ | ✅ | 🔜 |
| Outline / stroke / shadow / background plate | ✅ | ✅ | 🔜 |
| Text animations (in/out/loop) | ✅ | ✅ | 🔜 |
| Title presets / templates | ✅ | ✅ (presets) | 🔜 |
| Auto captions | ✅ | ✅ | 🔜 |
| Manual subtitle editor | ✅ | ✅ | 🔜 |
| Subtitle style presets | ✅ | ✅ | 🔜 |
| Keyword highlight | ✅ | — | 🔜 |
| TTS from captions | ✅ | ✅ | 🔜 |
| Stickers | ✅ | — | 🚧 |

## 7. Effects, Filters & Transitions

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Video effects | ✅ | ✅ (21) | 🚧 |
| Filters (color/style presets) | ✅ | ✅ (57) | 🚧 |
| Transitions | ✅ | ✅ (20) | 🚧 |
| Audio effects | ✅ | ✅ (25) | 🚧 |
| Overlays / PiP via blend | ✅ | ✅ | 🔜 |
| Body / tracked effects | ✅ | — | 🔜 |
| Effect parameter keyframing | ✅ | ✅ | 🔜 |
| GPU-rendered, live in preview | ✅ | ✅ (wgpu) | 🔜 |
| Loaded from manifests (not hard-coded) | — | ✅ | 🔜 (nice goal) |

## 8. Templates

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Project templates ("replace clips") | ✅ | ✅ (template API) | 🚧 (tab) |
| Aspect-ratio presets (16:9/9:16/1:1/4:5…) | ✅ | ✅ | ✅ (new-project presets) |
| Trending / community templates | ✅ | — | — |
| Save selection as template | ✅ | ✅ | 🔜 |

## 9. Export / Output

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| Resolution up to 4K | ✅ | ✅ (4K 60) | 🔜 (follows source) |
| Frame rate 24–60 | ✅ | ✅ | 🔜 |
| H.264 | ✅ | ✅ | ✅ |
| HEVC (H.265) | ✅ | ✅ | 🔜 |
| AV1 | — | ✅ | 🔜 |
| 10-bit / HDR (BT.2020) | — | ✅ | 🔜 |
| Bitrate / CRF control | ✅ | ✅ (CRF + CBR) | 🔜 |
| MP4 / MOV output | ✅ | ✅ | ✅ (MP4) |
| GIF export | ✅ | — | 🔜 |
| Audio-only export (MP3/WAV/AAC/FLAC) | ✅ | ✅ | 🔜 |
| Still-frame export (PNG) | ✅ | ✅ (first/still png) | 🔜 |
| Export progress | ✅ | ✅ | ✅ |
| No watermark / free | ✅ (desktop) | ✅ | ✅ |
| Platform publishing presets | ✅ | — | — |

## 10. Platform, Workflow & Scripting

| Feature | CapCut | Concat | MozCut |
|---|:--:|:--:|:--:|
| macOS / Windows / Linux | ✅ | ✅ | ✅ (macOS; Win/Linux next) |
| Android | ✅ | ✅ | 🔜 |
| Project launcher (new / recents) | ✅ | ✅ | ✅ |
| Project = folder + manifest | ✅ (draft folder) | ✅ (concat.json) | ✅ (mozcut.json) |
| Autosave / save project | ✅ | ✅ | ✅ (save) |
| Resizable / dockable panels | ✅ | ✅ (dockable) | ✅ (resizable) |
| Keyboard shortcuts | ✅ | ✅ | 🔜 |
| Undo/redo history | ✅ | ✅ | 🔜 |
| Multi-language UI | ✅ | ✅ (25 locales) | 🔜 |
| **JSON-RPC / gRPC / MCP API** | — | ✅ | 🔜 |
| **CLI driver** | — | ✅ | 🔜 |
| Cloud projects / collaboration | ✅ | — | — |
| Account / login | ✅ | — | — (stays account-free) |

---

## Appendix — Concat's built-in catalogue

Concat ships **123 effect packages** (loaded from TOML + WGSL manifests). A target
list for MozCut's own catalogue.

### Transitions (20)
Dissolve, Blur Dissolve, Film Burn, Glitch, Glitch Warp, RGB Split, Cube, Light
Leak, Light Leak Flash, Push, Slide, Spin, Swirl, Clock Wipe, Iris, Linear Wipe,
Shape Wipe, Whip Pan, Zoom, Zoom Blur.

### Video effects (21)
Sharpen, Gaussian Blur, Motion Blur, Zoom Blur, Color Wheels, Contrast, Curves,
Exposure, Saturation, White Balance, Chroma Key, Luma Key, Chromatic Aberration,
Fisheye, Pixelate, Bloom Pulse, Halftone, Film Grain, Glow, Posterize, Vignette.

### Filters (57)
*Cinematic:* Bleach Bypass, Cool Blue, Cyberpunk, Daydream, Film, Midnight, Moody,
Night, Noir, Rain, Sage, Sci-Fi, Teal & Orange · *Everyday:* Clean, Cloudless Sky,
Fresh, Golden Hour, Ivory, Lagoon, Milk, Soft Light, Umber, Vivid · *Color:*
Contrast Pop, Cool, Vibrance, Warm · *B&W:* High-Contrast Mono, Silver · *Film:*
Classic Chrome, Retro 70s, Super 8 · *Retro:* Bronze, Digicam, Falling Dust, Mono,
Polaroid, VHS, Vintage · *Portrait:* Fair, Natural, Peach, Rosy · *Scenery:*
Autumn, Tropical, Vivid Landscape, Winter Cool · *Stylised:* Marquee, Matcha, Neon,
Pink Fuzz, Retro Cartoon, Spooky · *Vibe:* Dreamy, Vaporwave · *Food:* Delicious ·
*Adjust.*

### Audio effects (25)
*Clean:* Enhance Voice, Noise Reduction, Normalize Loudness · *Space:* Cathedral,
Echo, Hall, Plate, Room, Stadium, Underwater · *Tone:* Bass, Bright, Distorted,
Lo-fi, Radio, Telephone, Treble, Vinyl · *Voice:* Chipmunk, Deep, Megaphone, Pitch,
Robot, Sweet, Whisper.

---

*Last updated: 2026-10-15. Sources: Concat repo (github.com/jub0t/concat) and
CapCut official docs + reviews.*
