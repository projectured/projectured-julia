# The font zoom of each editor

The rule PAR-PER-EDITOR-STATE says: "No process-global state in the editor or the
machinery it drives; one process must run many editors at once." Layout reads
the font zoom, so PAR-NO-PROJECTION-GLOBALS applies too: "No global mutable
state in projections (or the machinery they call)."

The device audit (`plan/done/device-layer-audit.md`) moved the uniform zoom
(Ctrl+= and Ctrl+-) into the `Display` of each editor. The font zoom (Ctrl+Alt+=
and Ctrl+Alt+-) is still one value for the whole process. The owner asked for a
plan on 2026-09-25. This plan gives the facts and the options. The owner
chooses the design before the work starts.

The owner deferred this plan on 2026-09-25, before choosing an option.

## The facts

`_FONT_ZOOM` is a `Cell(1.0)` in `source/style/Font.jl`. It is a cell because
layout reads it: a change must lay out the text again.

- **The writer.** `adjust_font_zoom!(delta)` steps it with `step_zoom`. The SDL
  backend calls it in `evaluate_operation(editor, ::AdjustFontZoomOperation)`,
  then sets `editor.iomap = nothing`, so the editor projects again. The widgets
  measure their text while they print and keep the sizes, so only a new
  projection fits their boxes to the new text size.
- **The readers.** `font_logical_size(font)` and `font_device_size(font, ratio)`
  multiply `font.size` by it. Layout calls `font_logical_size` in 15 places in
  7 files of 6 packages:

  | File | Where |
  | --- | --- |
  | `source/text/TextToGraphics.jl` | 5 places: the rows, the columns and the band height of the text geometry |
  | `source/style/TrueType.jl` | 3 places: `measure_truetype_text`, the font metrics, the glyph bounds |
  | `source/graphics/GraphicsCaching.jl` | 2 places: the bounds, and the read of a cached image |
  | `source/graphics/GraphicsDocument.jl` | 2 places: the hit test, and the bounds of an element |
  | `source/pdf/Pdf.jl` | 1 place: `paint_text!` |
  | `source/web/Web.jl` | 1 place: the draw list sent to the browser |
  | `source/sdl/Sdl.jl` | 1 place: the measure of an empty text |

- **No reader has a printer context.** They get an element, a font, or a text
  and a font. `measure_truetype_text(text, font)` is the default text measure,
  and 29 files in 20 packages pass a measure of the form `(text, font)`.
- **The tests.** `PdfTest.jl` calls `adjust_font_zoom!` twice. Five tests call
  `font_logical_size`.

**The web backend.** The owner wants many editors in one process mainly with
the web backend. Each `WebBackend` holds its own server, port, connection and
windows, and `Web.jl` has no module-level mutable value. So the font zoom is the
state that web editors still share:

- The web layout measures with `measure_truetype_text`, which reads the font
  zoom.
- Only the SDL package evaluates `AdjustFontZoomOperation`. The fallback
  `evaluate_operation(editor, op)` in `OperationDefaults.jl` does nothing. So in
  a process with only the web backend, Ctrl+Alt+= does nothing. With the SDL
  package loaded, it changes the font zoom of every editor, web editors too.

**The fault.** With two editors in one process, Ctrl+Alt+= in one editor
changes the cell that the layout of both reads. The other editor lays out its
text at the new size at its next frame. It does not project again, so the text
can grow out of its widget boxes. An export with `write_image` in the same
process also uses the zoom of the last editor that zoomed.

## The options

### (A) A scoped value for each frame

The editor holds its own font zoom cell. The editor loop binds that cell in a
scoped value for each frame, as it binds the performance counters now
(`with_performance_counters` in `EditorLoop.jl`). `font_logical_size` reads the
cell that the frame binds. Outside a frame it reads a constant cell of `1.0`, so
a test or an export that is not in an editor gets no zoom.

- The 15 readers and the measure contract do not change.
- The binding must cover every place where the cells of an editor compute:
  `run_frame!` and the first print of `make_editor`. The rule PAR-STORE-THEN-DRAIN
  already keeps the cells of an editor out of other tasks.
- A cell computed in one frame depends on the zoom cell of that editor, so a
  change of the zoom invalidates only the layout of that editor.
- The scoped value is a new mechanism for a value that belongs to an editor.
  The counters use it for a value that belongs to a frame.
- Decisions inside (A):
  - **Where the cell lives.** On the `Display`, beside the uniform `zoom`. The
    `Display` is sealed, so this needs permission for `Display.jl`. Or on the
    `Editor`, which is not sealed.
  - **Where the scoped value is declared.** In the layer of that owner, so the
    style package reads it and the editor loop binds it.
  - **Who evaluates the operation.** The kernel editor can evaluate
    `AdjustFontZoomOperation` for every backend, because it only writes the
    cell and clears `editor.iomap`. Then the web backend gets the font zoom
    too. The SDL backend keeps only its full repaint.
- The size is about 60 lines in the style package, the kernel editor and the
  SDL backend, and a test with two editors.

### (B) The zoom as an argument

The zoom comes in through the printer context, as the clock does, and each
projection passes it down to the place where it measures or lays out text.

- The measure contract changes from `(text, font)` to one that carries the zoom,
  or each projection passes a font whose size is already zoomed.
- It touches the 15 readers and the 29 files that pass a measure, in 20
  packages.
- Nothing is hidden, but the change is large, and each new projection that
  draws text must remember the zoom.

### (C) One font zoom for the process, as a written exception

The font zoom stays a setting of the person at the machine, the same for every
editor, as the font size of an operating system is. The rule gets a named
exception. For the fault above, the operation must then project every editor
again, which needs a list of the live editors: a second process-global value.
This option keeps the code, but it breaks the requirement that one editor's
activity must not disturb another's.

My recommendation is (A), with the cell on the `Editor` and the kernel editor
evaluating the operation. Then each web editor gets its own font zoom, with or
without the SDL package. The readers are spread over six packages and have no
context, and the loop already binds a per-frame scope. The decision is the
owner's.

## Steps

The steps depend on the option. For (A):

0. [ ] The baseline on main: `test_kernel()`, `test_substrate()`, `test_sdl()`,
   `PdfTest`, the web backend test, and the live-window check of the device
   audit with Ctrl+Alt+= (the note `live-window-pixel-compare`).
1. [ ] The owner of the cell, and the scoped value that the loop binds.
2. [ ] `font_logical_size` and `font_device_size` read the bound cell;
   `_FONT_ZOOM` and `adjust_font_zoom!` go.
3. [ ] The operation writes the cell of its editor.
4. [ ] Tests: two editors in one process, a font zoom in one, and the layout of
   the other stays as it was; the same with two web backends; an export outside
   an editor has no zoom.
5. [ ] Guides: `style.md`, `sdl.md`, and the rule text if it names the
   mechanism.
6. [ ] The check: the suites as on main plus the new tests, and the live window
   with Ctrl+Alt+= as on main.
