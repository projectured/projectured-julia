# Tooltip

> **Kind:** design · **Status:** current · **Stands on:** [screen.md](../screen/screen.md), [shell.md](../shell/shell.md)

`ProjecturedTooltip` shows a tooltip in a window of its own. It has two mechanisms: a probe that asks the document under the pointer for its tooltip, and a wrapper document with an explicit trigger. This document says how each one works and why both exist.

## How it works

### The probe

`TooltipProbeProjection` wraps the content projection of a window. It has no document of its own and it prints the content unchanged. On each `MouseMove`, its reader:

1. makes a left press with the Alt key at the pointer and reads it through the content chain, without applying it;
2. takes the path of the `ReplaceSelectionOperation` that comes back, which names the innermost document under the pointer;
3. calls `compute_tooltip(document)` on that document;
4. opens a window with the answer next to the pointer, moves it, or closes it when the answer is `nothing`.

The press has the Alt key because a plain press is the action gesture of a widget: it would press a button. An Alt+press only selects. The probe opens a new window only when the document under the pointer changes, so a pointer that crosses a wide label does not open the tooltip again. The probe has no delay of its own; the backend sends no move while the pointer rests.

`compute_tooltip` is a generic function of `ProjecturedDomain`, and a document gives its own tooltip: a widget returns the text in its `tooltip` field, and a `JuliaFunction` returns its signature. The host gives the generic to the probe as a function value, so this package needs no dependency on the domains that answer it. [shell.md](../shell/shell.md) describes how the shell puts the probe and its twin, the context menu probe, into the window.

### The wrapper

`TooltipSource` wraps a `child`, which stays on the screen, and a `content`, which the tooltip window shows. `TooltipDecoratorProjection` prints the child and calls its `trigger(source, event)` function on each event. When the trigger is true for `delay_ms`, the reader makes an `OpenWindowOperation` with the `id`, the `style` and the content of the source; when it is false again, a `CloseWindowOperation`. The reader of the child comes first: if the child returns an operation, the tooltip change waits for the next event. One decorator keeps a state for each `id`, so sibling sources are independent.

Both mechanisms make ordinary window operations. `WindowManagingProjection` adds or removes a `WindowDocument` with `style = :tooltip`, and the backend shows it.

## How it fits

`ProjecturedTooltip` depends on the kernel and on `ProjecturedScreen` for the window operations. `ProjecturedShell` puts a `TooltipProbeProjection` into the projection of every window. The package registers nothing.

## Design decisions

- **A tooltip is a window.** A tooltip can extend past the edge of the window it describes, and it needs no drawing layer inside the window. See the invariant `PAR-MANY-WINDOWS` and `plan/done/tooltip.md`.
- **The document computes its tooltip.** The probe needs no wrapper around each node, so every document can have a tooltip without a change of its tree. The wrapper is the older mechanism, and it stays for a tooltip with its own trigger.
- **The state is on the projection.** The open window and the last document are not data of the document, as for a drag.

## Usage

```julia
probe = TooltipProbeProjection(; inner = content_projection,
                               compute_tooltip = compute_tooltip,
                               pointer = () -> get_pointer_position(backend))
```

`pointer` returns the pointer in screen coordinates; the host supplies it. `ProjecturedShell` builds the probe for you.

- Tests: `test_tooltip()` for the wrapper, `test_tooltip_probe()`, `test_widget_tooltip()` and `test_julia_tooltip()` for the probe.

## Limits

- The probe takes every `MouseMove` and does not pass it on. So a hover highlight or a drag of a divider below the probe gets no move. `plan/pending/hover-drag-and-tooltip-share-the-pointer.md` describes the fault and a fix.
- The default `position` of the wrapper is a fixed rectangle at the corner. A caller must give a position function.
- `plan/pending/tooltip.md` lists the open steps of the wrapper: the window flags of the `:tooltip` style in the SDL backend, and more examples and tests.
