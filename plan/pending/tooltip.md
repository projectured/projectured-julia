# Arbitrary Tooltip Support on top of Multiple Windows

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> **Prerequisite:** This plan assumes [multiple-windows.md](multiple-windows.md)
> is implemented. `ScreenDocument` / `WindowDocument`, the backend window
> reconciler, `EventEnvelope`, and the
> `RecursiveProjection(TypeDispatchingProjection(...))` pipeline shape are taken
> for granted here.

## Summary

A tooltip is just another `WindowDocument` with `style = :tooltip` that the
pipeline emits when some trigger condition holds and omits otherwise. The
backend reconciler already opens, moves, resizes, and closes the native window;
this plan only has to answer three tooltip-specific questions:

1. **When to show** — what condition makes a tooltip's `WindowDocument`
   appear in the `ScreenDocument`.
2. **What to show** — what document goes into its `content`, and which
   projection renders it.
3. **Where to place it** — how the `WindowDocument`'s `x`, `y`, `width`,
   `height`, and `style` are derived from the current state (selection,
   cursor position, content size).

All three are expressible as a projection that takes a `ScreenDocument` in and
emits a `ScreenDocument` out with zero or one extra `WindowDocument` appended.
No new output type, no backend changes, no new event routing.

---

## Motivation

Before multiple windows, supporting tooltips meant inventing a multi-canvas
output type *and* teaching the backend to manage extra windows. With multiple
windows in place, the same need reduces to "emit one more
`WindowDocument`" — a much smaller change that reuses the existing
reconciliation, event envelope, and per-window style mechanisms.

The goal of this plan is therefore narrower:

- Give projections a clean way to add/remove a tooltip window.
- Keep tooltip content, position, and trigger inside the projection layer,
  not in the editor or the backend.
- Stay consistent with the rule from multiple-windows.md that "every 'open
  a window' feature is 'add a `WindowDocument`'".

---

## Design

### Tooltip as an appended `WindowDocument`

Pipeline shape after multiple-windows:

```
ScreenDocument(input) → RecursiveProjection(TypeDispatchingProjection(
    ScreenDocument => CopyingProjection(),
    WindowDocument => CopyingProjection(),
    Any            => domain_projection,
)) → ScreenDocument(output, with each WindowDocument.content rendered)
```

A tooltip is introduced by wrapping the `ScreenDocument` case so its output
windows list gets an extra entry when triggered:

```julia
projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => TooltipDecoratorProjection(
            inner    = CopyingProjection(),
            trigger  = (screen, selection) -> ...,
            content  = (screen, selection) -> ...,
            position = (screen, selection) -> (x, y, w, h),
            style    = :tooltip,
            id       = :tooltip,
            delay_ms = 300,
        ),
        WindowDocument => CopyingProjection(),
        Any            => domain_projection,
    )
)
```

`TooltipDecoratorProjection`'s printer:

1. Runs `inner` to get the copied `ScreenDocument`.
2. Evaluates `trigger` over the input + current selection.
3. If triggered (and the show-delay timer has elapsed), builds a
   `WindowDocument` whose `content` is the result of `content(...)`,
   `style = :tooltip`, position from `position(...)`, and `id` as given.
   Appends it to `windows`.
4. If not triggered, omits the entry. The backend reconciler closes the
   tooltip window on the next frame.

Its reader is `inner`'s reader: tooltip windows are read-only in v1.
Events arriving via an envelope whose `window_id == :tooltip` are dropped
at the editor level.

Crucially: `content(...)` returns a `Document`, not a `GraphicsCanvas`.
The outer `RecursiveProjection(TypeDispatchingProjection(...))` projects it
the same way as any other window's content — through the type dispatcher and,
ultimately, `domain_projection` (or a different dispatcher entry, see below).

### Hover vs selection as the trigger

The selection cursor is already a first-class concept; the mouse pointer is
not. Two natural sources for triggers:

- **Selection-based**: trigger fires when the caret has been on a particular
  reference for `delay_ms`. Reuses existing selection plumbing; no new event
  types. Less faithful to a "hover" UX but is what the user already controls.
- **Pointer-based**: requires routing `MouseMotion` events into a hover-state
  cell on the input `ScreenDocument` (e.g. `hovered::Reference`).
  `read_from_devices` already emits motion; a `HoverTrackingProjection` reader
  could maintain the cell.

v1 picks selection-based. The trigger function signature stays
`(screen, selection) -> Bool`. Pointer-based tooltips can be added later by
swapping in a different trigger and feeding it a separately tracked
`hovered` cell.

### Show delay

The trigger may flip rapidly while the user moves the caret. To avoid flicker:

- The decorator owns a `Cell{Union{Nothing,Float64}}` holding the wall-clock
  timestamp at which `trigger` last became true.
- On each `projection_print`:
  - If `trigger` is false → clear the timestamp, omit the window.
  - If `trigger` is true and the timestamp is `nothing` → set it to `time()`,
    omit the window this frame.
  - If `trigger` is true and `time() - timestamp >= delay_ms / 1000` →
    emit the tooltip window.
- The REPL's frame loop pulls `projection_print` on every iteration after
  multiple-windows' "drain events per frame" change, so the tooltip naturally
  appears on the first frame after the delay has elapsed.

This is the "sample wall-clock in the printer" option from the original plan
(option (a) of the old Open Questions). It is pragmatic but means the
projection output depends on `time()`, which the reactive cell system
otherwise does not see. Document the limitation; a `TimerCell` abstraction
can be added later if it becomes a real problem.

### Position

`position(screen, selection)` returns `(x, y, width, height)` in screen
coordinates. The decorator needs:

- The screen-coordinate position of the selection, which the IoMap's
  `char_to_coord` already gives in window-local coordinates.
- The main window's screen-coordinate origin, exposed by the backend via
  something like `screen_origin(backend, id::Symbol)` — a small addition.
- Clamping to screen bounds: callee's responsibility, or a shared helper.

Width/height can be `0` (auto-size from content canvas — already supported
by the multi-windows plan via `WindowDocument(width=0, height=0)`).

### Style

`WindowDocument.style = :tooltip` is already part of multiple-windows'
schema. The backend's `_apply_style!(:tooltip, ...)` is the right place for
borderless / always-on-top / non-focusable flags
(`SDL_WINDOW_BORDERLESS`, `SDL_WINDOW_ALWAYS_ON_TOP`, `SDL_WINDOW_TOOLTIP`
where supported). That belongs in the multiple-windows implementation rather
than here; this plan just consumes the style.

### Multiple simultaneous tooltips / preview panels

Trivial under multi-windows: stack multiple `TooltipDecoratorProjection`s
(each with its own `id` like `:type_tooltip`, `:error_tooltip`, `:preview`),
or have one decorator return multiple appended windows. Each id is reconciled
independently by the backend.

### Per-tooltip content projections

If the tooltip content needs a *different* projection than `domain_projection`
(e.g. a JSON-path string is rendered by a text projection while the main
window uses a tree projection), do not add new projection types. Instead,
either:

- Add another entry to the `TypeDispatchingProjection` keyed on the tooltip
  content's concrete document type, or
- Have `content(...)` return a document of a type that the dispatcher already
  routes appropriately.

This stays consistent with multiple-windows' "no per-window content
projection dispatch in a new type".

---

## Implementation Steps

### Step 1 — `:tooltip` style on the backend

Pre-work in `SdlBackend._apply_style!`: borderless, always-on-top,
non-focusable (where the platform allows). Add `screen_origin(backend, id)`
or equivalent so tooltip positions can be expressed in screen coordinates
relative to the main window.

Strictly speaking this belongs to multiple-windows; capture it here in case
that plan does not land it.

### Step 2 — `TooltipDecoratorProjection` skeleton

- Struct with `inner`, `trigger`, `content`, `position`, `id`, `style`,
  `delay_ms`, and the timestamp cell.
- Printer: implement steps 1–4 of "Tooltip as an appended `WindowDocument`"
  without delay logic (treat `delay_ms = 0`).
- Reader: pass through to `inner`'s reader; drop envelopes whose
  `window_id == id`.
- Smoke test: a JSON example with a trigger that always returns `true`
  showing the path of the selected node in a small window.

### Step 3 — Show delay

- Add the timestamp cell; gate emission on elapsed time.
- Verify with two example triggers: one that is always-on (window appears
  after `delay_ms`), and one that flips on every selection move (no window
  ever appears under reasonable mouse movement).

### Step 4 — Position derivation

- Surface enough of the IoMap and backend window origin to compute
  `(x, y)` near the selection's screen coordinates.
- Clamp to screen bounds via SDL display info.
- `(width, height) = (0, 0)` for auto-sizing.

### Step 5 — Example tooltips

Each is just a different `content` + (possibly) dispatcher entry:

- **Path tooltip**: for the selected JSON node, show its JSON path as a
  short string document.
- **Type tooltip**: show inferred schema/type.
- **Error tooltip**: show validation errors on a node.
- **Documentation tooltip**: for a Julia function call node, show its
  docstring (reuses any existing Julia documentation projection).

### Step 6 — Multiple simultaneous tooltips

- Compose two `TooltipDecoratorProjection`s and verify the reconciler keeps
  both windows open / closed independently.
- Confirm id collisions are reported as bugs (multiple-windows step already
  asserts this at the screen level).

### Step 7 — Optional: pointer-based hover

- A `HoverTrackingProjection` whose reader updates a `hovered::Reference`
  cell on the input `ScreenDocument` in response to `MouseMotion` envelopes
  on the main window.
- Tooltip triggers can then read `hovered` instead of `selection`.
- Defer until selection-based tooltips are exercised in practice.

---

## Open Questions

- **Where does the show-delay timestamp live?** On the
  `TooltipDecoratorProjection` struct (per projection instance, leaks across
  iomaps), in the iomap (rebuilt each frame, would need explicit carry), or
  on the input `ScreenDocument` (intrusive). The first is the simplest and
  matches how other projection state is held; reconsider only if it causes
  trouble.

- **Time in the reactive system.** The cell graph is event-driven; sampling
  `time()` in the printer breaks that purity. Acceptable for v1; a
  `TimerCell` that self-invalidates after a duration is the principled fix
  if frame cadence proves unreliable.

- **Interactive tooltips.** v1 drops envelopes targeted at the tooltip
  window. Interactive tooltips (click-through links, scroll) would either
  forward those envelopes into a sub-projection rooted at the tooltip's
  content (likely the right design, since the content is already a regular
  document) or run the tooltip as its own `Editor`. The former is much
  simpler and is preferred when v2 is needed.

- **Pointer tracking precision.** SDL motion events are coarse; correctly
  mapping them through the projection to a `Reference` in the input
  document requires the same reverse-projection plumbing as
  click-to-select. That plumbing already exists; the work is wiring it up
  for motion as well as buttons.

- **Tooltip outliving its trigger.** If `content(...)` recomputes per frame
  it stays in sync with whatever the trigger was based on. If the user
  wants a "pinned" tooltip that survives selection changes, it becomes an
  ordinary `WindowDocument` controlled by a different mechanism — out of
  scope here.

---

## Relationship to the Multiple Windows Plan

| Concern | Multiple windows handles | This plan adds |
|---------|--------------------------|----------------|
| Multi-window output type | `ScreenDocument` / `WindowDocument` | — |
| Opening / closing native windows | `write_to_devices(::ScreenDocument)` reconciler | — |
| Per-window event routing | `EventEnvelope { window_id, event }` | Drops envelopes for tooltip window in v1 |
| Per-window style | `WindowDocument.style` + `_apply_style!` | Defines `:tooltip` style semantics (borderless, on-top, non-focusable) |
| Per-window position / size | `WindowDocument.x/y/width/height` | Tooltip-specific `position` function and screen-coordinate helper |
| Trigger to show a window | Out of scope — push/remove `WindowDocument` | `TooltipDecoratorProjection.trigger` + show-delay timestamp |
| What goes in the tooltip | Out of scope — any `Document` | `content` function returning a document; rendered via the existing type dispatcher |
| Multiple tooltips at once | Trivial — multiple `WindowDocument`s | Compose multiple decorators |

Net effect: this plan goes from inventing a new output type + backend
machinery to writing one new projection (`TooltipDecoratorProjection`) plus
the `:tooltip` style hookup on the backend.
