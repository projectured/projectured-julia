# Gesture log

> **Kind:** design · **Status:** current · **Stands on:** [projection-system.md](../../kernel/projection-system.md), [shell.md](../shell/shell.md)

The gesturelog slice of `ProjecturedPlatform` records what a person does in a session: each gesture, and the operation that the projection chain made from it. It shows the record as a panel over a window or in a tab. This document describes the shape that this slice shares with the fault log and the gesture help, and why an entry holds text and not the live values.

## How it works

### The shared shape

Three packages add an editor feature with the same parts, and add no code to the editor loop:

- **A document** holds the state: `GestureLog` here, `FaultLog` in the fault slice, `GestureMap` and `CommandPalette` in the gesturehelp slice. A view of it follows a change as the view of any other document does.
- **A transparent decorator** wraps a projection. Its printer returns the inner output through a computed cell, so the IoMap keeps its identity while the inner projection prints again. Its reader calls the inner reader first. On the way it records the result, catches a fault, or uses one gesture that the inner reader returned no operation for.
- **A panel** draws the document. The document goes through a chain of its own, from `…ToSyntax` through `SyntaxToText` to `TextToGraphics`, and an overlay decorator puts the result in a corner of the window canvas. The overlay reader gives every gesture to the inner projection, so a click on the panel reaches the content below it.

The document also opens in a tab: a natural syntax row draws it, and its insertion alias gives the one instance of the session. [fault.md](../fault/fault.md) and [gesturehelp.md](../gesturehelp/gesturehelp.md) say how the two other packages vary the shape.

### The recorder

`GestureLogRecordingProjection(; inner, log, filter)` calls the inner reader. When the result is an `Operation` and `filter(gesture, operation)` returns `true`, it calls `record_gesture!`. It returns the inner result unchanged, so it never makes an operation and never consumes a gesture.

It belongs at the root of the composed projection, because every operation passes there: an operation of the content, of a window and of a nested application. The `appearance` wrapper answers the keys of the zoom and of the scales outside the window and its recorder, so the log does not hold them.

`default_gesture_log_filter` drops `nothing`, `DoNothingOperation` and every `ReplacePathOperation`. A selection follows almost every click and arrow key, and the part under the pointer follows every move of the pointer, and they would fill the buffer.

### The entry

`record_gesture!(log, gesture, operation)` appends one `GestureLogEntry` and deletes the oldest entries above `capacity`. `count` counts every entry that was recorded, also the entries that the buffer dropped, so the index of a line still says how many gestures came before it.

An entry holds text: the gesture, the operation and the name of the operation type. `describe_gesture` builds the `GesturePattern` that matches exactly the event and writes it with `describe_gesture_pattern`, so the log and the gesture help use one table of key names. A mouse event adds its coordinates, and a double click adds `x2`. `describe_operation` comes from the kernel.

### The panel

`GestureLogOverlayProjection(; inner, log, anchor = :top_right, margin, padding, background)` prints `inner`, and prints the log through `make_gesture_log_content_projection()`. The log chain gets a new `PrinterContext`, so the panel takes the space it needs and not the layout space of the content. The output is one canvas: the inner output at the origin, and the panel at the corner.

The panel reads the maximum width and height of the range in the printer context. They are cells, so the panel follows a resize of the window. With no maximum, the panel stays at the top left. The panel is there also for an empty log, which shows `no gesture yet`.

`GestureLogToSyntax` prints one line for each entry, the newest first, so the newest line stays in one place. It uses DejaVu Sans Mono, which has the glyphs `←` and `∅`. A glyph from a fallback font has a width of its own, and the columns would not align. A line of a selection operation is muted. The panel is 8 pixels wider than its text, because the measure function of the printer and the text metrics of the backend differ a little.

### The theme

`GestureLogTheme` holds the text of the index, the gesture, the operation and the muted parts of a line of the gesture log, and of an empty log. Each value has the default that the slice draws with no
appearance. `GestureLogToSyntax` holds its styles and no theme. `make_gesture_log_projection(; theme)`
fills them with `get_gesture_log_style`, from a `GestureLogTheme` scaled or not, or the default values for
`nothing`. The registration of the gesture log gives the scaled theme of the `Appearance`. The overlay keeps its own styles, built the same way through `make_gesture_log_panel_syntax_projection`.

## How it fits

The gesturelog slice depends on the kernel and on the collection, domain, graphics, natural, projection, serialization, style, syntax and text slices.

The `gesture_log` wrapper of `build_editor`, in this slice, puts a recorder outermost in the container layer of a window, over `get_session_gesture_log()`; [shell.md](../shell/shell.md#the-wrappers-of-a-window) gives the order of the wrappers. The toolbar button and `gestures` in an empty tab open that log. The gallery adds an overlay to each window and a recorder at the root with `gesture_log = true`, over a log of its own.

Its `__init__` registers the natural row `:gesturelog`. `get_insertion_aliases` gives `gestures`, and `make_insertion_document` returns the session log, because a new log would never fill: only a recorder writes into a log. `pred_arguments` saves only `capacity`, so a loaded window starts with an empty log of the same size.

## Design decisions

- **A decorator, not code in the editor loop.** The editor has no reference to a log or a panel. A recorder in `Editor.run_evaluate_stage!` was rejected, because it puts a view concern in the loop. A `GestureLogOperation` beside the real operation was rejected, because an operation changes the edited document and the log is not part of it. See [plan/done/gesture-log-overlay.md](../../../../plan/done/gesture-log-overlay.md).
- **Two decorators share one log.** The complete record exists only at the root, and the panel needs a canvas, which only the chain of a window has.
- **An entry holds text.** An operation holds a reference into the document, and the document changes when the operation runs. A live operation would print differently a moment later.
- **The panel is an element of the window canvas.** The help window and the tooltip open a window of their own; the log stays over the content that it describes.
- **The panel is a rectangle and a text canvas, not a `WidgetCard`.** A card stretches to the width that its parent gives.
- **The shell records always.** A tab that opens the log must hold what happened before it opened. See [plan/done/the-gesture-log-opens-in-a-tab.md](../../../../plan/done/the-gesture-log-opens-in-a-tab.md).

## Usage

```julia
log = GestureLog(; capacity = 20)
window = GestureLogOverlayProjection(inner = window_projection, log = log)  # for each window
root = GestureLogRecordingProjection(inner = composed, log = log)           # once, at the root
run_example("json"; gesture_log = true, gesture_log_capacity = 40)
```

- Example: the `gesture_log` keyword of `run_example`. The package has no example of its own.
- Test: `test_gesture_log()` in `test/projectured/projection/GestureLogProjectionTest.jl`. The package has no test suite of its own.

## Limits

- The overlay adds no step to a mapped reference. No graphics projection returns a structural graphics reference, so no path needs the extra step; one that returns such a path would get a wrong one.
- The filter drops every selection. A log that must show the selection needs a filter of its own, and the printer then mutes those lines.
