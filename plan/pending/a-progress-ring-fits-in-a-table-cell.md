# A progress ring fits in a table cell

> **Status:** pending. Written on 2026-10-06. Nothing is implemented. The owner
> decided the four questions on 2026-10-06 (section 5). The work starts when the
> owner asks for it.

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
    [feature-video-screenplays.md:328, 745](feature-video-screenplays.md)
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
  [release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md)
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
  The constructor limits `sweep_angle` to the range 0 to 360. An arc of 360
  degrees is a full ring.
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
- The box takes the range that its parent offers (`_resolve_width`,
  `_resolve_height`), as every widget does. The ring sits at the start of the
  box and in its vertical center, as the box of a checkbox does. Step C1
  checks the checkbox and follows it.
- **A known value:** the track is a `GraphicsCircle` ring with a transparent
  fill. The indicator is a `GraphicsArc` from 0 degrees with the sweep
  `360 · clamp(value, 0, 1)`. At 0 there is no indicator.
- **No value (the spinner):** the indicator is a `GraphicsArc` with the sweep
  `360 · indeterminate_share`, 90 degrees. Its `start_angle` is a function:
  `360 · frac(get_reactive_clock_time(ctx.clock) / indeterminate_period)`,
  so one turn takes 1 second. Only this one cell reads the clock. A tick
  invalidates the arc and nothing else, and the canvas does not run again.
- The canvas reads `w.value`. When the value changes from `nothing` to a
  number, the canvas runs again. The new arc does not read the clock, so the
  ring stops its subscription. A ring with `visible == false` prints an empty
  canvas and does not read the clock either.
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
- Each visible part is a `GraphicsRect` with the radius of the track. The
  positions of the rectangles are functions that read the clock, so only
  these cells tick. The bounds of a rectangle change from frame to frame, so
  the dirty rectangle of SDL covers the old and the new place. Both are in the
  box of the bar.
- A known value draws the bar as it is drawn now, and the bar does not read
  the clock.

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

Do the work in a worktree of projectured-julia, and in a branch of
omnet-julia. Make one commit for each step, and mark the step here.

### Part A — the rename

- [ ] **A1. Rename in projectured-julia.**
  - Run `workspace/bin/julia-rename.jl` with `--report` for each name of 4.1.
    Read `--show-other` before you trust a rename whose `other` count is not
    zero.
  - A theme field and a keyword can not go through the tool. Rename
    `progress_height` with a text pass on the exact word.
  - Do a second pass for strings, docstrings, the symbol `:WidgetProgress` and
    the documents.
  - After each text pass, find the new name as a `.jl` file name in a string,
    and revert those hits.
  - Replace the names in `package/*/precompile/examples.txt` with a text pass
    on the exact word. These files are generated lists of signatures. The next
    recording makes them exact.
  - Update [feature-video-screenplays.md](feature-video-screenplays.md).
  - Tests: `test_widget_live_values()`, `test_widget_colors()`,
    `test_example(widget_progress_bar_example)` and the naming guard. Then run
    `Pkg.precompile()` over `environment/all`, and search its log for
    `Imported binding .* was undeclared`.
- [ ] **A2. omnet-julia follows.** Do this on a branch of omnet-julia.
  - Change the imports, the constructors, the tests, `legacy-simulation.md`,
    the two pending plans and `asset/precompile/PrecompileStatements.jl`.
  - Do not change `plan/done/`.
  - Run `Pkg.precompile()` and search for undeclared bindings again. Then run
    the suites that hold the 9 assertions.
  - This branch can land only after A1 is on main of projectured-julia.
- [ ] **A3. inet-julia follows.** Change the 25 generated lines of
  `asset/precompile/PrecompileStatements.jl`.

### Part B — `GraphicsArc`

- [ ] **B1. The primitive.**
  - Add the document, the constructor, `_make_angle_cell`, the hit test and
    the bounds.
  - Add a row to the table of
    [graphics.md](../../documentation/package/platform/graphics/graphics.md),
    and a clause to its sentence about the hit test. Write that an angle is
    `Float64` and is not a coordinate.
  - Test in `GraphicsDocumentTest.jl`, with the testset of `GraphicsPolygon`
    as the model:
    - the fields
    - an angle from a cell that changes
    - a hit in the sweep and a miss outside it
    - `get_graphics_size` gives the box of the full circle
- [ ] **B2. SDL.** Add `_render_arc!` and its branch.
  - Test in `GraphicsToFileTest.jl` with `write_image(…; supersample = 1)`,
    because the default supersample hides edges that are not smooth.
  - A pixel in the band and in the sweep has the color. A pixel in the band
    and outside the sweep has the background color.
  - A full sweep colors the same pixels as the ring of a `GraphicsCircle`.
- [ ] **B3. PDF.** Add `paint_arc!` and its branch. Add an arc to the canvas
  of the test `"write_pdf renders every primitive + embedded font"`.
- [ ] **B4. Web.** Add the branch in `_serialize_node`, and `drawArc` in
  `client.js`. In `WebTest.jl`, test that an arc gives the dictionary of 4.2.

### Part C — the ring, and the bar for unknown progress

- [ ] **C1. The ring.**
  - Add the document, the theme field `progress_ring_size`, the printer, its
    row in the dispatch table, the exports, and `:WidgetProgressRing` in
    `make_interface_api`.
  - Test in a new `WidgetProgressRingTest.jl`, `test_widget_progress_ring()`.
    Check that its fixture names are not in another test file.
  - Check these results:
    - The diameter is one line of the theme font.
    - At 0.25 the arc goes from 0 to 90 degrees.
    - At 0 there is no indicator.
    - At 1 the indicator is a full ring.
    - A row of a `WidgetTable` that holds a ring has the same height as a
      row of text. Assert the coordinates.
  - Check the spinner with a `Clock` in a `PrinterContext` (`with_clock`):
    - At the clock times 0 and 0.25, `start_angle` gives 0 and 90.
    - While the ring spins, `has_dependent_cells` of the clock time is true.
    - After the value becomes 0.5 and the ring prints again, it is false.
    - A ring with a known value never makes it true.
- [ ] **C2. The bar for unknown progress.**
  - Give `WidgetProgressBar` the value `nothing` (4.4): the field type, the
    default of the constructor, `_make_share_cell` for `nothing`, and the
    moving segment in the printer.
  - Test in `WidgetLiveValueTest.jl`, next to the testset of the bar that
    follows a function. Use a bar of 200 pixels, a `Clock` in a
    `PrinterContext`, and these checks:
    - At the clock time 0, one rectangle covers the pixels 0 to 50.
    - At 0.5, one rectangle covers the pixels 100 to 150.
    - At 0.875, two rectangles cover the pixels 175 to 200 and 0 to 25.
    - The subscription to the clock starts and stops as for the ring.
    - A bar with a known value draws the same elements as before this step.
      Compare them with the bar at the commit of step A1.
- [ ] **C3. The examples.** Add `widget_progress_ring_example` and
  `make_widget_progress_ring_document_example`: rings at some values, one
  spinner, and a `WidgetTable` of jobs with a ring column.
  - Add a bar with no value to the example of the bar.
  - Add the document of the ring to `_PROBED_WIDGET_DOCUMENTS` in
    `WidgetColorTest.jl`.
  - Run `test_example` of the two examples with a timeout. A spinner keeps the
    editor awake, and a test must not wait for it to settle.
- [ ] **C4. The documents.** Update these files:
  - [widget.md](../../documentation/package/platform/widget/widget.md): the
    table of documents, the list of widgets that only show a value, the count
    of the theme sizes, and a paragraph on a value that is not known.
  - [system-anatomy.md](../../documentation/design/system-anatomy.md): the
    row of `WidgetDocument.jl`.
  - [layout-rules.md](../../documentation/rule/layout-rules.md): the
    widgets that size from an authored value. The ring sizes from the line
    height.
- [ ] **C5. The live check.** The owner looks at the two examples in a real
  window: the ring in the table, the spinner, and the moving segment of the
  bar.
  - Measure the CPU time while a spinner turns only after the owner says so,
    on an idle machine.

### Close

- [ ] Add an item to
  [release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md):
  the next release gives `ProjecturedPlatform` the version 0.2.0 (Q1). The
  generator needs a way to give a minor step. Each package above it gets a
  new `[compat]` bound on 0.2, and so a new version by rule 3.
- [ ] Move this plan to `plan/done/`.

## 7. Risks

- **A spinner keeps the editor awake.** While a document shows a ring or a bar
  with no value, the loop wakes every 10 milliseconds. A document that forgets to set
  the value keeps the CPU busy, and a `wait_for` of a video recording that
  waits for a quiet document never ends. This is the cost of every animation.
- **A ring that scrolled out of view still reads the clock.** A ring in a
  viewport stays printed when it is outside the visible part, so it keeps its
  subscription. A tab page that is not shown does not print its content.
- **The track and the arc use different drawing paths in SDL.** The track
  uses rows of spans, and the arc uses triangles. Their edges can differ by
  less than one device pixel. Step B2 compares the pixels.

## 8. Out of scope

- Text in the ring. At 16 pixels there is no space for it. Use the next cell
  or the `tooltip`.
- Rings in the tables of omnet-julia. No bar there is in a table now.
