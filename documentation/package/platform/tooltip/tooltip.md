# Tooltip

> **Kind:** design · **Status:** current · **Stands on:** [screen.md](../screen/screen.md), [mousetargettracking.md](../mousetargettracking/mousetargettracking.md)

The tooltip slice of `ProjecturedPlatform` shows what a part says about itself in a window of its own. The meaning is in the gesture table of the part: a part answers a dwell with an operation. A wrapper at the screen keeps the one tooltip window. This document says how the two meet, and why the tooltip is a binding and not a central lookup.

## How it works

### A part answers a dwell

A part that has something to say declares a binding in its own gesture table:

```julia
get_document_gesture_bindings_own(::Type{JuliaFunction}) = GestureBinding[
    make_tooltip_binding(function_ -> _julia_tooltip_text(compute_julia_signature(function_));
                         description = "Show the signature")]
```

`make_tooltip_binding(compute; description)` binds a `MouseDwell`. The binding answers `ReplaceViewStateOperation(OpenTooltipOperation(layers, source, point))` when `compute(document)` answers a document, and nothing when it answers `nothing`. The binding is `applicable` only where the part has something to say.

`OpenTooltipOperation` holds:

- `layers`: the `(title, content)` pairs, the nearest part first. The title is `get_document_title` of the part, or the name of its type;
- `source`: the path of the nearest part. A reader reroots it and retargets it on the way up, as it does any path;
- `point`: where the pointer rested, or `nothing` when a command runs the binding.

`ReplaceViewStateOperation` marks the tooltip as not an edit, so a history does not record it.

### The dwell goes to the part, and out through the parts around it

The gesture tracker recognizes the dwell when the pointer rests. The dwell then goes by its position, as a click does: the screen gives it to the window of the pointer, and each container gives it to the child at its point, in the frame of that child. So the readers decide: a projection can deny a dwell with an answer that ends the walk, such as `DoNothingOperation`, and an answer of `nothing` says that it has nothing to say. A child that answers nothing gets the dwell in its documents: the backward map of the point names the part inside it (`compute_part_at_point`), and the documents on that path read the dwell with their tables, the part first (`read_child_part_gesture`). So a text, which draws a whole document as one leaf, gives a dwell to the part of the document under the pointer.

**The parts around add their layers.** `OpenTooltipOperation` collects (`is_collecting_operation`). After the child at its point answered, each container reads the dwell with the tables of its own documents, from the one above the child out to its own input (`read_container_gesture`, with the kernel's `read_gesture_outward`): when the deeper answer is nothing, the next document around reads the gesture with its own table; when the deeper answer collects, the next document reads it too, and `join_collected_operations` adds its layer after the nearer ones; any other answer stops the walk. So a label in a group with a tooltip gives two layers, and a label that says nothing gives the layer of the group. The point in the answer moves back into the frame of each container on the way out, so the window opens beside the pointer. A command that shows the tooltip of the selection has no point: it sends the dwell by route to the part, and `read_routed_child` reads the tables outward in the same way.

### The window

`TooltipWindowProjection` keeps the tooltip window. It sits at the screen, inside the gesture tracker and around the mouse target tracker. `make_tracking_screen` puts it there when `inner_wrappers` holds `wrap_tooltip_window`. The `window` wrapper of `build_editor` gives its setting `inner_wrappers` to `make_tracking_screen`.

- **Opening.** The wrapper takes the `OpenTooltipOperation` out of the answer of its content and opens a window with `style = :tooltip`, `offset` from the point, in screen coordinates. The window of the pointer moves the point from its own frame to the screen. With no point, the window opens at the forward image of the part.
- **What it shows.** The window holds a `TooltipContent`: all the layers, and how many of them show. The natural projection draws it: the content of each shown layer, and a separator and the title before each layer when more than one shows. The row is `make_natural_tooltip_row(; measure)`, and a host gives it in `make_opened_window_projections(; content)`.
- **More and fewer.** F2 shows the next layer outward, and Shift+F2 one fewer. `TooltipWindowState` declares both keys in its gesture table while a tooltip is open, so the gesture help lists them. So F2 does not reach the part under the tooltip while the tooltip is open.
- **Closing.** A move off the part closes the window: the wrapper maps the point backward, and the path does not go through the source. Escape closes it, and the wrapper takes the Escape. A press, a scroll and the leave of a window close it too. Any other key passes on and leaves it open.

The state of the wrapper, `TooltipWindowState`, holds the layers, the count that shows, the source and the window operation. A view state operation writes each field.

### A command runs the same binding

The command palette lists the binding by its `description` on the selection, and greys it where the part says nothing. It runs the binding with no gesture, so the answer has no point, and the wrapper opens the window at the part. A command that an agent runs goes by route through the wrapper, and the wrapper takes the tooltip from that answer as well.

### The decorator

`TooltipSource` wraps a `child`, which stays on the screen, and a `content`, which the tooltip window shows. `TooltipDecoratorProjection` prints the child and calls its `trigger(source, event)` function on each event. When the trigger is true for `delay_ms`, the reader makes an `OpenWindowOperation` with the `id`, the `style` and the content of the source; when it is false again, a `CloseWindowOperation`. It is for a tooltip with its own trigger.

## How it fits

The tooltip slice depends on the kernel and on the graphics and screen slices. It can not depend on the natural or widget slices, because both use it. So the natural slice draws `TooltipContent`, and the widget, Julia and fault slices declare their bindings with `make_tooltip_binding`.

## Design decisions

- **The meaning belongs to the part.** A part answers a dwell from its own gesture table, and each projection on the way up can change or drop the answer. A central lookup that asks the document under the pointer gives no projection on the path that chance. The command palette can run a binding, but not a lookup.
- **A tooltip is a window.** A tooltip can extend past the edge of the window it describes, and it needs no drawing layer inside the window. See the invariant `PAR-MANY-WINDOWS`.
- **One wrapper keeps the window.** A part cannot close its own tooltip when the pointer goes to another part, and a window belongs to the screen. The wrapper does only this global piece.
- **The layers are collected at once.** F2 and Shift+F2 choose from what the dwell collected, so they read no part again.

## Usage

```julia
editor = build_editor(document, projection; backend = backend,
    window = (; title = "Title", inner_wrappers = [wrap_tooltip_window],
              opened_window_projections = make_opened_window_projections(;
                  content = Pair{Type,Any}[make_natural_tooltip_row(measure = measure)])))
```

**The window fits what it says.** The wrapper gives the window `minimum_size = (120, 32)` and `maximum_size = (560, 400)`, both keywords of `TooltipWindowProjection`. The screen prints the window at the maximum, so a long text wraps there, and the backend gives the window the extent of what it printed. So a tooltip of one word is small and a docstring is tall, and neither is cut.

- Tests: `test_tooltip_window()` for the window, through a real editor; `test_widget_tooltip()` and `test_julia_tooltip()` for the bindings; `test_tooltip()` for the decorator.

## Limits

- The default `position` of the decorator is a fixed rectangle at the corner. A caller must give a position function.
