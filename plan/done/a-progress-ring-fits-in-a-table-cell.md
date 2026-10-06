# A progress ring fits in a table cell

> **Status:** done. Implemented on 2026-10-06 on the branch `progress-ring` of
> projectured-julia, omnet-julia and inet-julia. The owner looked at the two
> examples in a real window (step C5) and approved the landing on main the same
> day. The measurement of the CPU time of a turning spinner is not done.
> Section 7 holds what the implementation found and decided.

## 1. The request

The owner wrote on 2026-10-06:

> I would like to have circular progress indicator widget in projectured-julia,
> what do you suggest? it would fit much better in table cells for example

The owner answered the first proposal:

> 1, separate WidgetProgressRing and rename WidgetProgress to WidgetProgressBar
> 2, now
> 3, yes

- **1** is about the shape of the change. The ring is a separate widget
  type, `WidgetProgressRing`. The bar that exists now gets the name
  `WidgetProgressBar`.
- **2** is about the spinner for unknown progress. It is part of this plan.
- **3** is about the angles of `GraphicsArc`. They are in degrees, 0 is at
  the top, and a positive angle goes clockwise.

The owner answered the questions of section 5 on the same day:

> for 1, use 0.2.0
> for 2, agreed
> for 3, agreed
> for 4, similar to a rotating 90 arc, it's a 1/4 segment shifting from start to end

## 2. Summary

The plan has three parts:

- **Part A** gives `WidgetProgress` the name `WidgetProgressBar`, together
  with the names that come from it, in projectured-julia and in omnet-julia.
- **Part B** adds a graphics primitive, `GraphicsArc`: a stroke along a part
  of a circle. The SDL, PDF and web backends draw it.
- **Part C** adds `WidgetProgressRing`. It shows a value from zero to one as
  an arc on a ring. If the value is `nothing`, an arc turns around the ring.
  The ring is as tall as a line of text, so a table row that holds it is not
  taller than a row of text.
- **Part C** also gives the bar a value of `nothing`. Then a segment of a
  quarter of the track moves from the start to the end.

The spinner needs no new mechanism. Every printer gets the clock of the
editor through `ctx.clock`, and a cell that reads the clock ticks once a
frame.

## 3. Facts

### 3.1 The bar that exists now

- The document is `WidgetProgress`
  ([WidgetDocument.jl:1786](../../source/platform/widget/WidgetDocument.jl#L1786)),
  with the fields `position`, `value::Float64`, `width`, `visible`, `margin`,
  `border`, `padding`, `style` and `tooltip`. `_make_share_cell` turns a
  number, a cell or a function into the value cell.
- The printer is `WidgetProgressToGraphicsCanvas`
  ([WidgetToGraphics.jl:7029](../../source/platform/widget/WidgetToGraphics.jl#L7029)).
  It draws two `GraphicsRect`s, the track and the filled part. Its row in the
  dispatch table is at
  [WidgetToGraphics.jl:10746](../../source/platform/widget/WidgetToGraphics.jl#L10746).
- The style is `WidgetProgressStyle`
  ([WidgetStyle.jl:265](../../source/platform/widget/WidgetStyle.jl#L265)),
  with `track_color` and `indicator_color`. A printer finds a style color by
  the name of the field, not by the type of the style. So any style that has
  these two fields can color the bar and the ring.
- The theme field is `progress_height`
  ([WidgetTheme.jl:179](../../source/platform/widget/WidgetTheme.jl#L179)).
- `ProjecturedPlatform` exports `WidgetProgress` and `WidgetProgressStyle`
  ([WidgetModule.jl:100](../../source/platform/widget/WidgetModule.jl#L100)).
  `ProjecturedAll` exports them again. The umbrella `Projectured` does not
  export them.
- `:WidgetProgress` is in the vocabulary of the assistant, `make_interface_api`
  ([PaneProgram.jl:124](../../source/platform/pane/PaneProgram.jl#L124)).

### 3.2 Where the old name occurs

- **projectured-julia**, 41 written lines in these places:
  - source: the files of section 3.1
  - examples: [WidgetDocumentExample.jl:61, 481-483](../../example/platform/WidgetDocumentExample.jl#L481),
    [PlatformExamples.jl:84, 159, 239](../../example/platform/PlatformExamples.jl#L84),
    [ProjecturedExamples.jl:22](../../example/projectured/ProjecturedExamples.jl#L22),
    and the exports of `ProjecturedExample` and `ProjecturedPlatformExample`
  - tests: [WidgetLiveValueTest.jl:20, 51, 55](../../test/platform/projection/WidgetLiveValueTest.jl#L51),
    [WidgetColorTest.jl:129](../../test/platform/projection/WidgetColorTest.jl#L129)
  - documents: [widget.md:17, 55, 167](../../documentation/package/platform/widget/widget.md),
    [system-anatomy.md:250](../../documentation/design/system-anatomy.md),
    [feature-video-screenplays.md:328, 745](../pending/feature-video-screenplays.md)
- **projectured-julia**, 37 generated lines in `package/*/precompile/examples.txt`.
  AutoPrecompile reads these lines, and the recording `"examples"` writes them
  ([ReplStatementFiles.jl](../../source/tool/repl/ReplStatementFiles.jl)).
- **omnet-julia** uses the old name in these places:
  - 8 constructor calls and 8 import lines
  - 9 test assertions in 4 files
  - [legacy-simulation.md](../../../omnet-julia/documentation/package/legacy/legacy-simulation.md)
  - 2 pending plans
  - 38 generated lines in `asset/precompile/PrecompileStatements.jl`

  None of the bars is in a `WidgetTable`. Each one is in a `FormLayout`, in a
  `HorizontalLayout`, or alone.
- **inet-julia** has the old name only in 25 generated lines of
  `asset/precompile/PrecompileStatements.jl`.
- **Projectured.jl** is the release copy. The release generator writes it, so
  nobody edits it by hand.
- **projectured.github.io** and **ProjecturedRegistry** do not use the name.

### 3.3 The release

- 0.1.0 is released through ProjecturedRegistry and is announced.
- Rule 3 of R11 in
  [release-the-binary-and-the-packages.md](../pending/release-the-binary-and-the-packages.md)
  gives a changed package a patch step (`0.1.0` → `0.1.1`).
- A user with `[compat] ProjecturedPlatform = "0.1"` gets 0.1.1 at `pkg> up`.
  A removed exported name is a breaking change, so the code of that user can
  stop working. Question Q1 is about this.
- A saved appearance file names each theme field. The loader ignores a key
  that it does not know
  ([Appearance.jl:284](../../source/platform/style/Appearance.jl#L284)).
  So after the rename of `progress_height`, a value that a user saved for it
  goes back to the default. Nothing fails.

### 3.4 The clock

- Each `PrinterContext` has the field `clock`
  ([PrinterContext.jl:57](../../source/kernel/projection/PrinterContext.jl#L57)).
  The root context gets the clock of the editor.
- `run_editor!` writes the clock once a frame
  ([EditorLoop.jl:217-219](../../source/kernel/editor/EditorLoop.jl#L217)).
- `compute_wait_timeout` lets the loop sleep for `FRAME_INTERVAL` (0.01
  seconds) while a cell reads the clock. When no cell reads it, the loop
  sleeps until the next input
  ([Feeds.jl](../../source/kernel/editor/Feeds.jl)).
- `get_reactive_clock_time(clock)` reads the time and records a dependency.
  `get_clock_time(clock)` reads it and records no dependency
  ([Clock.jl](../../source/kernel/clock/Clock.jl)).
- No printer in projectured-julia reads `ctx.clock` now. The ring is the
  first one. A printer in omnet-julia reads it, `PacedClockLabel`
  ([PacedClockLabel.jl](../../../omnet-julia/source/presentation/control/PacedClockLabel.jl)),
  and it reads the clock only while a pace is active. The ring follows the
  same rule: it reads the clock only while it spins.
- The SDL backend repaints only the rectangles of the graphics whose cells
  changed ([SdlBackend.jl:314-325](../../source/backend/sdl/SdlBackend.jl#L314)).
  So a spinner repaints only its own box on each frame.
- Rule `PAR-PER-EDITOR-STATE` in
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
  says: "every animated cell subscribes to the clock the printer context
  carries". The ring does this.

### 3.5 The graphics primitives

- No primitive draws a part of a circle. `GraphicsCircle` draws a full disc or
  a full ring. `GraphicsPolygon` takes integer points, and at 16 pixels an arc
  made of integer points has uneven edges.
- Every coordinate is `Int32`
  ([graphics.md:26](../../documentation/package/platform/graphics/graphics.md)).
  An angle is not a coordinate. So a `Float64` angle does not break this rule,
  but `GraphicsArc` is the first primitive with a `Float64` field.
- `@document` exports the type, so `GraphicsModule.jl` needs no change.
- A new primitive needs a branch in each of these places:
  - `_hit_test_element`
    ([GraphicsDocument.jl:774](../../source/platform/graphics/GraphicsDocument.jl#L774))
  - `extend_element_bounds!`
    ([GraphicsDocument.jl:961](../../source/platform/graphics/GraphicsDocument.jl#L961)).
    The layout, `get_graphics_size` and the dirty rectangles of SDL all read
    the bounds from this function.
  - `_dispatch_render_elem!` in SDL
    ([SdlBackend.jl:1839](../../source/backend/sdl/SdlBackend.jl#L1839))
  - `paint_elem!` in PDF
    ([PdfWriter.jl:468](../../source/backend/pdf/PdfWriter.jl#L468))
  - `_serialize_node` of the web backend
    ([WebBackend.jl:191](../../source/backend/web/WebBackend.jl#L191)), and
    `renderNode` in [client.js:390](../../asset/web/client.js#L390).
    `build/…/client.js` is a generated copy. Do not edit it.
- These places need no change:
  - the video backend and `write_image`, which draw through SDL
  - `GraphicsToGraphics`
  - the serialization
  - `show`
  - `LayoutToGraphics`
  - the layering guard and the naming guard
- SDL draws a polygon with float vertices in one `SDL_RenderGeometry` call
  (`_fill_polygon!`, [SdlBackend.jl:1610](../../source/backend/sdl/SdlBackend.jl#L1610)).
  The supersample of a live window, 2 by default, smooths the edges.
- PDF draws a ring with four Bézier curves and the constant `KAPPA`
  ([PdfWriter.jl:5](../../source/backend/pdf/PdfWriter.jl#L5), `_stroke_ring!`
  at line 257).

### 3.6 The size of a ring next to text

- The theme field `icon_size` gives the size of an icon as a part of the
  height of one line of text. A menu item sizes its icon so
  ([WidgetToGraphics.jl:2669-2672](../../source/platform/widget/WidgetToGraphics.jl#L2669)).
  The printer needs the text measure for this, as the button printer has it.
- The theme field `stroke` is the width of a checkmark, of the ring of a radio
  button and of the ring of a knob.

## 4. Design

### 4.1 The rename (Part A)

| old name | new name |
|---|---|
| `WidgetProgress` | `WidgetProgressBar` |
| `WidgetProgressToGraphicsCanvas` | `WidgetProgressBarToGraphicsCanvas` |
| `progress_height` (theme field) | `progress_bar_height` |
| `widget_progress_example`, `"widget_progress"` | `widget_progress_bar_example`, `"widget_progress_bar"` |
| `make_widget_progress_document_example` | `make_widget_progress_bar_document_example` |
| catalog key `"progress"` | `"progress_bar"` |
| `:WidgetProgress` in `make_interface_api` | `:WidgetProgressBar` |

`WidgetProgressStyle` keeps its name (Q2). It is the style of both progress
widgets.

The rename removes exported names of `ProjecturedPlatform`, so its next
release is 0.2.0 (Q1).

### 4.2 `GraphicsArc` (Part B)

```julia
GraphicsArc(cx, cy, radius; width = 1, start_angle = 0, sweep_angle = 360,
            color = color_black)
```

- `cx`, `cy` and `radius` are `Int32` pixels, as in `GraphicsCircle`. Each
  is a number, a cell or a function.
- `radius` is the outer radius. The stroke of `width` lies inside it. This is
  the ring of `GraphicsCircle(cx, cy, radius; border_width = width)`. So an
  arc covers its track exactly.
- `start_angle` and `sweep_angle` are `Float64` degrees. 0 is at the top, and
  a positive angle goes clockwise on the screen. Each is a number, a cell or a
  function, through a new helper `_make_angle_cell`. The helper does not round.
  The constructor keeps `sweep_angle` as it is given. Each backend and the
  hit test take a sweep of 360 or more as the full ring, and a sweep of 0 or
  less, or NaN, as nothing (section 7).
- The ends are flat.
- **Bounds:** the box of the full circle, not the box of the arc. Then the
  bounds of a spinner do not change from frame to frame, and the dirty
  rectangle is always the box of the ring.
- **Hit test:** the point is in the band between the two radii, and its angle
  is in the sweep.
- **SDL:** `_render_arc!` draws the band between the outer and the inner
  radius as a strip of triangles with float vertices, in one
  `SDL_RenderGeometry` call. The count of segments comes from the length of
  the arc in device pixels. A full sweep uses `_stroke_ring!`, as the circle
  does.
- **PDF:** `paint_arc!` strokes Bézier segments of 90 degrees or less at the
  radius `radius - width / 2`, with the line width `width`. Each segment uses
  the control length `4/3 · tan(θ/4) · r`. For 90 degrees this length is
  `KAPPA · r`.
- **Web:** `_serialize_node` writes `"t" => "arc"`. `drawArc` in `client.js`
  strokes `ctx.arc` with flat ends. The canvas measures an angle from 3
  o'clock, so the client subtracts 90 degrees and converts to radians.

### 4.3 `WidgetProgressRing` (Part C)

```julia
WidgetProgressRing(value = nothing; position, visible = true, margin = nothing,
                   border = nothing, padding = nothing, style = nothing,
                   tooltip = nothing)
```

- `value` is a share from 0 to 1, or `nothing` if the share is not known. It
  is a number, a cell, a function, or `nothing`. The field is
  `value::Union{Nothing, Float64}`.
- The ring has no `width`. Its diameter is one line of the text of the theme
  font, multiplied by the new theme field `progress_ring_size::IconSize =
  IconSize(1.0)`. The stroke is the theme field `stroke`, and the docstring of
  `stroke` gets the progress ring in its list.
- The ring authors no size. Its content is its diameter plus its insets, so
  an exact range from its parent stretches its box (`_resolve_width`,
  `_resolve_height`), and the ring stays at the start of the box and in its
  vertical middle. The checkbox was not the model: it sizes from its box and
  its label, and it does not stretch.
- The track is a `GraphicsCircle` ring with a transparent fill.
- The indicator is one `GraphicsArc` for the life of the ring. The canvas does
  not read the value; only the two angles of the arc read it. The sweep is
  `360 · clamp(value, 0, 1)`, or `360 · indeterminate_share` (90 degrees)
  while the value is `nothing`. The start is 0, or
  `360 · frac(get_reactive_clock_time(ctx.clock) / indeterminate_period)`
  while the value is `nothing`, so one turn takes 1 second.
- Only the start reads the clock, and only while the value is `nothing`. A
  tick invalidates the arc and nothing else, and the canvas does not run
  again. When the value becomes known, the backend draws the arc again, its
  start computes again without the clock, and the subscription ends. Section 7
  says why the arc must live as long as the ring. A ring with
  `visible == false` prints an empty canvas and does not read the clock.
- The style is the one of Q2. The printer reads `track_color` and
  `indicator_color` by name.
- The printer is `WidgetProgressRingToGraphicsCanvas`. It takes `measure`,
  as the button printer does, and it has no reader (`@_printer_only`).
- `indeterminate_share` (0.25) and `indeterminate_period` (1 second) are
  fields of the projection. They are not theme fields (Q3). The bar has the
  same two fields (4.4).

### 4.4 The bar for unknown progress (Part C)

- `WidgetProgressBar` takes `value = nothing` too, with the same signature as
  the ring: `WidgetProgressBar(value = nothing; position, width = 240, …)`.
  Its field becomes `value::Union{Nothing, Float64}`. Both widgets make the
  value cell with `_make_share_cell`, which gets a method for `nothing`. A
  function that returns `nothing` gives `nothing`.
- **No value:** a segment of `indeterminate_share` of the track, a quarter,
  moves from the start of the track to the end in `indeterminate_period`.
  Its start is `frac(get_reactive_clock_time(ctx.clock) / indeterminate_period)
  · length`.
- The part of the segment that passes the end of the track shows at the start
  of the track. So the visible part is always a quarter of the track, as the
  arc of the ring is always a quarter of the ring. The owner confirmed this
  (Q4). A segment that leaves at the end and enters again at the start, and so
  is shorter at the two ends, is not the design.
- Two `GraphicsRect`s with the radius of the track show the value for the
  life of the bar, as the arc does for the ring. Only their places and widths
  read the value. A known value fills the first from the start, and the second
  has the width 0 and draws nothing. While the value is not known, the first
  is the part of the segment before the end of the track and the second the
  part that passed the end, and only then do they read the clock. The bounds
  of a rectangle change from frame to frame, so the dirty rectangle of SDL
  covers the old and the new place. Both are in the box of the bar.
- A known value draws the same picture as before this plan.

## 5. Decisions of the owner

The owner decided each question on 2026-10-06. The options that were not
chosen stay here, so that the reason stays visible.

**Q1. How does the rename reach the users of 0.1.0?** Rule 3 of R11 gives
`ProjecturedPlatform` a patch step, but the rename removes the exported name
`WidgetProgress` and the theme field `progress_height`.

- **Decided: the next release gives `ProjecturedPlatform` the version
  0.2.0.** A removed name is a breaking change, and in 0.x a minor step says
  that. The generator applies only rule 3 now, so the release plan gets an
  item for a minor step (the step "Close").
- Not chosen: keep `WidgetProgress` for the 0.1 series with
  `Base.@deprecate_binding`. A theme keyword can not have such an alias, so
  `WidgetTheme(; progress_height = …)` stops working anyway.
- Not chosen: accept the break in a patch step.

**Q2. One style for both widgets.** Decided: `WidgetProgressStyle` keeps its
name and is the style of the bar and of the ring. The two widgets have the same
parts, a track and an indicator, so one style colors both. Not chosen: a
`WidgetProgressBarStyle` and a `WidgetProgressRingStyle`.

**Q3. The look of the spinner.** Decided: a fixed arc of 90 degrees that turns
once a second. Not chosen: an arc that grows and shrinks while it turns. The two
numbers are fields of the projection, not of the theme.

**Q4. The bar for unknown progress.** Decided: it is part of this plan. The
owner described it as "similar to a rotating 90 arc, it's a 1/4 segment shifting
from start to end". Asked if the segment wraps, the owner answered: "the segment
can be halfway at the end and at the start at the same time just like the 90
arc". Section 4.4 holds the design.

## 6. Steps

The work was done in the worktree `projectured-julia-progress-ring` and in a
branch `progress-ring` of omnet-julia and inet-julia, one commit for each step.
The SHAs are the ones after the rebase onto main (section 7).

### Part A — the rename

- [x] **A1. Rename in projectured-julia.** Done in `fb1141f20`: 20 files.
  `julia-rename.jl` renamed the identifiers, and a second pass by text renamed
  the docstrings, the symbol `:WidgetProgress`, the theme field and its read,
  the strings and the markdown. The generated statement files took an
  exact-token text pass. No code uses the generated variants
  (`ACWidgetProgress` and the others); only the statement files name them.
  - Checks: the naming guard, `Pkg.precompile()` with no undeclared binding,
    `test_widget_live_values()`, `test_widget_colors()`, and
    `test_example(widget_progress_bar_example)` with one failure that the base
    commit has too (section 7).
  - The task slice that main gained later makes its bar with the old name.
    `07d60b5a0` follows the rename there, after the rebase.
- [x] **A2. omnet-julia follows.** Done in omnet-julia `3ed4e90b`: 15 files,
  the 8 constructors, the 8 imports, the 9 test assertions, the comments,
  `legacy-simulation.md`, two pending plans and the 38 generated statements.
  - A throwaway environment in `/var/tmp` pointed omnet-julia at its branch and
    projectured-julia at its branch. `Pkg.precompile()` gave no undeclared
    binding. Seven test functions gave the counts of unmodified main
    (section 7).
- [x] **A3. inet-julia follows.** Done in inet-julia `28c50d9`: 32 generated
  lines of `asset/precompile/PrecompileStatements.jl`, among them
  `WidgetProgressMut`, a generated suffix that the planned regex did not
  reach. No other file of inet-julia names the widget. The replay skips a
  statement that names nothing, so an old file does not fail a build.

### Part B — `GraphicsArc`

- [x] **B1. The primitive.** Done in `a247ae4d7`: the document, the
  constructor, `_make_angle_cell`, `_is_point_on_arc`, the bounds, and
  [graphics.md](../../documentation/package/platform/graphics/graphics.md).
  `test_graphics()`: 13 checks in the testset `GraphicsArc`.
- [x] **B2. SDL.** Done in `e6a6f0c21`: `_fill_arc_band!` and `_render_arc!`.
  The pixel test in `GraphicsToFileTest.jl` reads an image with no supersample:
  10 checks, among them a full sweep that colors exactly the pixels of the ring
  of a circle.
- [x] **B3. PDF.** Done in `431eda471`: `paint_arc!`. Besides the smoke test,
  a testset checks the exact operators of a quarter arc, the segment count of
  200 degrees, a full sweep and an empty one.
- [x] **B4. Web.** Done in `42878e1e8`: the node `"arc"` and `drawArc`. The
  test checks the dictionary. No browser ran the client, and this machine has
  no `node` to check the syntax of `client.js`.

### Part C — the ring, and the bar for unknown progress

- [x] **C1. The ring.** Done in `8353fc722`. The test file has the name
  `WidgetProgressTest.jl` and the function `test_widget_progress()` since step
  C2, because it covers both widgets.
  - The first version made a new arc when the value changed, and the clock
    kept a reader after the value became known. The final design keeps one arc
    for the life of the ring (section 7).
- [x] **C2. The bar for unknown progress.** Done in `b7cf302b3`: two
  rectangles for the life of the bar. The test (9 checks) uses a bar of 200
  pixels and checks the places at the clock times 0, 0.5 and 0.875, that the
  same rectangle shows the known value 0.3, and that the subscription ends.
  - The plan asked to compare a bar with a known value with the bar of step A1.
    The elements are not the same: a second rectangle of width 0 is new, and it
    draws nothing and adds no bounds. The test checks the places instead.
- [x] **C3. The examples.** Done in `8389450e8`. The color probe reads the
  color of a `GraphicsArc` too, and `dd9d29301` skips an arc of no sweep there,
  as it skips a rect of no size.
  - `test_example(widget_progress_ring_example)` fails 154 checks: the known
    Home-key check, and 153 type-ins into the labels of its table. The
    unchanged `widget_table` example fails 333 type-ins of the same kind. No
    failure is in a ring.
  - `test_example(widget_progress_bar_example)` fails only the known Home-key
    check.
- [x] **C4. The documents.** Done in `369c34b48`: widget.md,
  system-anatomy.md and layout-rules.md. A review found that
  `tool/widget-images.jl` still named the old example; `435065fda` names the
  bar and the ring there.
- [x] **C5. The live check.** The owner looked at the two examples in a real
  window and accepted them on 2026-10-06.
  - The CPU measurement of a turning spinner is not done: it needs the word of
    the owner and an idle machine.

### Close

- [x] Add an item to
  [release-the-binary-and-the-packages.md](../pending/release-the-binary-and-the-packages.md):
  the next release gives `ProjecturedPlatform` the version 0.2.0 (Q1).
- [x] Move this plan to `plan/done/`.

## 7. What the implementation found and decided

**A reader lets go of the clock only when it computes again.** The cell engine
keeps the readers of a cell as `WeakRef`s, and a reader removes its edges only
when it computes again or is written
([ReactiveCell.jl](../../source/kernel/cell/ReactiveCell.jl), "the downstream
edge"). The first ring made a new arc in its canvas when the value changed. The
old arc was still a reader of the clock, so `has_dependent_cells` of the clock
time stayed true, and the editor would have woken every 10 milliseconds until
the garbage collector freed the old arc. So each widget keeps the same elements
for its whole life, and only their angles, places and widths read the value.
When the value becomes known, the backend draws them again, they compute again
without the clock, and the editor sleeps after the next frame. The tests check
the identity of the elements and the end of the subscription.

**The sweep of an arc is not limited when the arc is made.** A cell or a
function can give the angles, and a limit in the constructor would need a
second cell around each. Each backend and the hit test take a sweep of 360 or
more as the full ring and a sweep of 0 or less, or NaN, as nothing. The
docstring says so.

**The branch was rebased onto main.** omnet-julia main needs `TaskModule`,
which projectured-julia main gained after this branch started, so the legacy
packages of omnet-julia could not load against the branch. `git rebase
--autostash main` moved the branch onto `e9faed132` with no conflict.

**Measured on the machine.**
- `Pkg.instantiate()` of a fresh worktree of `environment/all` needs more than
  8 GB: the first run was killed at that cap, and a cap of 16 GB passed.
- The Home-key check at `NavigationTest.jl:180` fails for the example of the
  bar on the base commit `c223ac251` too. A throwaway worktree showed it.
- omnet-julia, the seven functions that hold the renamed assertions, branch
  against unmodified main: `test_sim_control_panel` 12/1 and 12/1,
  `test_sim_dashboard_panel` 34/2 and 34/2,
  `test_parallel_sim_dashboard_panel` 10/5 and 10/5,
  `test_sim_workbench_control_bar` 32/0 and 32/0, `test_simulation` 64/2 and
  64/2, `test_legacy_run` 39/0 and 39/0, `test_batch_widget` 25/0 and 25/0.
  The one failure of `test_sim_control_panel` is the timing check at
  `WatchExampleTest.jl:426`. It failed three times out of three on both, and an
  earlier run on main passed it.

## 8. Risks

- **A spinner keeps the editor awake.** While a document shows a ring or a bar
  with no value, the loop wakes every 10 milliseconds. A document that forgets to set
  the value keeps the CPU busy, and a `wait_for` of a video recording that
  waits for a quiet document never ends. This is the cost of every animation.
- **A ring that scrolled out of view still reads the clock.** A ring in a
  viewport stays printed when it is outside the visible part, so it keeps its
  subscription. A tab page that is not shown does not print its content.
- **A ring that is not drawn keeps an old edge.** When the value of a spinner
  becomes known while the ring is outside the clip, the backend does not draw
  the arc, so its start does not compute again and stays a reader of the clock
  until the ring is drawn again.
- **The track and the arc use different drawing paths in SDL.** The track
  uses rows of spans, and the arc uses triangles. Their edges can differ by
  less than one device pixel. Step B2 compares the pixels.

## 9. Out of scope

- Text in the ring. At 16 pixels there is no space for it. Use the next cell
  or the `tooltip`.
- Rings in the tables of omnet-julia. No bar there is in a table now.
