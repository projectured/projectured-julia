# Widget button hover + press feedback (workbench and everywhere)

## Problem

In the omnetpp-julia **workbench SDL example**, buttons don't highlight on hover, and
clicking runs the action but gives no press feedback. In projectured-julia's
`widget_example`, hover works. The buttons are the same `WidgetButton`s from
projectured-julia — the difference is the projection chain and the containers the
buttons are nested in.

A `WidgetButton` reader sets its transient `hovered` cell on `MouseEnter`/`MouseLeave`
and its `pressed` cell on `MouseDown`/`MouseUp` (`WidgetToGraphics.jl` ~1143-1150). The
printer picks the surface fill from those cells. For a button to react, the containers
above it must (a) deliver `MouseEnter`/`MouseLeave` crossings and (b) deliver raw
`MouseDown`/`MouseUp`. And *crossings only exist* if a `WidgetHoverTrackingProjection`
wraps the pipeline to synthesize them from raw `MouseMove`.

### Two root causes

1. **No hover tracker in the workbench.** `widget_example`'s projection ends with
   `ChainingProjection(WidgetHoverTrackingProjection(inner = inner))`
   (`package/visual/example/projection/Widget.jl:17-19`). The workbench's
   `content_projection` (`omnetpp-julia/watch/workbench_sdl.jl:116`) does not wrap the
   pipeline in the tracker, so raw `MouseMove` is never turned into
   `MouseEnter`/`MouseLeave`. → `hovered` never flips.

2. **Containers on the workbench button path swallow the events.** The workbench nests
   buttons: `WidgetScrollPane`(viewport) → `VerticalLayout` → `WidgetCard` →
   `VerticalLayout` → `HorizontalLayout` → `WidgetButton`. Event routing across these
   containers is inconsistent:

   | Container | MousePress | Move | Enter/Leave | Down/Up |
   |---|---|---|---|---|
   | ScrollPane Viewport (`WidgetToGraphics.jl:5823`) | ✓ translated | ✓ translated | forwarded **untranslated** | ✓ translated |
   | Vertical/HorizontalLayout (`LayoutToGraphics.jl:251` `_route_layout_event`) | ✓ | ✓ | ✓ | ✗ dropped |
   | WidgetCard (`WidgetToGraphics.jl:3533`) | ✓ (`:3511`) | ✗ | ✗ | ✗ dropped |

   `MousePress` reaches the button (action fires), but crossings die at the Card and
   down/up die at both the Card and the layouts. Even adding the tracker (cause 1) would
   not fix hover for buttons inside a Card, because the Card drops the synthetic
   crossings.

## Fix

### Fix #1 — Hover
- **projectured-julia**
  - `WidgetCardToGraphicsCanvas` generic reader: route `MouseMove` / `MouseEnter` /
    `MouseLeave` to hit children (like a layout does) instead of returning `nothing`.
  - `WidgetScrollPaneToGraphicsViewport` reader: translate `MouseEnter` / `MouseLeave`
    coords into the scrolled content frame (currently they fall to `_ => evt` and are
    forwarded untranslated — wrong once the pane is offset or scrolled).
- **omnetpp-julia**
  - Wrap `content_projection`'s result in `WidgetHoverTrackingProjection`
    (`watch/workbench_sdl.jl`), matching `widget_example`.

### Fix #2 — Press feedback
- **projectured-julia**
  - Layout containers (`_route_layout_event`, `LayoutToGraphics.jl`): route
    `MouseDown` / `MouseUp` to the hit child (new `_route_downup` helper; import
    `MouseDown`, `MouseUp`).
  - `WidgetCardToGraphicsCanvas` generic reader: route `MouseDown` / `MouseUp` to hit
    children (new `_route_downup_to_children` helper in `WidgetToGraphics.jl`).
  - (ScrollPane Viewport already forwards down/up translated — no change.)

Precondition (being verified): the live editor delivers raw `MouseDown`/`MouseUp` to
`read_intent`, not only the composed `MousePress`. If it only delivers `MousePress`,
Fix #2 must instead derive `pressed` from the gesture — TBD by the editor trace.

## Verification
- projectured-julia targeted test: build `WidgetCard` → layout → `WidgetButton`, print,
  drive `MouseEnter` and `MouseDown` at the button's coords through the container
  reader / tracker, assert `hovered` / `pressed` ops come back. Plus existing
  `WidgetButtonTest`, layout, card tests — no regressions.
- omnetpp-julia e2e: with `[sources]` temporarily pointed at this worktree, drive one
  `MouseMove` over a workbench button through the full `content_projection` and assert a
  `hovered` op is returned.

## Progress
- [x] Editor event-delivery confirmed — the loop delivers `MouseDown` → `MouseUp` →
  `MousePress` to `read_intent` (recognizer passes raw down/up through and *adds* the
  click; `Editor.jl` `read!`, `GestureRecognizer.jl` `recognize_gesture!`). So Fix #2's
  down/up routing is exercised live.
- [x] Fix #1 projectured-julia — `WidgetCard` generic reader routes
  MouseEnter/MouseLeave/MouseMove to hit children; `WidgetScrollPaneToGraphicsViewport`
  translates MouseEnter/MouseLeave into the content frame.
- [x] Fix #1 omnetpp-julia — `content_projection` wrapped in
  `WidgetHoverTrackingProjection` (+ import).
- [x] Fix #2 projectured-julia — layouts (`_route_layout_event` + `_route_downup`) and
  `WidgetCard` (`_route_downup_to_children`) route MouseDown/MouseUp to hit children.
- [x] Routing test added — two testsets in `WidgetButtonTest.jl` (layout depress;
  card hover+press), button located from the rendered iomap (no hard-coded offsets).
- [x] Targeted tests green — new testsets 3/3 + 4/4; full `test_visual()`
  **49236 Pass / 0 Fail / 0 Error / 1 Broken** (known) — zero regressions.
- [x] Workbench e2e — with the watch env's `ProjecturedVisual` source repointed at this
  worktree, the changed `workbench_sdl.jl` loaded, `content_projection(...)` returned a
  `WidgetHoverTrackingProjection`, and `write_workbench_image()` rendered the whole
  tracker-wrapped panel to a PNG (2 runs, 1 series) with no errors. (Repoint reverted;
  the committed omnetpp-julia change is only `workbench_sdl.jl`.)

## Decisions / notes discovered during implementation
- The container routing was inconsistent across the whole widget kit, not just the
  workbench path: `WidgetTabbedPane`, `WidgetComposite`, `WidgetSplitPane` already
  routed down/up; layouts and `WidgetCard` did not; the Card swallowed crossings too.
  Fix targets the workbench path (ScrollPane-viewport → Layout → Card → Layout →
  Layout → Button) but the layout + card changes benefit every nested interactive
  widget.
- The Card comment previously called swallowing hover/press deliberate ("as before");
  it was really an untested gap — a Card was only ever a static display container
  before the workbench put interactive buttons inside one.
- The ScrollPane **viewport** already *forwarded* crossings (via `_ => evt`) but
  untranslated; the fix only corrects the coordinates (matters once scrolled/offset).
