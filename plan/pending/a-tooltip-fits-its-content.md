# A tooltip fits its content

**Status (2026-09-22): READY.** Nothing is implemented. The owner asked on
2026-09-22 for a tooltip that fits what it holds, between a minimum and a
maximum.

**Goal:** a window that asks to fit takes the size of its printed content,
between its minimum and its maximum, and it stays on the screen. A tooltip asks
to fit, so a short one is small and a long one wraps instead of being cut.

**Repositories:** projectured-julia only.

## 1. What is wrong

A tooltip window is always 420 × 120. That is the `size` keyword of
`TooltipProbeProjection` ([source/tooltip/TooltipProbe.jl:65](../../source/tooltip/TooltipProbe.jl#L65)),
which the probe passes as the width and the height of its `OpenWindowOperation`.
Nothing measures the content. A short tooltip leaves empty space, a long one is
cut off, and the window can run off the right or the bottom edge of the screen,
because the probe places it at the pointer plus `offset = (16, 20)` and nothing
checks the edge.

A menu and a select popup do fit, because the widget layer makes them and knows
its rows: it passes the widest item plus 16, and the row height times the number
of rows ([source/widget/WidgetToGraphics.jl:1533](../../source/widget/WidgetToGraphics.jl#L1533)).
A tooltip holds a document of any domain, and the rows that draw it are the
`opened_window_projections` of `run_window_editor`, which the probe never sees.
So the probe can not measure, and the measure belongs where the content is
printed.

## 2. Decisions

- **A window says its bounds, not its size.** `WindowDocument` gets
  `minimum_size` and `maximum_size`. A window whose `maximum_size` is `(0, 0)`
  keeps the fixed size it has today, so every window that exists now is
  unchanged. `OpenWindowOperation` mirrors the two fields, as it mirrors the
  schema of a window.
- **The screen offers the maximum.** `ScreenToScreen` prints the content of a
  window with the window's size as the available extent. For a window that
  fits, it offers `maximum_size` instead, always. So prose wraps at the maximum
  width, and the offer never follows the size that the content settled on.
- **The backend takes the size from the printed canvas.** The content of a
  window is a `GraphicsCanvas`, which carries `w` and `h`. The reconciler reads
  them, clamps them between `minimum_size` and `maximum_size`, and makes or
  resizes the native window at that size. It writes the size back into the
  `WindowDocument`, as `open_native_windows!` writes back the size a window
  manager grants. The window is still painted before it is shown, so the first
  frame a person sees already has the right size.
- **The backend keeps such a window on the screen.** A window that would cross
  the right or the bottom edge of the work area is moved inside it. When the
  moved window would then sit under the pointer, it goes to the other side of
  the pointer. The backend knows both the work area and the pointer.
- **The tooltip asks to fit.** `TooltipProbeProjection` loses `size` and takes
  `minimum_size = (120, 32)` and `maximum_size = (560, 400)`.

Names, checked against `naming-rules.md`:

| Name | What it is |
| --- | --- |
| `minimum_size`, `maximum_size` | fields of `WindowDocument` and of `OpenWindowOperation`, each a `(width, height)` |
| `compute_fitted_window_size(w, canvas)` | the size a fitting window takes: the canvas extent, clamped between the two |
| `_place_window_on_screen!(res, w)` | moves a fitting window inside the work area, and off the pointer |

## 3. Steps

### Step 0 — baselines, and what a canvas reports

- [ ] `test_sdl()` 97, `test_shell()` 178, `test_application()` 127,
      `test_substrate()` 63059 with 3 fail, 2 error, 1 broken, `test_screen()`.
- [ ] The main window's own sizing, which this plan must not touch: what
      `run_window_editor` asks for, what `open_native_windows!` writes back
      after the window manager answers, and the size the document holds after
      the first frame. Write the numbers here, and read them again at the end.
- [ ] Measure, in the application window with the tooltip on: the `w` and `h`
      of the printed canvas of a tooltip that holds one line, and of one that
      holds a docstring, at the offer of today (420 × 120) and at an offer of
      560 × 400. **The whole plan stands on this**: a content that fills the
      offer instead of shrinking to its own extent would always come back as
      the maximum. Write the numbers here.

### Step 1 — a window says its bounds

- [ ] `minimum_size` and `maximum_size` on `WindowDocument`, both `(0, 0)` by
      default, and on `OpenWindowOperation`; `_apply_open!` and
      `_update_window!` of `WindowManaging.jl` copy them.
- [ ] **The mirror builds its window by keyword.**
      [ScreenToScreen.jl:81](../../source/screen/ScreenToScreen.jl#L81) builds
      the output window with twelve positional arguments. Two more fields shift
      them, and `x`, `y`, `width` and `height` are all `Int`, so a shifted
      argument would mis-size the main window with no error. Every other place
      that builds a window already uses keywords.
- [ ] A `WindowDocument` is a saved type (`register_pred_type!`), so a user
      interface saved before this change must still load, with the two new
      fields at their default.
- [ ] Tests in the screen suite: a window opened without the two fields is
      sized as it is today; the mirrored window keeps the id, the title, the
      position and the size of its input; an old saved interface loads.

### Step 2 — the screen offers the maximum

- [ ] `ScreenToScreen`: the content of a window that fits is printed with
      `maximum_size` as the available extent.
- [ ] Test: the offer of a fitting window is its maximum, and the offer of
      every other window is its size.

### Step 3 — the backend fits the window

- [ ] `compute_fitted_window_size`, and the reconciler uses it when it opens a
      window and when it updates one.
- [ ] The fitted size is written back into the `WindowDocument`.
- [ ] Tests in the SDL suite: a window with a small content gets the content's
      size; one with a content larger than the maximum gets the maximum; one
      with a tiny content gets the minimum; a window with no maximum keeps its
      size.

### Step 4 — the window stays on the screen

- [ ] `_place_window_on_screen!`: inside the work area, and off the pointer.
- [ ] Tests in the SDL suite, with the work area of the display: a window asked
      for beyond the right edge ends inside it, and does not hold the pointer.

### Step 5 — the tooltip asks to fit

- [ ] `TooltipProbeProjection` takes `minimum_size` and `maximum_size` in place
      of `size`, and passes them.
- [ ] `test_tooltip_probe()` and `test_widget_tooltip()`: the operation carries
      the bounds.
- [ ] `test_application()`: a tooltip of one line is smaller than a tooltip of
      a docstring, and neither is the old fixed size.

### Step 6 — the main window is unharmed

- [ ] `test_native_window()`: the main window still asks for the work area,
      takes what the window manager grants, and writes that size into its
      document. The numbers of Step 0 hold.
- [ ] `test_application()` and `test_shell()`: unchanged counts.
- [ ] By hand, in the binary: the window opens at its size, a resize by the
      person still resizes the content, and the tooltip fits.

### Step 7 — the guides, and close

- [ ] `screen.md`: a window says its bounds, and the content of a window that
      fits is printed at its maximum. `sdl.md`: the backend fits such a window
      and keeps it on the screen. `tooltip.md`: the tooltip's bounds.
- [ ] Move this plan to `plan/done/`.

## 4. Risks

| Risk | What is done about it |
| --- | --- |
| A content that fills the offer rather than shrinking to its own extent. Then every tooltip is the maximum. | Step 0 measures it before anything is built. If a content fills, the plan needs a layout that shrinks to its content, and that is a bigger change than this plan. |
| The size that is written back changes the next offer, and the window oscillates. | The offer of a fitting window is always its maximum, never the size it settled on. |
| Two new fields change the positional constructor of a `@document` struct, and the screen builds the mirrored window positionally. A shifted `Int` would mis-size the main window silently. | Step 1 turns that one call into a keyword call, and the screen suite asserts that the mirror keeps the size, the position and the title. |
| A saved user interface holds windows, so a new field changes the schema. | Step 1 loads a file saved before the change and asserts the defaults fill in. |
| A window that a person resizes and that also fits. | Only a window with a maximum fits, and no window a person resizes has one. A resize of such a window is a fault to report, not to handle. |
| The help window and the command palette could fit too. | They keep their fixed size in this plan. They gain the bounds when someone asks for it. |
