# Gesture log overlay

## Goal

Show the user what the editor does, while the user works. Record every gesture
and the operation that the projection pipeline makes from it. Keep the last N
records in a buffer of fixed size. Draw the buffer as an overlay panel on top of
the window content.

A filter parameter selects what the buffer keeps. The default filter drops
selection operations, because a selection operation follows almost every click
and almost every arrow key.

`run_example` gets a new keyword argument that turns the feature on.

## What exists today

These facts come from the current code. Read them before you design a change.

- The editor loop makes one operation per gesture. See
  [Editor.jl:97](../../package/kernel/main/editor/Editor.jl#L97). `read!` seeds
  an `Intent(window_input, nothing)`, calls `read_intent` on the root
  projection, and takes `change.operation`. The loop already logs the operation
  with `@info "[operation] ..."`
  ([Editor.jl:165](../../package/kernel/main/editor/Editor.jl#L165)).
- A view concern belongs in a decorator projection, not in the editor loop.
  `GestureHelpProjection` is the model to copy
  ([GestureHelpDecorator.jl](../../package/domain/main/gesturemap/GestureHelpDecorator.jl)).
  Its printer is transparent. Its reader gives the inner reader priority. Shared
  state lives in a separate object, because the gallery rebuilds the decorator
  on each dispatch.
- A read-only document plus a `XToSyntax` printer reuses the normal display
  path. `GestureMap` and `GestureMapToSyntax`
  ([GestureMap.jl](../../package/domain/main/gesturemap/GestureMap.jl),
  [GestureMapToSyntax.jl](../../package/domain/main/gesturemap/GestureMapToSyntax.jl))
  are the model. The gallery renders a `GestureMap` with
  `ChainingProjection(GestureMapToSyntax(), RecursiveProjection(SyntaxToText()), WordWrapping(), TextToGraphics())`
  ([Gallery.jl:347](../../package/domain/example/Gallery.jl#L347)).
- A printer runs one time. A printer that reads a `Cell` outside a cell freezes
  the render. A thunk that calls `print_document` is an accepted pattern: the
  tooltip content does exactly that
  ([Gallery.jl:368](../../package/domain/example/Gallery.jl#L368)).
- `GraphicsCanvas` holds `x`, `y`, `w`, `h` and an `elements` collection
  ([Graphics.jl:396](../../package/visual/main/graphics/Graphics.jl#L396)). An
  element can be a nested canvas. A `GraphicsRect` carries a `StyleColor` with
  an alpha component
  ([Graphics.jl:82](../../package/visual/main/graphics/Graphics.jl#L82)).
- `TextToGraphics` maps graphics references to `nothing`
  ([TextToGraphics.jl:96](../../package/visual/main/text/TextToGraphics.jl#L96)).
  The window level maps a reference into the content iomap
  ([ScreenToScreen.jl:146](../../package/visual/main/screen/ScreenToScreen.jl#L146)).
- The printer context carries the space that the parent gives
  (`ctx.available_width`, `ctx.available_height`,
  [PrinterContext.jl:49](../../package/kernel/main/projection/PrinterContext.jl#L49)).
  `ScreenToScreen` sets it from the window size
  ([ScreenToScreen.jl:83](../../package/visual/main/screen/ScreenToScreen.jl#L83)).
- No `describe_event` function and no `Base.show` method for an event or an
  operation exist.
- The kernel `document` layer and the kernel `operation` layer are not sealed,
  but this plan needs no change in them.

## Design

### Two projections, one log

Split the work in two, because the two seams are different.

1. **`GestureLogRecordingProjection`** — a transparent decorator at the **root**
   of the composed screen projection. Its reader calls the inner reader, records
   the pair (gesture, operation), and returns the inner result without a change.
   The root is the seam where every operation passes, so the record is complete:
   a content operation, a window operation, and a workbench operation all bubble
   through it.
2. **`GestureLogOverlayProjection`** — a decorator around one window's **content**
   pipeline. Its printer draws the panel over the inner output. Its reader is a
   pure pass-through.

Both hold the same `GestureLog` object. The gallery makes one log and threads it
into both, the way it threads one `GestureHelpState` today.

### The log document

```julia
struct GestureLogEntry
    index::Int          # 1, 2, 3, … over the whole session
    gesture::String     # the rendered gesture, e.g. "Ctrl+C"
    operation::String   # the rendered operation, e.g. "select entries[1].value"
    kind::Symbol        # the operation type name, for the display style
end

@document struct GestureLog
    entries::CellVector = CellVector()
    capacity::Int = 20
    count::Int = 0      # entries recorded so far, including dropped ones
end
```

`record_gesture!(log, gesture, operation)` pushes one entry and deletes the
first entry while the length is over the capacity. `entries` is a `CellVector`,
so the push invalidates every reader of the collection.

The entry holds **strings**, not the live operation. An operation holds a
reference into the document. The document changes after the operation runs, so a
live operation renders differently one second later. A string is a record of the
moment.

### The filter

The filter is a predicate `(gesture, operation) -> Bool`. It returns `true` for
a pair that the log must keep. It lives on `GestureLogRecordingProjection`,
which is a plain `struct <: Projection` and holds it as a plain field. Do not
put the predicate in a reactive field: a `Function` in a `@document` field or in
a `@projection` field becomes a thunk and the reader calls it with no arguments.

The default is `default_gesture_log_filter`. It returns `false` for a
`ReplaceSelectionOperation`, for a `DoNothingOperation` and for `nothing`. It
returns `true` for every other operation.

The filter runs at record time, not at display time. The buffer is small, so a
filter at display time leaves almost nothing to show.

### The rendering of a gesture and an operation

Two functions in the log slice make the strings. They are a display concern, so
they do not belong to the event layer or to the operation layer.

- `describe_gesture(event)` — `"Ctrl+C"`, `"Left"`, `"Click (412,88)"`,
  `"Wheel -3"`. Write one method per gesture type. The fallback is
  `string(nameof(typeof(event)))`.
- `describe_operation(op)` — `"select <reference>"` for a
  `ReplaceSelectionOperation`, `"set <reference> = <value>"` for a
  `ReplaceReferencedValueOperation`, `"compound(3)"` for a `CompoundOperation`,
  and so on. The fallback is `string(nameof(typeof(op)))`. Render a reference
  with `string(reference)` and cut it to a maximum length.

`GestureLogToSyntax` makes one `SyntaxLeaf` per entry and joins the leaves with
a newline separator, exactly like `GestureMapToSyntax`. The index and the
gesture get one style, the operation gets another style.

### The overlay panel

The printer of `GestureLogOverlayProjection` does this:

1. Print the inner projection. Keep the inner iomap.
2. Make the panel body as a `ComputedCell`. The thunk prints the log through
   `ChainingProjection(GestureLogToSyntax(), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure))`
   and returns the output canvas. The thunk reads `log.entries`, so the buffer
   invalidates it. This re-prints the whole panel for each record. The panel
   holds at most 20 lines, so the cost is small. A reactive
   `GestureLogToSyntax` is the refinement if a measurement shows a cost.
3. Make the background rectangle. Its `w` and `h` read the body canvas size plus
   the padding, inside cells.
4. Make the panel canvas with the rectangle and the body. Its `x` and `y` read
   `ctx.available_width` and `ctx.available_height` and the anchor, inside
   cells, so a resize of the window moves the panel.
5. Return an output canvas with exactly two elements: a `ComputedCell` that
   yields the inner output, and the panel canvas. The two elements are stable,
   so the iomap identity is stable (AR-STABLE-IOMAP-IDENTITY).

The inner canvas sits at `(0, 0)` in the output canvas, so a pixel coordinate
means the same thing above and below the decorator. The reader passes every
gesture to the inner reader without a change, and the panel is never a hit
target. A click goes through the panel to the content below it.

The reference mappers delegate to the inner mappers. The extra canvas level is
not in the mapped path. This matches `TextToGraphics`, which maps a graphics
reference to `nothing` in both directions. Step 6 checks a widget pipeline,
which maps more. If a widget pipeline needs the level, add the `elements[1]`
step on the forward map and remove it on the backward map.

### The gallery

`run_example` gets three keyword arguments:

- `gesture_log=false` — turn the feature on.
- `gesture_log_filter=nothing` — a predicate that replaces the default filter.
- `gesture_log_capacity=20` — the size of the buffer.

The gallery makes one `GestureLog`, wraps each example projection in a
`GestureLogOverlayProjection` in the flag loop, and wraps the composed root in a
`GestureLogRecordingProjection` inside the `compose` closure. The wrap of the
`compose` closure covers the three composer variants (plain, tooltip,
inspector) with one line of code.

## Decisions

- **A decorator projection, not the editor loop.** The editor must not know
  about a log or an overlay. This follows the rule that the gesture help window
  is a projection.
- **Two decorators, one shared log.** The complete record is only at the root.
  The panel needs a canvas, which only a content pipeline has.
- **The panel is an element of the output canvas, not a window.** The user asked
  for an overlay. A sibling window is the mechanism that the help and the
  tooltip use, and it is rejected here.
- **The buffer holds strings.** See "The log document" above.
- **The filter runs at record time.** See "The filter" above.
- **The newest entry is at the top.** The newest line then always sits at the
  same place, and the panel does not jump.
- **The default capacity is 20 entries.**

### Rejected

- A `GestureLogOperation` that the reader returns beside the real operation. An
  operation acts on the document under edit. The log is projection state.
- A recorder in `Editor.evaluate!`. It is simple, but it puts a view concern in
  the loop.
- A widget panel (`WidgetCard`). A card stretches to the available width and
  spills. A graphics rectangle plus a text canvas is enough and needs no widget.

## Steps

Do the work in a git worktree, not in the main checkout. Make one commit per
step. Mark each step here when it is complete.

- [ ] **Step 1 — Add the log document.** Add
  `package/domain/main/gesturelog/GestureLog.jl` with `GestureLogEntry`,
  `GestureLog`, `record_gesture!`, `describe_gesture`, `describe_operation` and
  `default_gesture_log_filter`. Include it in
  [ProjecturedDomain.jl](../../package/domain/main/ProjecturedDomain.jl) next to
  the `gesturemap` document include. Export the new names beside the
  `GestureMap` exports.
- [ ] **Step 2 — Add the syntax printer.** Add
  `package/domain/main/gesturelog/GestureLogToSyntax.jl`, modelled on
  `GestureMapToSyntax`. Include it after `GestureMapToSyntax.jl`.
- [ ] **Step 3 — Add the recorder.** Add
  `package/domain/main/gesturelog/GestureLogRecorder.jl` with
  `GestureLogRecordingProjection`, a transparent printer, a reader that records
  and returns the inner result, and delegating reference mappers.
- [ ] **Step 4 — Add the overlay.** Add
  `package/domain/main/gesturelog/GestureLogOverlay.jl` with
  `GestureLogOverlayProjection` and the panel geometry above. Include it after
  Step 2, because the printer names `GestureLogToSyntax`.
- [ ] **Step 5 — Wire the gallery.** Add the three keyword arguments to
  `run_example` in [Gallery.jl](../../package/domain/example/Gallery.jl) and
  document them in the docstring.
- [ ] **Step 6 — Check the colors and the mapping in the live editor.** Run
  `run_example("json"; gesture_log=true)` and
  `run_example("workbench"; gesture_log=true)`. Check three things: the SDL
  backend paints the translucent background; a click under the panel still
  reaches the content; a widget pipeline still maps its references. If the
  backend ignores the alpha component, use an opaque panel color. If the widget
  pipeline loses a reference, add the `elements[1]` step to the mappers.
- [ ] **Step 7 — Add the tests.** See the next section.
- [ ] **Step 8 — Update the documentation.** Add the slice to the inventory in
  [package/domain/doc/architecture.md](../../package/domain/doc/architecture.md).
  Add a short section to
  [documentation/debugging.md](../../documentation/debugging.md), because the
  overlay is a debugging aid.
- [ ] **Step 9 — Move this plan to `plan/done/`.**

## Tests

Add `package/domain/test/projection/GestureLogTest.jl` with `test_gesture_log()`.
Include it in
[ProjecturedDomainTest.jl](../../package/domain/test/ProjecturedDomainTest.jl),
call it in the aggregator and export it, the way `test_gesture_help` is wired.

Test these things:

1. **The buffer.** Record 25 entries into a log of capacity 20. The length is
   20. The first entry is the 6th record. `count` is 25.
2. **The filter.** The default filter drops a `ReplaceSelectionOperation` and
   keeps a `ReplaceReferencedValueOperation`. A custom filter replaces the
   default.
3. **The recorder.** The decorator returns exactly what the inner reader
   returns. A gesture that makes an operation adds one entry. A gesture that the
   inner reader declines adds no entry.
4. **The overlay printer.** The output is a `GraphicsCanvas` with two elements.
   Element 1 yields the inner output. Element 2 is the panel.
5. **The reactive panel.** Force the panel body. Record one operation. Force the
   body again. The new text holds the new entry. This is the test that fails if
   the printer reads the log outside a cell.
6. **The pass-through.** The overlay reader gives the same operation as the
   inner reader for a click and for a key.

Run `test_gesture_log()` alone while you work. Run `test_domain()` one time at
the end.

## Risks

- **A write during the read stage.** The recorder writes into a `CellVector`
  from `read_intent`. This is not a write in a thunk, so it does not break
  AR-NO-WRITE-IN-THUNK. The write happens before `print!`, so the frame that
  follows shows the entry.
- **A full repaint per record.** The panel body is a fresh canvas on each
  record. The renderer may repaint the whole window. The overlay is a debugging
  aid, so this is acceptable. Measure it in Step 6.
- **The measure function.** `TextToGraphics` needs a measure function. Take the
  gallery default (`truetype_measure_text`) as a keyword argument of the
  projection, so a test can pass a fake measure function.

## Limitations to state in the documentation

- The editor makes the zoom operation **after** the pipeline declines the
  gesture ([Editor.jl:129](../../package/kernel/main/editor/Editor.jl#L129)).
  No projection sees it, so the log does not hold it.
- A gesture that no reader answers leaves no entry. The log holds operations,
  not every key.
- The panel is not interactive. It has no scrollbar and no selection.
