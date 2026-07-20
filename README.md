# FigureLab

A figure-layout and annotation editor for scientific publishing, built as a single
self-contained HTML file plus a tiny native macOS shell.

It exists because assembling a journal figure usually means bouncing between
Photoshop and Illustrator for what is, in the end, a small set of operations:
place some panels, crop them, draw a few arrows, label them, and export at the
resolution the journal demands. FigureLab does exactly those things, reads the
PSD and AI files the source material actually comes in, and always exports with
the print resolution written into the file.

No build step, no dependencies to install, no network access. Open the HTML file
in a browser, or run the macOS app.

---

## Features

### Reading what you already have

- **Photoshop (`.psd`, `.psb`)** — parsed in-browser, since browsers cannot decode
  PSD natively. Handles 8/16/32-bit, RGB / Grayscale / CMYK, raw and RLE
  compression. On import you can either flatten the file or **split it into its
  individual layers**, each becoming a separately selectable, movable object with
  its original layer name. The document's own resolution (image resource 1005) is
  read, so a 300 ppi A4 file arrives as 2480 × 3508 px at exactly 210 × 297 mm.
- **Illustrator / PDF (`.ai`, `.pdf`)** — modern `.ai` files are PDF documents, so
  they are rasterised at print resolution with a bundled copy of pdf.js and
  trimmed of the artboard's empty margin.
- **Ordinary images** — PNG, JPEG, TIFF, WebP, by file picker, drag-and-drop, or
  paste from the clipboard.

### Layout

- Layer panel listing every object: click to select, drag to reorder, double-click
  to rename, toggle visibility.
- Alignment (left / centre / right / top / middle / bottom) against the canvas for
  a single object, or against the selection when several are chosen, plus
  distribute-evenly for three or more.
- **Smart guides** while dragging: objects snap to each other's edges and centres
  and to the canvas, with a guide line showing what was matched. Hold `Alt` to
  suspend.
- Crop a single image, or **crop the whole canvas**, or trim the empty margin
  around all content.
- Multiple documents open at once as **tabs**, each with its own canvas, layers,
  view and undo history.

### Drawing and annotation

- Lines, arrows, rectangles, ellipses, freehand, and multi-point curves.
- **Editable nodes.** Draw a straight line, then double-click it to add nodes
  anywhere along it and pull them into arcs — several nodes make an S-curve.
  Rectangles and ellipses can be **converted to paths** so their outlines gain the
  same treatment. Corner nodes (square handles) keep straight edges perfectly
  straight, so bending one side of a rectangle does not round off the others.
- Arrowheads on either end of any line or curve, with adjustable size.
- Dashed and dotted strokes with independent dash length and gap.
- **Corner radius** on rectangles: drag the corner widget on the canvas, or type
  an exact radius.
- Text with font family, size, weight, style and colour.

### Image editing

- **Background removal** by colour, either one-click white removal or
  eyedropper-picked. Tolerance, edge feathering and edge shrink are adjustable.
  By default only the *contiguous outer* region is removed, so white areas inside
  a chart — axis backgrounds, gaps between bars, the counters of letters — are not
  punched through.
- **Puppet warp.** Pins are placed over an image and dragging one bends the
  picture smoothly around it, using Moving Least Squares rigid deformation.
  Pins can be added anywhere with `Alt`-click, which a fixed lattice cannot do;
  pins left alone act as anchors that hold their region still.

### Export

Every raster format carries the real print resolution, so journals see 300 ppi
rather than the browser's default 72.

| Format | Resolution metadata |
| ------ | ------------------- |
| PNG    | `pHYs` chunk |
| JPEG   | JFIF density fields |
| TIFF   | `XResolution` / `YResolution`, Deflate-compressed |
| PDF    | MediaBox in points, so the page measures correctly |
| SVG    | width/height in millimetres |

Resolution is chosen in ppi (150 / 300 / 600 / 1200) rather than as a multiplier,
and the panel shows the resulting pixel dimensions and physical size before you
export. Anything below 300 ppi is flagged.

New documents can be started at A4 or A3 in either orientation, at single- or
double-column journal widths, or at a custom size in millimetres.

---

## Running it

### In a browser

Open `figure-editor.html`. That is the whole application — one file, no server,
no installation. Work is auto-saved to the browser's local storage; "Save project"
writes a `.json` containing every tab for backup.

### As a macOS app

```bash
mac-app/build.sh
open FigureLab.app
```

The build produces a universal (Apple Silicon + Intel) `.app` of about 2 MB. It is
a native `WKWebView` shell — not Electron — so it carries a real menu bar, native
open/save dialogs, clipboard integration and trackpad pinch-to-zoom.

Requires the Xcode command line tools (`xcode-select --install`). The app is
ad-hoc signed, so a copy sent to someone else will need right-click → Open the
first time.

---

## Layout of the repository

```
figure-editor.html   the entire editor, including an inlined copy of pdf.js
mac-app/
  main.swift         the native shell: window, menus, file panels, pinch zoom
  build.sh           compiles the binary and assembles FigureLab.app
  icon.html          the app icon, rendered to PNG and then to .icns
  icon-1024.png      rendered icon source
```

`FigureLab.app` is a build artifact and is not tracked.

---

## Notes on the implementation

Everything runs client-side with no external dependencies, with one exception:
pdf.js is inlined into the HTML (together with its worker, as a same-page script)
so that `.ai` and `.pdf` import works offline and under a strict content security
policy. That accounts for almost all of the file's size.

A few pieces were worth building carefully:

- **PSD layers** are validated by recompositing the parsed layers and comparing
  against Photoshop's own flattened image; they agree to within 0.015 % of pixels.
- **TIFF** uses Deflate rather than a hand-written LZW packer, and decodes
  byte-identically to the PNG export.
- **Mesh warp** reduces exactly to the identity when no pin has been moved, so
  entering and leaving the tool never degrades an image.
- **Corner nodes** collapse the spline tangent on their side, which is what makes
  a converted rectangle stay a true rectangle.

## Limitations

- Imported `.ai` and `.pdf` artwork becomes a high-resolution raster, not editable
  vector paths.
- Mesh warp is baked into the image when applied; the pins cannot be recovered
  afterwards (undo still works).
- PSD import reads the composited layer content, so files must be saved from
  Photoshop with "Maximize Compatibility" enabled.
- PDF export embeds a raster at the chosen resolution rather than vector artwork.
