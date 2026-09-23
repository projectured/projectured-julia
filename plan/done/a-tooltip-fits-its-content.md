# A tooltip fits its content

**Status (2026-09-23): DONE.** Landed on `main` at `4624140f`, and the owner
checked it in the binary. Nothing is pushed. The owner asked on 2026-09-22 for a
tooltip that fits what it holds, between a minimum and a maximum.

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

**Done, 2026-09-22**, in the worktree `workspace/projectured-julia-tooltip-fit`
on branch `tooltip-fit`, cut from `main` at `1b8cb64d`.

- [x] Measured on `main` the same day: `test_sdl()` **97**, `test_shell()`
      **178**, `test_application()` **127**, `test_substrate()` **63059** with
      3 fail, 2 error, 1 broken. The screen has no suite of its own; its tests
      sit in the substrate and the projectured suites.
- [x] The main window's own sizing, which this plan must not touch. The
      display's work area is 1853 × 1168; the window asks for that, the window
      manager grants **1853 × 1131** — it keeps the title bar inside the work
      area — and `open_native_windows!` writes that size into the document.
- [x] What the printed canvas of a tooltip reports. The content is the name of
      a toolbar button, and a long text in the same window:

      | Content | Offer | Canvas |
      | --- | --- | --- |
      | one line | 420 × 120 | 370 × 40 |
      | one line | 560 × 400 | 430 × 20 |
      | one line | 200 × 60 | 200 × 60 |
      | a long text | 560 × 400 | 560 × 160 |
      | a long text | 420 × 120 | 420 × 200 |

      **The canvas answers the content, not the offer.** The text wraps at the
      offered width, and the height follows the lines it took: one line is 20
      high at an offer of 560 and 40 high at an offer of 420, where it wraps in
      two. A canvas that is as wide as the offer is a text that filled the
      width, and its height still answers the content — 200 at an offer of 120.
      So the plan holds: offer the maximum, take the extent, clamp it.

### Step 1 — a window says its bounds

**Done.** `WindowDocument` and `OpenWindowOperation` carry the two fields.

- [x] `minimum_size` and `maximum_size` on `WindowDocument`, both `(0, 0)` by
      default, and on `OpenWindowOperation`; `_apply_open!` and
      `_update_window!` of `WindowManaging.jl` copy them.
- [x] **The mirror builds its window by keyword.**
      [ScreenToScreen.jl:81](../../source/screen/ScreenToScreen.jl#L81) builds
      the output window with twelve positional arguments. Two more fields shift
      them, and `x`, `y`, `width` and `height` are all `Int`, so a shifted
      argument would mis-size the main window with no error. Every other place
      that builds a window already uses keywords.
- [x] A `WindowDocument` is a saved type (`register_pred_type!`), so a user
      interface saved before this change must still load, with the two new
      fields at their default.
- [x] The screen has no suite of its own, so the three cases went to the
      substrate suite as `test_window_fit()`, in
      `test/substrate/projection/WindowFitTest.jl`: the mirror keeps the id,
      the title, the position, the size, the bounds, the style and the
      dismissal of its input; a window opened without the bounds keeps its
      size; a window saved before the change loads with the bounds at `(0, 0)`.

### Step 2 — the screen offers the maximum

**Done.** The offer is two computed cells, so it stays reactive: the maximum
when the window has one, and the window's own size otherwise.

- [x] `ScreenToScreen`: the content of a window that fits is printed with
      `maximum_size` as the available extent.
- [x] The offer is proven where it shows: in `test_application()`, the canvas
      of a tooltip that holds one line is narrower and shorter than the
      maximum, which it could not be if the offer were the window's size.

### Step 3 — the backend fits the window

**Done**, as `_fit_window_size!(w, canvas)`, which the reconciler calls before
it opens or updates a window. Only a size that changed is written, because an
equal write would invalidate the cell the mirrored window shares on every frame.

- [x] The fit, and the write-back into the `WindowDocument`.
- [x] Tests in the SDL suite: the content's size, the maximum, the minimum, and
      a window with no maximum keeping its size.

### Step 4 — the window stays on the screen

**Done.** `_place_fitted_window!` reads the work area and the pointer from the
backend, and `compute_window_place` is the rule itself, which takes both as
arguments, so a test needs neither a display nor a pointer it can not move.

- [x] The placement, and its five cases in the SDL suite.

### Step 5 — the tooltip asks to fit

**Done**, with `minimum_size = (120, 32)` and `maximum_size = (560, 400)`.

- [x] `TooltipProbeProjection` takes the two in place of `size`.
- [x] `test_tooltip_probe()`: the window carries the bounds.
- [x] `test_application()`: the canvas of a tooltip of one line is inside the
      bounds and smaller than the maximum. The size itself is given by a
      backend, and the application suite runs without one, so the SDL suite
      holds the sizes.

### Step 6 — the main window is unharmed

- [x] `test_native_window()`: the main window still asks for the work area,
      takes what the window manager grants — 1853 × 1131 of a work area of
      1853 × 1168, as in Step 0 — and writes that size into its document.
- [x] The suites, with the change: `test_sdl()` **106** (97 and 9 new),
      `test_shell()` **180** (178 and 2), `test_application()` **140** (136 on
      `main` the same day and 4), `test_substrate()` **63087** with the known 3
      fail, 2 error and 1 broken of the split-pane cases.
- [x] By hand, in the binary, 2026-09-23: the owner checked the window and the
      tooltip, and both are right.

### Step 7 — the guides, and close

- [x] `screen.md`: a window says its bounds, and the content of a window that
      fits is printed at its maximum. `sdl.md`: the backend fits such a window
      and keeps it on the screen. `tooltip.md`: the tooltip's bounds.
- [x] Move this plan to `plan/done/`.

## 4. Risks

| Risk | What is done about it |
| --- | --- |
| A content that fills the offer rather than shrinking to its own extent. Then every tooltip is the maximum. | Step 0 measures it before anything is built. If a content fills, the plan needs a layout that shrinks to its content, and that is a bigger change than this plan. |
| The size that is written back changes the next offer, and the window oscillates. | The offer of a fitting window is always its maximum, never the size it settled on. |
| Two new fields change the positional constructor of a `@document` struct, and the screen builds the mirrored window positionally. A shifted `Int` would mis-size the main window silently. | Step 1 turns that one call into a keyword call, and the screen suite asserts that the mirror keeps the size, the position and the title. |
| A saved user interface holds windows, so a new field changes the schema. | Step 1 loads a file saved before the change and asserts the defaults fill in. |
| A window that a person resizes and that also fits. | Only a window with a maximum fits, and no window a person resizes has one. A resize of such a window is a fault to report, not to handle. |
| The help window and the command palette could fit too. | They keep their fixed size in this plan. They gain the bounds when someone asks for it. |
