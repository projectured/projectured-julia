# Gesture help and command palette

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [screen.md](../screen/screen.md), [gesturelog.md](../gesturelog/gesturelog.md)

The gesturehelp slice of `ProjecturedPlatform` holds two lists that a person opens while working: F1 shows the gestures that work where the selection is, and Ctrl+Shift+P runs a command by its name. Both read the live projection chain, not a table written by hand. This document says how the rows are collected, why the help is a window and the palette is an overlay, and how the palette matches a query.

## How it works

Both tools have [the shared shape](../gesturelog/gesturelog.md#the-shared-shape): a document, a transparent decorator, and a view of the document. The decorator does not record or catch. It uses one gesture that the inner reader returned no operation for.

### One list of rows

A key press goes to the view under the selection, and each view has its own gestures. So the true list of keys depends on where the selection is. Both decorators call the inner reader with `Intent(CollectIntents())`, the route that a keystroke takes. Every gesture table on that route returns one `Intent` for each rule, with the operation that the rule builds now, inside a `CollectedIntentsOperation`. Every stage on the way back roots these operations, so each one applies at the input of the decorator. [devices-and-backends.md](../../kernel/devices-and-backends.md#asking-what-is-available) describes the collection.

`collect_gesture_rows` makes one `GestureRow` for each intent: the gesture text, the description, the domain and the operation. The order is the order of the chain, the innermost document first, and a pair of domain and description appears once. A row whose `operation` is `nothing` can not run now: its precondition failed, or it needs the key that carries its argument. No other test of applicability exists.

### F1: the gesture map

`GestureHelpDecoratorProjection(; inner, state, id = :gesture_help, …)` passes the output of `inner` through. Its reader calls the inner reader first. When that returns no operation and the gesture matches `HELP_GESTURE`, which is `KeyDownPattern(:f1)`, the decorator collects the rows, makes a `GestureMap`, and returns an `OpenWindowOperation` whose content is the map. `WindowManagingProjection` opens it as a window beside the content; see [screen.md](../screen/screen.md). A second F1 returns `CloseWindowOperation(id)`.

The open flag is in a `GestureHelpState` that the caller makes and shares, because a pipeline can build the decorator again for each dispatch. The screen that opens the window needs a row for `GestureMap`: `make_gesture_map_projection(measure)` chains `GestureMapToSyntax`, `SyntaxToText`, `WordWrapping` and `TextToGraphics`. `GestureMapToSyntax` prints a heading for each domain and one line for each row. A row with no key shows `by name`, and a row that can not run is muted and ends with `(n/a)`.

### Ctrl+Shift+P: the command palette

`CommandPaletteDecoratorProjection(; inner, measure, state, x = 60, y = 60)` opens on `COMMAND_PALETTE_GESTURE`, which is `KeyDownPattern(:p; modifiers = [:ctrl, :shift])`. While the palette is closed, the inner reader comes first, as in the help. The gesture then fills the one `CommandPalette` of the state with the collected rows, empties the query, and opens the palette.

While the palette is open, the decorator reads first and takes every event, also a key that it has no use for. So the selection of the content does not move while a person types.

| Key | What it does |
| --- | --- |
| a printable character | adds it to the query |
| Backspace | deletes the last character of the query |
| Up, Down | selects the previous or the next matching row |
| Enter | runs the selected row and closes the palette |
| Escape, Ctrl+Shift+P | closes the palette |

To run a row, the reader returns the operation of that row as its own result. Every stage above roots it, as if the key of the binding had fired. A row with no operation does not run, and the palette stays open.

The output is one `GraphicsCanvas` whose first element is the inner output, open or closed. While the palette is open, a second element holds the palette on a panel at `(x, y)`. So a reference that the decorator maps forward always gains the step `elements[1]`. `CommandPaletteState` holds one `CommandPalette` for the life of the editor. The decorator changes it in place and does not replace it, so the IoMap of its chain stays valid. `open` is a `Cell`, because the printer reads it inside a thunk.

### Matching a query

`get_command_palette_matches(palette)` returns the indices of the matching rows. Each word of the query must appear as a contiguous run of characters in `"<description> <domain>"`, without case and in any order. A row ranks first by whether it can run, then by how early its match starts, then by the order of collection. The rows are then grouped by domain, and each group takes the place of its best row.

`CommandPaletteToSyntax` prints the query line `> query▏`, a heading for each domain, and the rows. `▸` marks the selected row, and a row that can not run ends with `(not now)`. The selection of the palette is an ordinary reference to element `i` of `rows`, which `build_command_palette_selection(i)` builds and `get_command_palette_selected` reads back.

### What a domain must do to appear

Nothing but declare its gestures with `@gestures`. The description of a rule is what both lists show, and a rule with no description shows its key alone. A rule with `nothing` in the pattern slot has no key; it appears in the palette by its name.

## How it fits

The gesturehelp slice depends on the kernel and on the collection, graphics, projection, screen, style, syntax and text slices. It takes the collection of intents from the gesture bindings of the kernel, and the window operations from the screen slice.

A window built with `build_editor` adds both decorators only when `gesture_help` or `command_palette` is given as a wrapper. `command_palette` is around the help; [shell.md](../shell/shell.md#the-wrappers-of-a-window) says why. `make_opened_window_projections` of the shell gives the row for `GestureMap`. The gallery adds them with `gesture_help = true` and `command_palette = true`.

It registers nothing: no natural row and no insertion alias. No tab holds either document.

## Design decisions

- **The lists are projections over the live chain.** A list written by hand goes stale when a projection changes. The rows come from the same gesture tables that fire, so what a list shows is what a key does. See [plan/done/reified-gesture-bindings.md](../../../../plan/done/reified-gesture-bindings.md).
- **Applicability is the built operation.** A row runs when its rule built an operation. No predicate exists that could disagree with the rule.
- **The palette is an overlay in the chain of the window, not a window.** `ScreenToScreen` roots every operation that leaves a window under `windows[i].content`. An operation from a palette window would carry the path of the palette window and apply in the wrong place. See [plan/done/command-palette.md](../../../../plan/done/command-palette.md).
- **The help map is a snapshot.** The rows are built once, when F1 is pressed. A map that follows the selection was left for later; press F1 twice to see the list of a new place.
- **A query matches words, not letters.** A match of the query as a subsequence of letters was tried first. It listed almost every row: the letters of `sort` appear in order in `Select the root node`. The ranking put the right row first, but the list did not get shorter.
- **The state is outside the projection.** A pipeline can build the decorator again for each dispatch, and only an object that the caller holds keeps the open flag.

## Usage

```julia
help_state = GestureHelpState()
projection = GestureHelpDecoratorProjection(inner = projection, state = help_state)
projection = CommandPaletteDecoratorProjection(inner = projection, measure = FontFileMeasure())
help_row   = GestureMap => make_gesture_map_projection(FontFileMeasure())   # for the window F1 opens
run_example("json"; gesture_help = true, command_palette = true)
```

- Example: `make_gesture_map_document_example()`, the `GestureMap` of the atomic catalog. The package has no example of its own; the gallery keywords above show both tools.
- Tests: `test_gesture_help()`, `test_gesture_map()`, `test_command_palette()` and `test_command_palette_decorator()` in `test/projectured/projection/`. The package has no test suite of its own.

[keyboard-and-mouse-guide.md](../../../guide/keyboard-and-mouse-guide.md) describes the same tools for a user of the editor.

## Limits

- The help map does not follow the selection while it is open.
- The menu bar of the shell has no item for either tool; only the keys open them. See [shell.md](../shell/shell.md).
