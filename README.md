<div align="center">

<img src="icon.png" width="140" alt="Paint for macOS icon">

# Paint for macOS

**A faithful re-creation of Microsoft Paint, built natively for macOS with Swift & AppKit.**

No web view, no Electron, no external dependencies — just a single native `.app` powered by Cocoa drawing.

</div>

---

## Overview

**Paint for macOS** brings the classic Windows Paint experience to the Mac. It reproduces the Windows 7/10‑style **Ribbon** interface, the full tool set, the shape library, the color palette, and the editing workflow you remember — implemented from scratch on top of AppKit's `NSView`, `NSBitmapImageRep`, and `NSBezierPath`.

The whole application is roughly **5,000 lines of Swift across 16 files**, with **62 automated tests** and a headless self‑test harness that renders the drawing engine and UI to PNG for visual verification.

> **Localized in 10 languages** — English, 繁體中文, 简体中文, 日本語, 한국어, Français, Deutsch, Español, Italiano, Português — auto-selected from your macOS system language (other languages fall back to English).

---

## Screenshots

| Ribbon UI | Drawing engine (tools & shapes) | Transparency |
|---|---|---|
| The full Home tab: Clipboard · Image · Tools · Tolerance · Brushes · Shapes · Size · Colors | Pencil, 9 brushes, 23 shapes, fills | Transparent color punches real alpha holes (checkerboard) |

*(Generate fresh screenshots any time with the built‑in render modes — see [Headless tooling](#headless-tooling).)*

---

## Features

### Tools
- **Pencil** — crisp, non‑antialiased freehand drawing in **1 / 2 / 3 / 4 px**
- **Brushes (9 styles)** — round, calligraphy 1 & 2, airbrush, oil, crayon, marker, natural pencil, watercolour, each with its own stroke algorithm
- **Eraser** — **4 / 6 / 8 / 10 px** square, paints with the background color (or **transparent**, erasing to real alpha); **right‑drag = colour replace** (only Color 1 pixels become Color 2)
- The Size menu adapts to the current tool and remembers a separate size for pencil, eraser and brushes/shapes
- **Fill with color (paint bucket)** — scanline flood fill with an adjustable **tolerance slider** (Windows 11 style): raise it to fill similar colors together
- **Color picker (eyedropper)** — sample any pixel into Color 1 / Color 2
- **Text** — click to type, rendered into the bitmap; while editing, drag the dashed frame to **move** the text box or its 8 handles to **resize** it (text wraps to the box width)
- **Magnifier** — click to zoom in (right‑click / ⌥‑click to zoom out), centred on the clicked point

### Shapes (23)
Line, curve, ellipse, rectangle, rounded rectangle, polygon, triangle, right triangle, diamond, pentagon, hexagon, four arrows (←↑→↓), 4/5/6‑point stars, rectangular / elliptical / cloud callouts, heart, and lightning bolt — each with independent **outline** and **fill** styles.
- Hold **Shift** for perfect squares / circles and 45°‑snapped lines
- Right‑drag swaps Color 1 / Color 2 (outline ↔ fill)
- Curve: drag a line, then click‑or‑drag two bend points; polygon: click vertices, double‑click / click the start point / press Return to close
- **Esc** cancels a shape in progress

### Selection & Image editing
- Rectangular **and** free‑form selection
- Move selections, plus **8 resize handles** to scale them; arrow keys nudge (Shift = 10px), Delete removes
- **Transparent selection** — background‑colour pixels in a floating selection become see‑through
- Selections are copied pixel‑exact (no colour shift or blur when moved)
- Cut / Copy / Paste / Delete via the system pasteboard
- Crop to selection
- Resize / rescale the canvas
- Rotate 90° / 180°, flip horizontal / vertical (transparency preserved)
- **Invert colours** (⇧⌘I, selection or whole image) and **Clear image** (⇧⌘N)
- Resize dialog keeps the aspect ratio when the box is ticked

### Colors
- 20‑swatch standard Paint palette + Color 1 / Color 2 — select Color 2, then a swatch (or *Edit colors*) sets Color 2; right‑click a swatch also sets Color 2
- **Control‑click acts as right‑click** on the canvas and palette (trackpad friendly)
- **Transparent color** swatch — draw, fill, or erase to genuine transparency
- "Edit colors" opens the native macOS color panel; picked colors are remembered

### Transparency (alpha)
- A dedicated **transparent color** lets the bucket, pencil, brush, eraser, and shapes clear pixels to true alpha 0 via `.clear` compositing
- The canvas renders a **checkerboard** behind transparent pixels so you can see through them
- Opaque tools correctly paint **over** transparent regions
- **PNG export preserves the alpha channel** — transparent areas stay transparent in the saved file

### View
- Zoom **25%–800%** in 25% steps — the View‑tab Zoom In/Out buttons and the bottom‑right `−` / `+` controls share identical stepping logic
- Live zoom slider and percentage in the status bar
- Pinch‑to‑zoom and ⌘‑scroll zoom around the pointer; **Fit to window** (⌘9)
- Gridlines (at high zoom), pixel **rulers** with pointer marker, status bar (pointer, canvas and selection size), full‑screen (⌃⌘F)

### File
- New / Open / Save / Save As (**PNG, JPEG, BMP, GIF, TIFF**)
- Print
- **Drag & drop** an image file onto the canvas to load it (with a blue drop highlight)
- Image properties dialog
- **Open Recent** menu
- JPEG/BMP export flattens transparency onto white (instead of black)
- Unsaved‑changes confirmation on New / Open / Close (⌘W) / Quit — every edit marks the document modified, and a cancelled or failed save never discards your work; save errors are reported

### Localization
- Full UI translated into **English · 繁體中文 · 简体中文 · 日本語 · 한국어 · Français · Deutsch · Español · Italiano · Português**, auto‑selected from the macOS system language (falls back to English); system dialogs (Open/Save, colour panel) follow the same language
- The ribbon sizes buttons and groups to each language's text, wraps long button labels onto two lines, and scrolls sideways if the window is too narrow — nothing gets cut off
- Interface text uses macOS‑standard sizes (12–13 pt)

### Polish
- Light‑appearance window matching Paint's look (readable in any system theme)
- Custom **retina‑crisp tool cursors** drawn as vectors — a yellow segmented pencil, a tilting paint bucket with a pouring drop, a 3D pink eraser, a light‑blue eyedropper, a magnifier with a `+`, precise crosshairs, plus diagonal/edge resize and 4‑way move cursors
- **Canvas resize handles** (right / bottom / corner) drag to extend or crop the canvas; selection handles resize floating images
- Snapshot‑based **undo/redo** (memory‑capped for large images) that survives canvas‑size changes (resize, rotate, crop, image insert)
- Ribbon laid out on a unified content band with a single type scale for tidy alignment

---

## Download

Grab **`Paint-macOS.dmg`** from the [latest release](https://github.com/walush2023/macos-paint/releases/latest), open it and drag **Paint.app** onto the *Applications* shortcut.

- **Signed with a Developer ID and notarized by Apple** — it opens with a normal double‑click, no Gatekeeper warning or `xattr` workaround needed.
- **Universal binary** — runs natively on both Apple Silicon and Intel Macs.
- Bundle identifier: `com.walush.paint`

---

## Requirements

- **macOS 12 (Monterey)** or later
- For building: **Xcode command‑line tools** with **Swift 5.9+** (developed against Swift 6.2)

---

## Build & Run

### Quick start (bundled `.app`)

```bash
git clone https://github.com/walush2023/macos-paint.git
cd macos-paint
./build_app.sh      # compiles, generates the icon, and packages Paint.app
open Paint.app
```

`build_app.sh` compiles the Swift Package, regenerates `AppIcon.icns` from `icon.png` (via `sips` + `iconutil`), and assembles `Paint.app` with its `Info.plist` and icon.

### Signed & notarized release

```bash
./release.sh        # universal release build → Developer ID signing (hardened runtime)
                    # → Apple notarization → staple → notarized dist/Paint-macOS.dmg
```

Needs a *Developer ID Application* certificate in the keychain and a `notarytool` credential profile
(`xcrun notarytool store-credentials`); override with the `SIGN_ID` / `NOTARY_PROFILE` environment variables.
The Intel slice needs full Xcode (the Command Line Tools ship arm64‑only Swift libraries).

### Run directly with SwiftPM

```bash
swift build
.build/debug/Paint
```

---

## Testing

The app ships with a self‑contained test harness — no XCTest target required. Each mode is a command‑line flag on the same binary.

```bash
# 62 functional unit tests (history, flood fill, selection, text box, shapes,
# file round‑trip, zoom, cursors, transparency, all 10 languages …)
.build/debug/Paint --unit-test

# Render every tool & shape into a 4×4 grid PNG (drawing‑engine check)
.build/debug/Paint --test out.png

# Render the full main window offscreen to PNG (UI‑layout check)
.build/debug/Paint --render-window ui.png
```

### Headless tooling

Extra diagnostic render modes used during development:

| Flag | Purpose |
|---|---|
| `--unit-test` | Run all 62 tests; exits non‑zero on failure |
| `--test <out.png>` | Draw all tools/shapes into a labelled grid |
| `--render-window <out.png>` | Offscreen snapshot of the whole window |
| `--cursor-preview <out.png>` | Enlarged preview of every tool cursor (with hot‑spots) |
| `--drop-test <img> <out.png>` | Simulate drag‑and‑drop image loading end‑to‑end |
| `--transparency-demo <view.png> <export.png>` | Punch a transparent hole and verify PNG alpha is preserved |

---

## Architecture

A single SwiftPM executable target. Key types:

| File | Responsibility |
|---|---|
| `main.swift` | Entry point + CLI test/render mode dispatch (`--lang xx` forces a UI language) |
| `AppDelegate.swift` | App lifecycle, main menu, dock icon |
| `MainWindowController.swift` | Window layout, file/edit/image/view actions, status bar |
| `TabBarView.swift` | File / Home / View ribbon tabs |
| `RibbonView.swift` | The whole ribbon: groups, buttons, palette, tolerance slider |
| `CanvasView.swift` | The drawing surface — `NSBitmapImageRep` backing, mouse handling, flood fill, selection, undo/redo, drag‑and‑drop, transparency |
| `Brushes.swift` | The 9 brush stroke algorithms |
| `Shapes.swift` | `NSBezierPath` geometry for all 23 shapes |
| `Cursors.swift` | Vector, retina‑rendered tool cursors |
| `Dialogs.swift` | Color picker & resize sheets |
| `Localization.swift` / `LocalizationExtra.swift` | 10‑language string tables |
| `Rulers.swift` | Pixel rulers & Open Recent list |
| `Models.swift` | Shared `PaintState`, enums, palette, undo `History`, transparent‑color helpers |
| `SelfTest.swift` / `UISnapshot.swift` / `UnitTests.swift` | Headless test & render harnesses |

### Design notes
- **Drawing model:** a bottom‑left‑origin `NSBitmapImageRep` is the single source of truth; an overlay `NSImage` previews shapes/selections without committing them.
- **Coordinate system:** the canvas `bounds` always equals the native pixel size while its `frame` is the zoomed size, so every mouse coordinate maps 1:1 to a pixel regardless of zoom.
- **Undo/redo:** snapshot‑based `History` (up to 50 steps).
- **Flood fill:** scanline fill with a `visited` array (prevents re‑scan loops under non‑zero tolerance) and RGBA distance matching.
- **Transparency:** transparent drawing uses `.clear` compositing; the canvas composites the bitmap with explicit `.sourceOver` over a checkerboard so alpha reads correctly and PNG export keeps it.

---

## License

Released for educational and personal use. "Microsoft Paint" and "Windows" are trademarks of Microsoft Corporation; this project is an independent re‑creation and is not affiliated with or endorsed by Microsoft.

---

<div align="center">
Built with Swift &amp; AppKit · 🎨
</div>
