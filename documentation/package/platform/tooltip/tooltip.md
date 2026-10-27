# Tooltip

> **Kind:** design · **Status:** current · **Stands on:** [screen.md](../screen/screen.md), [gesturetracking.md](../gesturetracking/gesturetracking.md)

The tooltip slice of `ProjecturedPlatform` shows what a part says about itself in a window of its own. The meaning is in the gesture table of the part: a part answers a dwell with an operation. A wrapper at the screen keeps the one tooltip window. What a part says is a `TooltipNote`, which one projection draws in a frame with the texts and the colors of the theme. This document says how the three meet, and why the tooltip is a binding and not a central lookup.

## How it works

### A part answers a dwell

A part that has something to say declares a binding in its own gesture table:

```julia
get_document_gesture_bindings_own(::Type{JuliaFunction}) = GestureBinding[
    make_tooltip_binding(_make_julia_function_note; description = "Show the signature")]
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

`TooltipWindowProjection` keeps the tooltip window. It sits around the screen, inside the gesture tracker. `make_tracking_screen` puts it there when `inner_wrappers` holds `wrap_tooltip_window`. The `tooltip` wrapper of `build_editor`, on by default in the layer `:window => -20`, gives `wrap_tooltip_window` to the `window` wrapper through `EditorParts.window_wrappers`, so every editor with a window has the tooltip window, and `tooltip = false` leaves it out. A host that calls `make_tracking_screen` itself, as the gallery does, passes `wrap_tooltip_window` in `inner_wrappers`.

- **Opening.** The wrapper takes the `OpenTooltipOperation` out of the answer of its content and opens a window with `style = :tooltip`, `offset` from the point, in screen coordinates. The window of the pointer moves the point from its own frame to the screen. With no point, the window opens below the part, with the left edges aligned (`find_part_place` of the screen slice).
- **What it shows.** The window holds a `TooltipContent`: all the layers, and how many of them show. The natural projection draws it in a frame: the `surface` of the `TooltipTheme`, its `line`, `line_width` wide, and its `padding`. Inside stands the content of each shown layer, with the title of its part before it, in the quiet `layer_text`, when more than one shows. The last line names the keys of the layers, "F2 shows 1 more" or "Shift+F2 shows one fewer", from `describe_layer_keys`, which reads `WINDOW_LAYER_MORE_KEY` and `WINDOW_LAYER_FEWER_KEY`, the keys that the window binds. The row is `make_natural_tooltip_row(; measure)`, and a host gives it in `make_opened_window_projections(; content)`.
- **More and fewer.** F2 shows the next layer outward, and Shift+F2 one fewer. `TooltipWindowState` declares both keys in its gesture table while a tooltip is open, so the gesture help lists them. So F2 does not reach the part under the tooltip while the tooltip is open. The keys and the reopening of the window are the layer helper of the screen slice (`make_window_layer_bindings`, `show_window_layers`), which the context menu window uses too.
- **Closing.** A move off the part closes the window: the wrapper maps the point backward, and the path does not go through the source. Escape closes it, and the wrapper takes the Escape. A press, a scroll and the leave of a window close it too. Any other key passes on and leaves it open.

The state of the wrapper, `TooltipWindowState`, holds the layers, the count that shows, the source and the window operation. A view state operation writes each field.

The context menu works the same way, with a right click and a wrapper of its own: [context-menu.md](../widget/context-menu.md).

### The note

`TooltipNote(; title, keys, code, text, facts, hint, tone)` is what a part says, piece by piece, and `TooltipNoteToVerticalLayout` of the natural slice draws every note the same way:

- the head: the mark of the `tone` (`:warning` or `:error`, a glyph of the icon font in its color), the `title` in bold, and the key caps of `keys`, each key a cap in Ubuntu Mono on `key_fill` with a `key_line`; two keys have an "or" between them;
- the `code`, such as a signature, in Ubuntu Mono, and the `text`, in the body text; both break at the edge of the window;
- the `facts`, a grid of a name in the quiet text and a value in Ubuntu Mono; a fact can be a `DocumentCondition`, drawn as the glyph of its look in the color of its role, its words and its count;
- the `hint`, in the quiet text.

The title and the text stand `gap` apart, and the parts `section_gap` apart. A piece that is `nothing` or empty draws nothing, and a piece that is a document draws as itself.

The note takes its keys from where they are bound: the `shortcut` of an `Action`, a constant such as `HELP_GESTURE`, or `find_bound_keys(type, description)`, which reads the key patterns that the gesture table of a type binds to a command. So a change of a binding changes the note.

**A note made when the pointer rests.** A `tooltip` of a widget, of a `PaneTabTitle`, and `decoration.tooltip` can be a function with no argument that makes the note. The dwell calls it, so a part reads its facts only when a person asks. A row of a tree is built in a computation that reads its decoration; a fact read in the decoration would rebuild the row each time it changes, as the position of a running task does, and a fact read in the function costs nothing until the pointer rests. A note reads only what a document holds: no disk read, because a reader and a computation read no disk.

Who answers a note:

- a widget: a string `tooltip` is the text of a note; a control of an action (`WidgetToolbarItem`, `WidgetMenuItem`, `WidgetButton`) says the label of the action as the title and its `shortcut` as a key cap. A control that shows only a picture says its label and its key with no tooltip of its own; one that shows its label says nothing more;
- a decorated document, in a row of a tree and in a tab: `make_decoration_note(decoration)` says each condition that has words as a fact, then the tooltip of the decoration, a string, a note, or a function that makes one. Each row of the Explorer gives a function: a file its path, format and lines (`make_file_note`), a folder its path and entries, a task its state, result, times, position and process, an assistant its model, context and prompts, a log its stored counts, a system process its full command;
- a fault: `make_fault_report_note(report)`, in the tone of an error;
- a Markdown link and an RST reference: the target as a fact;
- a Julia function: its name, and its signature as code; a docstring adds its prose.

### A container says what the pointer is on

A part sees only itself, so a JSON value can not say its path and a Julia call can not say the function that it names. The container around it knows: each move of the pointer writes the mouse target, and each document on the way holds the path from itself down to the part under the pointer ([mouse-target.md](../../kernel/mouse-target.md)). A container gives a tooltip binding of its own that reads that path. `find_pointed_part(container)` answers the part at the end of the mouse target, or of the selection when no pointer is on the container, as for a tooltip that a command opens, with the documents and the steps on the way; it stops where a step leads into a text.

The dwell reaches the container after the part, so the order of the layers stays: when the part has a note of its own, the note of the container is the next layer, which F2 shows; when the part has none, the note of the container shows first. The containers:

- a JSON or a YAML file: the path of the part, as `users[1].name`, its type, and its length, its value or its count;
- an XML file: the path of the element, as `/root/a[1]/b`, the namespace of its prefix, its attributes and children;
- a Julia file: for a call of a plain name, the signature and the docstring of the function of that name in the file;
- a graph: the edges out and in, and the label, of a vertex.

A package adds the same for its own files, with a tooltip binding on its file type.

### A command runs the same binding

The command palette lists the binding by its `description` on the selection, and greys it where the part says nothing. It runs the binding with no gesture, so the answer has no point, and the wrapper opens the window at the part. A command that an agent runs goes by route through the wrapper, and the wrapper takes the tooltip from that answer as well.

### The decorator

`TooltipSource` wraps a `child`, which stays on the screen, and a `content`, which the tooltip window shows. `TooltipDecoratorProjection` prints the child and calls its `trigger(source, event)` function on each event. When the trigger is true for `delay_ms`, the reader makes an `OpenWindowOperation` with the `id`, the `style` and the content of the source; when it is false again, a `CloseWindowOperation`. It is for a tooltip with its own trigger.

## How it fits

The tooltip slice depends on the kernel and on the graphics, screen and style slices. It can not depend on the natural or widget slices, because both use it. So the natural slice draws `TooltipContent` and `TooltipNote`, the widget slice makes the notes of a widget, a decoration and a fault, and the widget, Julia and fault slices declare their bindings with `make_tooltip_binding`. The navigator, explorer and task slices use the tooltip slice to make their notes.

## Design decisions

- **The meaning belongs to the part.** A part answers a dwell from its own gesture table, and each projection on the way up can change or drop the answer. A central lookup that asks the document under the pointer gives no projection on the path that chance. The command palette can run a binding, but not a lookup.
- **A tooltip is a window.** A tooltip can extend past the edge of the window it describes, and it needs no drawing layer inside the window. See the invariant `PAR-MANY-WINDOWS`.
- **One wrapper keeps the window.** A part cannot close its own tooltip when the pointer goes to another part, and a window belongs to the screen. The wrapper does only this global piece.
- **The layers are collected at once.** F2 and Shift+F2 choose from what the dwell collected, so they read no part again.
- **A note is meaning, not markup.** An author writes what a part is: its name, its keys, what it does, its facts. Markdown is a domain package above the platform, which the platform widgets can not use, and a span of the text domain holds a color, not a role of the theme. One projection gives every note the same look, in both color modes. A note can hold any document in a piece, such as a Markdown page.
- **No line between the parts.** A `WidgetSeparator` draws a rule of its own length, so in a wide note it stops short of the widest part. The parts stand apart by a gap.

## Usage

```julia
editor = build_editor(document, projection; backend = backend,
    window = (; title = "Title",
              opened_window_projections = make_opened_window_projections(;
                  content = Pair{Type,Any}[make_natural_tooltip_row(measure = measure)])))
```

A part that writes its own note:

```julia
TooltipNote(; title = "Refresh", keys = find_bound_keys(DataFrameView, "Read the frame again"),
            text = "Read the frame again.", facts = ["Rows" => "12480"])
```

**The window fits what it says.** The wrapper gives the window `minimum_size = (120, 32)` and `maximum_size = (560, 400)`, both keywords of `TooltipWindowProjection`. The screen prints the window at the maximum, so a long text wraps there, and the backend gives the window the extent of what it printed. So a tooltip of one word is small and a docstring is tall, and neither is cut. The frame is at least as wide as the least width of the window: `TooltipContentToVerticalLayout` reads `minimum_size` of the `TooltipTheme` and gives it to the frame as the least of its width. So a short note does not leave the surface of the window beside its frame. A frame of one line is higher than the least height, so the height needs no least.

- Tests: `test_tooltip_window()` for the window and its frame, through a real editor; `test_tooltip_note()` for the drawing of a note; `test_widget_tooltip()`, `test_julia_tooltip()` and `test_document_decoration()` for the notes that parts answer; `test_tooltip()` for the decorator.

## Limits

- The default `position` of the decorator is a fixed rectangle at the corner. A caller must give a position function.
