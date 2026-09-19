# Tooltip Support — Remaining Work

> **Status (2026-08-12): IN PROGRESS.** Steps 1, 6, 5, 7, and 8 below are
> still open — re-checked directly against the current tree, same gaps as
> the last check. Step 9 is done (see its own section). Paths are updated for
> the current package layout (`package/sdl/main/`, `package/projectured/example/Gallery.jl`,
> `package/substrate/test/projection/TooltipTest.jl`).

> The v1 design (see [plan/done/tooltip.md](../done/tooltip.md)) is in
> place: `TooltipSource`, `TooltipDecoratorProjection`,
> `WindowManagerProjection`, `OpenWindowOperation` / `CloseWindowOperation`,
> the `:tooltip` window flag, and the path-tooltip example. This document
> captures the items from the original plan that did **not** get done.

> **A second mechanism exists since 2026-09-19**, from
> [both-binaries-offer-one-interface.md](both-binaries-offer-one-interface.md).
> `TooltipProbeProjection` asks the document under the pointer what it says
> about itself, through the `compute_tooltip(document)` generic that every
> document answers: a widget reads a field somebody set, and every other
> document computes one. `ProjecturedShell`'s fold composes it, so a binary asks
> for a tooltip by keyword. **The probe places its window beside the pointer, in
> screen coordinates, and always in a window of its own** (`PAR-MANY-WINDOWS`).
> What that closed and what it did not is written on each step below.

---

## Step 1 (cont.) — Backend `:tooltip` style

**⏳ OPEN (re-verified 2026-08-12):** `_WINDOW_FLAGS_TOOLTIP` in
[package/sdl/main/ProjecturedSdl.jl:481](../../package/ProjecturedSdl/src/ProjecturedSdl.jl)
still only sets `SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP |
SDL_WINDOW_ALLOW_HIGHDPI` (plus `SDL_WINDOW_SHOWN`) — no UTILITY/SKIP_TASKBAR/no-input-focus flag. No
`screen_origin` symbol exists anywhere in `package/` (grep finds it only in plan
docs). Both sub-items below remain open.

**Written 2026-09-19, and not verified on a live display.** The flag set is
named rather than numbered, and it is `SDL_WINDOW_SHOWN | BORDERLESS |
ALWAYS_ON_TOP | SKIP_TASKBAR | TOOLTIP | ALLOW_HIGHDPI`.

**The number the comment named was the wrong one.** Both the tooltip style and
the floating style carried `0x00000400` under a comment that called it
`SDL_WINDOW_ALWAYS_ON_TOP`. It is `SDL_WINDOW_MOUSE_FOCUS`, which SDL *reports*
about a window and never accepts when one is made, so neither style was ever on
top. `SDL_WINDOW_ALWAYS_ON_TOP` is `0x8000`.

- **Non-focusable / no-input-focus behaviour.** `SDL_WINDOW_TOOLTIP` and
  `SDL_WINDOW_SKIP_TASKBAR` are what tell a window manager to leave the keyboard
  where it is. **Still to check on a display**: a run against the owner's live
  display hung in `X11_ShowWindow`, so the behaviour is written and not
  measured.
- **`screen_origin(backend, id)` helper** — **not needed, and not added.** SDL's
  `get_pointer_position` already answers in screen coordinates, and the web
  backend answers no pointer at all, so nothing called the helper after it was
  written. It was removed again.

**Two measurements wait for an idle machine and the owner's word**, and they are
what is left of this mechanism's verification:

1. **The focus behaviour.** Whether the main window still holds
   `SDL_WINDOW_INPUT_FOCUS` after a tooltip window opens, for each flag set. The
   script stands at `scratchpad/focus.jl`. A run against the owner's live display
   hung in `X11_ShowWindow`, and two probes were killed at their timeout.
2. **What the probe costs on a pointer move.** It reads the document under the
   pointer at every idle motion, and nothing has measured that.

## Step 6 — Real position derivation

**⏳ OPEN (re-verified 2026-08-12):** `_multi_window_projection_tooltipped` is now in
[package/projectured/example/Gallery.jl:513-521](../../example/projectured/Gallery.jl)
(moved from `Examples.jl` — that file is gone; the examples now live in
`Gallery.jl`) and still hard-codes `position = _ -> (100, 100, 1200, 600)` — no
`char_to_coord` lookup, no `screen_origin` combination, no display clamp, no
`(0, 0)` auto-size.

Today the example tooltip uses a fixed `(100, 100, 1200, 600)` placement
inside `_multi_window_projection_tooltipped` in
[package/projectured/example/Gallery.jl](../../example/projectured/Gallery.jl).
The plan called for the position to be derived from the decorated node's
screen coordinates.

**Answered for the probe, 2026-09-19, and not for this example.**
`TooltipProbeProjection` opens its window at the pointer plus an offset, in
screen coordinates, so a tooltip of the new mechanism needs no lookup in the io
map chain: the pointer is where the person is looking. The example below still
hard-codes its box, because it belongs to the older mechanism.

Required, for this example:

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

**⏳ OPEN (re-verified 2026-08-12):**
[package/substrate/test/projection/TooltipTest.jl](../../test/substrate/projection/TooltipTest.jl)
has no `delay_ms` always-on trigger, no flicker trigger, and no test exercising
the delay threshold — its triggers are plain `show[]` refs only.

The delay-gate is implemented but the verification the plan asked for
isn't:

- An "always-on" trigger that opens the window only after `delay_ms`
  elapses.
- A "flicker" trigger that flips on every selection move and therefore
  never crosses the delay threshold.

Plus tests covering both cases in [TooltipTest.jl](../../test/substrate/projection/TooltipTest.jl).

## Step 7 (cont.) — Additional example tooltips

**⏳ OPEN (verified):** grep for type/error/documentation tooltip content in
`package/` finds nothing; only the path-tooltip example pipeline exists.

The **documentation tooltip is done**, 2026-09-19, and by the generic rather
than by a source: `compute_tooltip(::JuliaFunction)` answers the signature, and
`compute_tooltip(::JuliaDocstring)` answers the signature and the prose. Two
remain:

- **Type tooltip** — show inferred schema / type for the selected JSON or
  table node.
- **Error tooltip** — show validation errors on a node.

Each is a different `TooltipSource.content` + possibly a new dispatcher
entry for that content type.

## Step 8 (cont.) — Multi-tooltip test

**⏳ OPEN (re-verified 2026-08-12):** `package/substrate/test/projection/TooltipTest.jl` only ever builds a single `TooltipSource`
(ids `:tt` / `:dup`, two occurrences total); no scenario wraps two sources in
different sub-trees, so independent open/close is untested.

Architecturally supported (decorator state is keyed by `source.id`), but
no test exercises it. Add a scenario with two `TooltipSource` wrappers in
different sub-trees, each with a distinct `id`, and assert the manager
keeps both windows open and closed independently.

**The probe does not close this.** `test_tooltip_probe()` drives one probe: a
document that says something opens a window, one that says nothing opens none,
the same document says it once, and leaving it closes the window. Two sources
open at the same time is still untested.

## Step 9 — Optional: pointer-based hover — DONE (via the hover inspector)

**✅ DONE (re-verified 2026-08-12):** `HoverProbeProjection`
([package/inspector/main/HoverProbe.jl](../../source/inspector/HoverProbe.jl)),
`ReferenceInspector` document + test
([package/projectured/test/projection/HoverProbeTest.jl](../../test/projectured/projection/HoverProbeTest.jl)),
the `inspector=true` pipeline
([package/projectured/example/Gallery.jl:556 `_multi_window_projection_inspector`](../../example/projectured/Gallery.jl)),
and throttled idle `MouseMove` forwarding in the SDL backend
([package/sdl/main/ProjecturedSdl.jl:548-549,2569](../../package/ProjecturedSdl/src/ProjecturedSdl.jl))
all exist.

**Implemented** by the hover click-reference inspector — see
[plan/done/hover-click-reference-inspector.md](../done/hover-click-reference-inspector.md).
Rather than a `HoverTrackingProjection` that stores a `hovered::Reference` on the
`ScreenDocument`, the chosen shape is a `HoverProbeProjection` that wraps a
window's content projection and, on each idle `MouseMove`, reverse-projects the
pointer (feeding a synthetic `MousePress` to the wrapped reader) into the
would-be-click reference, then drives a follower window via
`OpenWindowOperation` / `CloseWindowOperation` — the same window-management path
this plan established. The two enabling pieces this step called out are both in:

- Idle `MouseMotion` is now forwarded (throttled) by the SDL backend.
- Routing motion into the tree by position reuses the click reverse-projection.

Run it with `run_example("json"; inspector=true)`.

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
