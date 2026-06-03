# Tooltip Support — Remaining Work

> The v1 design (see [plan/done/tooltip.md](../done/tooltip.md)) is in
> place: `TooltipSource`, `TooltipDecoratorProjection`,
> `WindowManagerProjection`, `OpenWindowOperation` / `CloseWindowOperation`,
> the `:tooltip` window flag, and the path-tooltip example. This document
> captures the items from the original plan that did **not** get done.

---

## Step 1 (cont.) — Backend `:tooltip` style

Currently `_WINDOW_FLAGS_TOOLTIP` in
[program/src/backend/Sdl.jl](../../program/src/backend/Sdl.jl) sets
`SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_ALLOW_HIGHDPI`.

Missing:

- **Non-focusable / no-input-focus behaviour.** Clicking the tooltip
  currently steals focus from the main window. Candidates:
  `SDL_WINDOW_UTILITY`, `SDL_WINDOW_SKIP_TASKBAR`, or platform-specific
  hints (`SDL_HINT_WINDOWS_NO_CLOSE_ON_ALT_F4`, `_NET_WM_WINDOW_TYPE_TOOLTIP`).
  Pick what actually keeps focus on the main window across SDL's
  X11 / Wayland / macOS / Windows backends.
- **`screen_origin(backend, id)` helper** — returns the on-screen origin of
  a given native window so tooltip positions can be expressed in
  screen-relative coordinates. Needed by Step 6 below.

## Step 6 — Real position derivation

Today the example tooltip uses a fixed `(100, 100, 1200, 200)` placement
inside `_multi_window_projection_tooltipped` in
[example/src/Examples.jl](../../example/src/Examples.jl). The plan called
for the position to be derived from the decorated node's screen
coordinates.

Required:

- Surface enough of the iomap chain so the decorator can look up the
  selected character's pixel coordinates via the relevant
  `TextToGraphicsIoMap.char_to_coord` (or whatever leaf iomap holds the
  geometry).
- Combine with `screen_origin(backend, :<main_window_id>)` to land in
  screen-absolute coordinates.
- Clamp to display bounds via `sdl_display_size` (or the per-monitor
  variant, once that exists).
- Use `(width, height) = (0, 0)` so the backend's auto-size path picks
  the actual content size — currently disabled by the hard-coded
  `1200 × 200`.

## Step 5 (cont.) — Verify show delay with examples

The delay-gate is implemented but the verification the plan asked for
isn't:

- An "always-on" trigger that opens the window only after `delay_ms`
  elapses.
- A "flicker" trigger that flips on every selection move and therefore
  never crosses the delay threshold.

Plus tests covering both cases in [TooltipTest.jl](../../test/src/projection/TooltipTest.jl).

## Step 7 (cont.) — Additional example tooltips

Only the **path tooltip** ships today. The other three example tooltips
from the original plan are still open:

- **Type tooltip** — show inferred schema / type for the selected JSON or
  table node.
- **Error tooltip** — show validation errors on a node.
- **Documentation tooltip** — for a Julia call node, show the docstring
  (likely reuses an existing Julia documentation projection).

Each is a different `TooltipSource.content` + possibly a new dispatcher
entry for that content type.

## Step 8 (cont.) — Multi-tooltip test

Architecturally supported (decorator state is keyed by `source.id`), but
no test exercises it. Add a scenario with two `TooltipSource` wrappers in
different sub-trees, each with a distinct `id`, and assert the manager
keeps both windows open and closed independently.

## Step 9 — Optional: pointer-based hover

Still deferred from the original plan; revisit only if a real use case
appears.

- A `HoverTrackingProjection` whose reader updates a `hovered::Reference`
  cell on the input `ScreenDocument` in response to `MouseMotion`
  envelopes.
- Tooltip triggers can then read `hovered` instead of `selection`.
- Routing `MouseMotion` events into the tree by position is the same
  reverse-projection plumbing that `click-to-select` uses; the work is
  wiring it up for motion as well as buttons.

## Open Questions still open

- **`MoveWindowOperation`.** Whether continuous tooltip re-positioning is
  worth a third operation type, or whether re-issuing
  `OpenWindowOperation` with the same id (which already updates geometry
  in place) is good enough. Defer until something needs continuous
  tracking.

- **Interactive tooltips.** v1 drops envelopes targeted at the tooltip
  window's content. Interactive tooltips would route those envelopes into
  the same `WindowDocument.content` sub-iomap that any other window uses
  — since the content is already a regular document, the existing
  routing should work; the only question is whether the tooltip's
  `is_open` state should react to focus / clicks.

- **Where the `TooltipSource` lives in the input tree.** Wrapping
  individual nodes (`TooltipSource(child=...)`) is conceptually clean
  but requires explicit decoration at every potential tooltip site —
  intrusive for use cases like "tooltip on every JSON value". An
  alternative is a single top-level `TooltipSource` that holds a
  reference to the currently-anchored sub-tree; the trigger becomes a
  comparison against the selection. Decide which use cases warrant
  which shape (likely both, with different decorator variants).

- **Pointer tracking precision.** SDL motion events are coarse;
  correctly mapping them through the projection to a `Reference`
  requires the same reverse-projection plumbing as click-to-select.
  The plumbing exists; the work is wiring it up for motion as well as
  buttons.

- **Tooltip outliving its trigger.** A "pinned" tooltip that survives
  the trigger going false could be promoted to an ordinary
  `WindowDocument` (i.e. the decorator stops emitting
  `CloseWindowOperation` for it). Out of scope until needed.
