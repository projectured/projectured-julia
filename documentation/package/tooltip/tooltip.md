# Tooltip

> **Kind:** design · **Status:** current · **Stands on:** [screen.md](../screen/screen.md), [shell.md](../shell/shell.md)

`ProjecturedTooltip` shows a tooltip in a window of its own. It has two mechanisms: a probe that asks the document under the pointer for its tooltip, and a wrapper document with an explicit trigger. This document says how each one works and why both exist.

## How it works

### The probe

`TooltipProbeProjection` wraps the content projection of a window. It has no document of its own and it prints the content unchanged. **It gives every event to the content first**, so a hover, a drag and a click work under it as they do without it. It only watches the pointer: a move notes where the pointer is and when, and a move away from an open tooltip, a press, a key and a scroll close it.

**A tooltip opens only after the pointer rests.** A resting pointer sends no event, so the time comes from the editor's loop. A `TooltipFeed`, made with `make_tooltip_feed(; delay = 0.5)`, names a deadline: the last move plus the delay, while no tooltip is shown. The loop sleeps until that deadline and no longer, and an idle window names none. At the deadline the feed reads a `PointerRest(x, y)` through the editor's projection and posts the operation that comes back. The probe answers the rest:

1. it makes a left press with the Alt key at the resting point and reads it through the content chain, without applying it;
2. it takes the path of the `ReplaceSelectionOperation` that comes back, which names the innermost document under the pointer;
3. it calls `compute_tooltip(document)` on that document;
4. it opens a window with the answer next to the pointer, or nothing when the answer is `nothing`.

The press has the Alt key because a plain press is the action gesture of a widget: it would press a button. An Alt+press only selects. The probe and the feed share one `TooltipRest`, so the host hands the same feed to the probe and to `run_window_editor(feeds = …)`.

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
feed = make_tooltip_feed()
probe = TooltipProbeProjection(; inner = content_projection,
                               compute_tooltip = compute_tooltip,
                               pointer = () -> get_pointer_position(backend),
                               feed = feed)
run_window_editor(document, probe, "Title"; backend = backend, feeds = Feed[feed])
```

`pointer` returns the pointer in screen coordinates; the host supplies it. `ProjecturedShell` builds the probe for you when the fold gets `tooltip`, `pointer` and `tooltip_feed`.

- Tests: `test_tooltip()` for the wrapper; `test_tooltip_probe()`, `test_tooltip_feed()`, `test_widget_tooltip()` and `test_julia_tooltip()` for the probe and its feed.

## Limits

- The default `position` of the wrapper is a fixed rectangle at the corner. A caller must give a position function.
- `plan/pending/tooltip.md` lists the open steps of the wrapper: the window flags of the `:tooltip` style in the SDL backend, and more examples and tests.
