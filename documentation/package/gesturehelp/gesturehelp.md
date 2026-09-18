# The gesture help and the command palette

> **Kind:** reference · **Status:** current · **Stands on:** [concepts.md](../../design/concepts.md)

The two lists a person opens while they work: F1 shows every key that works where the selection is now, and Ctrl+Shift+P runs a command by its name. Both are projections over the running editor, not tables written by hand.

## Why they are projections

A key press goes to the view under the selection, and each view says which keys it takes. So the true list of keys depends on where the selection is, and a list written by hand goes stale the moment a projection changes.

Instead, the decorator asks the editor what it would do with each gesture at the current selection. The answer is a set of intents, and each intent carries its description and its domain. `collect_gesture_rows` turns those into `GestureRow` values — the gesture, what it does, and which domain answers it — and `make_gesture_map` makes the document that the help view draws.

## F1: the gesture map

```julia
const HELP_GESTURE = KeyDownPattern(:f1)
```

`GestureHelpDecoratorProjection` wraps a projection. It passes every gesture through, except F1, which opens the gesture map in a window of its own. The map follows the selection while it is open, so moving the selection changes the list.

An application wraps its own projection:

```julia
projection = GestureHelpDecoratorProjection(inner_projection)
```

`make_gesture_map_projection(measure)` is the projection of the map window itself, which the window manager needs when it opens that window.

## Ctrl+Shift+P: the command palette

```julia
const COMMAND_PALETTE_GESTURE = KeyDownPattern(:p, [:ctrl, :shift])
```

`CommandPaletteDecoratorProjection` works the same way. The palette lists the same intents, filtered by what a person types, and Enter runs the selected one. It is how a command with no key of its own is reached.

`build_command_palette_selection` computes the filtered list, and `get_command_palette_selected` answers the row that Enter runs.

## What a domain must do to appear

Nothing beyond declaring its gestures. A gesture declared with `@gestures` carries its description, and that description is what both lists show. A gesture with no description appears with its key alone, which is a reason to write one.

## Where to look

| File | What it holds |
| --- | --- |
| `source/gesturehelp/GestureMap.jl` | the rows and the document of the map |
| `source/gesturehelp/GestureMapToSyntax.jl` | how the map is drawn |
| `source/gesturehelp/GestureHelpDecorator.jl` | the F1 wrapper and its state |
| `source/gesturehelp/CommandPalette.jl` | the palette document and its filter |
| `source/gesturehelp/CommandPaletteDecorator.jl` | the Ctrl+Shift+P wrapper |

[keyboard-and-mouse-guide.md](../../guide/keyboard-and-mouse-guide.md) is the same subject for a user of the editor.
