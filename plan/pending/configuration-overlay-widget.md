# Show/hide a projection's configuration as an overlay

> **Status (2026-08-12): NOT STARTED.** Re-verified against the current
> codebase. `WidgetOverlay`, `WidgetOverlayToGraphicsCanvas`,
> `_strip_control_layer`, and the
> `configuration_label`/`is_configuration_gesture`/`configuration_descriptor`
> traits still do not exist anywhere under `package/`. The current
> `ProjectionConfiguringProjection`
> ([package/widget/main/ProjectionConfiguring.jl](../../source/widget/ProjectionConfiguring.jl))
> still builds a `WidgetSplitPane` (printer, line 85), still has
> `_strip_control_slot` (line 140), and still hardcodes the `Ctrl+F` toggle in
> `_toggle_operation` (line 155). The test
> ([package/substrate/test/projection/ProjectionConfiguringTest.jl](../../test/substrate/projection/ProjectionConfiguringTest.jl))
> still asserts `WidgetSplitPane` and `Ctrl+F`. This plan describes the
> intended future work and remains entirely OPEN.

> **Decision (2026-08-12): re-author this plan.** The owner chose to retire
> `ProjectionConfiguringProjection`, see
> [text-projection-config-into-document.md](text-projection-config-into-document.md).
> Part B, the printer swap from `WidgetSplitPane` to `WidgetOverlay`, targets a
> module that goes away. Part A, the generic `WidgetOverlay` widget, and Part C,
> the gesture traits, do not depend on that module. Both can stand against the
> document model.
>
> **Rejected.** Keep the projection so that Part B lands as written.

## Goal

Let the user **show and hide** the configuration UI that
`ProjectionConfiguringProjection` builds for an inner projection
(`make_text_configuring_projection` in
[package/workbench/example/projection/Wrapper.jl](../../example/workbench/projection/Wrapper.jl)),
with two refinements over the current behaviour:

1. **Overlay, don't stack.** The control bar must float *over* the projected
   document instead of reserving layout space above it (today it is the top
   slot of a `WidgetSplitPane`, which reflows the document down).
2. **Per-projection gestures.** Text highlighting, text filtering, etc. each get
   their *own* show/hide gesture and their own label, rather than one shared
   `Ctrl+F` toggle.

Decisions taken (see Open questions resolved):

- Overlay mechanism: **a new content-level z-layered widget** (`WidgetOverlay`).
  No `WindowManager`/`OpenWindowOperation` involvement — the overlay is a pure
  widget-domain concern, rendered and hit-tested inside the same content
  pipeline that renders the document.
- Gesture: **distinct per inner projection** (e.g. highlighting ≠ filtering),
  declared by the inner projection itself and surfaced in F1 context help.

## Current state (what exists today)

[package/widget/main/ProjectionConfiguring.jl](../../source/widget/ProjectionConfiguring.jl):

- **Printer** projects the inner projection (the document) *and* the inner
  projection **object** through a `control` projection (default `ObjectToWidget`)
  into a control widget, then stacks them in a `WidgetSplitPane`
  (`[control_widget, doc_widget]`, control on top).
- **Reader** routes four ways: control checkbox click (`ReplaceReferencedValue`)
  → inner parameter cell; control text edit (`StringReplaceRangeOperation`
  re-rooted at the split pane, stripped by `_strip_control_slot`) → parameter;
  control click (`ReplaceSelectionOperation`) consumed; and a **hardcoded
  `Ctrl+F` toggle / `Escape` hide** that flips the control widget's `visible`
  cell via `ShowWidgetOperation` / `HideWidgetOperation`. Everything else
  delegates to the inner reader.

So show/hide *already works* — but (a) via a single hardcoded gesture, and
(b) inside a split pane, which reserves space rather than overlaying.

`make_text_configuring_projection` wires exactly **one** inner projection per
pipeline (`TextHighlighting("dolor")` or `TextFiltering("dolor")`, chosen by the
example flags in [package/projectured/example/Gallery.jl:249-255](../../example/projectured/Gallery.jl#L249-L255)),
and renders the resulting widget+text tree with a combined `WidgetToGraphics` /
`TextToGraphics` dispatcher.

Reference for the rendering/hit-test pattern a container widget must follow:
`WidgetSplitPaneToGraphicsCanvas` in
[package/widget/main/WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl) (the `WidgetSplitPaneToGraphicsCanvas` projection)
— a `@projection` that lays out children, builds a `ChildrenIoMap`, hit-tests
`MousePress`/`MouseScroll` against each child canvas, forwards coordless events,
and maps references back through the selected child slot.

The gesture-help single-source mechanism is in
the `@event_case` gesture-pattern machinery — now in
[package/kernel/main/event/EventPattern.jl](../../source/kernel/event/EventPattern.jl);
there is no `GestureHelp.jl` file today, and a search for `GestureDescriptor`/
`merge_help` finds zero hits, so the F1-help single-source mechanism this plan
assumes needs re-examining under `package/gesturehelp/` at implementation time:
an annotated `@event_case` rule yields both the firing operation and a
`GestureDescriptor`; `merge_help` unions per-stage lists as they bubble up; F1
opens the list via `GestureHelpPopupProjection`.

## Design

### Part A — `WidgetOverlay`: a z-layered container widget

A new widget document type that stacks its children in **z-order** rather than
flowing them. The first child is the base layer and fills the overlay's area;
subsequent children are overlay layers drawn on top, each positioned (default:
anchored to a corner / offset) and sized to content, **not** reserving space
from the base. A layer whose `visible == false` is not drawn and not hit-tested
(reuse the existing `w.visible == false → _empty_canvas()` convention seen
throughout `WidgetToGraphics`).

New code:

1. **Document** — `@document struct WidgetOverlay <: WidgetDocument` in
   [package/widget/main/Widget.jl](../../source/widget/Widget.jl),
   mirroring `WidgetSplitPane`'s field/ctor shape (`elements::CellVector`, the
   base-kwargs `visible`/`margin`/`border`/`padding`/`selection`, plus per-layer
   placement: an `anchors::CellVector` or `offsets::CellVector` giving each
   non-base layer its `(corner, dx, dy)`). Export it from `WidgetModule`.
2. **Renderer + hit-test** — `WidgetOverlayToGraphicsCanvas` in
   [WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl),
   modelled on `WidgetSplitPaneToGraphicsCanvas` but:
   - **Layout:** base layer gets the full available size; each overlay layer is
     measured at its content size and placed at its anchor/offset. Composite the
     child canvases in order (base first) so later layers paint on top.
   - **Event routing:** hit-test `MousePress`/`MouseScroll` **top layer first**
     (reverse z-order) so a click on the floating control is consumed before the
     document underneath; coordless events (`KeyPress`/`KeyDown`) go to the
     active/selected layer. Map references back through the hit child slot, same
     as the split pane's `map_reference_backward`.
   - Register in the `WidgetToGraphics` dispatch table (like the other
     container widgets) so `make_*` renderers pick it up automatically.

This keeps the overlay a content-domain concern: no screen-level window, no new
operation type — `WidgetToGraphics` already knows how to render and route nested
widget containers.

### Part B — `ProjectionConfiguringProjection`: stack → overlay

In [ProjectionConfiguring.jl](../../source/widget/ProjectionConfiguring.jl):

1. **Printer:** replace the `WidgetSplitPane(p.orientation, [control_widget,
   doc_widget])` with `WidgetOverlay([doc_widget, control_widget]; anchors=...)`
   — base = the projected document, top layer = the control bar, anchored to a
   corner (default top-left; make it a ctor option). The control widget's
   `visible` cell still gates whether it is shown, so the existing
   `ShowWidgetOperation` / `HideWidgetOperation` toggle continues to work
   unchanged — the only behavioural difference is that hiding/showing no longer
   reflows the document.
2. **Reader:**
   - Keep redirect of `ReplaceReferencedValue` and `StringReplaceRangeOperation`
     onto the inner parameter, and consumption of control-bar
     `ReplaceSelectionOperation`. **Update `_strip_control_slot`** (rename to
     `_strip_control_layer`) to recognise the control re-rooted at the
     **overlay's control layer** (now element index 2, the top layer) instead of
     split-pane element 1. Confirm the index/`RangeReference.start` against the
     `WidgetOverlay` child ordering once the renderer exists.
   - Replace the hardcoded `Ctrl+F` in `_toggle_operation` with a **per-inner
     gesture** — see Part C.

`orientation` becomes irrelevant for the overlay; keep the field for
back-compat or drop it (the ctor default `:vertical` can be ignored). Consider a
ctor kwarg `placement=:top_left` for the control anchor.

### Part C — Per-projection gestures + discoverability

Introduce a tiny trait interface that a configurable inner projection
implements, so the configuring wrapper asks the inner projection *what* its
gesture and label are instead of hardcoding them:

```julia
# defaults live with ProjectionConfiguringProjection; inner projections specialise.
configuration_label(inner)  ::String           # e.g. "Highlighting", "Filtering"
is_configuration_gesture(inner, gesture)::Bool  # e.g. KeyDown :h + Ctrl
configuration_descriptor(inner)::GestureDescriptor  # trigger+domain+description for F1
```

- `TextHighlighting` → e.g. **`Ctrl+H`**, label `"Highlighting"`.
- `TextFiltering`    → e.g. **`Ctrl+R`** (or `Ctrl+L`), label `"Filtering"`.
- Pick triggers that don't collide with existing global bindings (audit the
  `@event_case` blocks / `is_*_gesture` predicates before fixing the letters).

`_toggle_operation` then becomes: if `is_configuration_gesture(p.inner,
gesture)` → toggle show/hide of the control widget; if `Escape` and shown →
hide. Because each pipeline wraps one inner projection, the gesture
unambiguously configures *that* projection; if two configuring layers are ever
nested, each responds only to its own gesture and overlays its own control.

**Discoverability (F1 help):** express the toggle as an **annotated
`@event_case`** so it yields a `GestureDescriptor` automatically (single source
of truth — see the note on `@event_case`/gesture-help above). Since
the trigger varies by inner projection, drive the descriptor from
`configuration_descriptor(p.inner)` (domain `"Configuring"`, description like
`"Configure highlighting"`). The descriptor then bubbles up and `merge_help`s
into the F1 list like every other gesture, so the user discovers *"Ctrl+H —
Configure highlighting"* / *"Ctrl+R — Configure filtering"* contextually.

## Implementation steps

1. **⏳ OPEN: `WidgetOverlay` document** — add struct + ctor in `Widget.jl`, export from
   `WidgetModule`. (Sonnet-delegable: mechanical, mirror `WidgetSplitPane`.)
   _Verified OPEN (2026-08-12): no `WidgetOverlay` exists in `package/widget/main/Widget.jl` (only `WidgetSplitPane`) nor any export._
2. **⏳ OPEN: `WidgetOverlayToGraphicsCanvas`** — renderer + hit-test in
   `WidgetToGraphics.jl`, register in the dispatch table. Layout = base full-size
   + anchored content-sized layers; route top-first. (Opus: layout/hit-test
   logic; verify against the split-pane reference.)
   _Verified OPEN (2026-08-12): no `WidgetOverlayToGraphicsCanvas` in `package/widget/main/WidgetToGraphics.jl`; the dispatch table maps only `WidgetSplitPane`._
3. **⏳ OPEN: Printer swap** in `ProjectionConfiguring.jl`: `WidgetSplitPane` →
   `WidgetOverlay`, control as the top (visible-gated) layer.
   _Verified OPEN (2026-08-12): printer still emits `WidgetSplitPane(p.orientation, Any[control_widget, doc_widget])` at `package/widget/main/ProjectionConfiguring.jl:85`._
4. **⏳ OPEN: Reader swap**: `_strip_control_slot` → `_strip_control_layer` (new overlay
   slot index); replace `_toggle_operation`'s `Ctrl+F` with
   `is_configuration_gesture(p.inner, …)`.
   _Verified OPEN (2026-08-12): `_strip_control_slot` still present (`package/widget/main/ProjectionConfiguring.jl:140`); `_toggle_operation` still hardcodes `gesture.key === :f && has_ctrl_modifier_key(gesture)` (line 155)._
5. **⏳ OPEN: Per-projection trait**: define `configuration_label` /
   `is_configuration_gesture` / `configuration_descriptor` with defaults; add
   `TextHighlighting` and `TextFiltering` methods. Audit existing bindings for
   collisions before fixing letters.
   _Verified OPEN (2026-08-12): none of the three trait functions exist anywhere under `package/`._
6. **⏳ OPEN: F1 help**: annotate the toggle so `configuration_descriptor(p.inner)` flows
   into the context-help list.
   _Verified OPEN (2026-08-12): depends on step 5 trait, which does not exist; toggle is not an annotated `@event_case`. The gesture-help mechanism itself has changed since this plan was written — see the note under "Current state" above._
7. **⏳ OPEN: Wrapper/Examples**: `make_text_configuring_projection` no longer needs the
   split-pane-specific combo for *layout*, but the renderer must still dispatch
   `WidgetOverlay` (it will, via the dispatch-table registration) and the control
   widgets inside it. Confirm the example tabs still render; update comments at
   [Wrapper.jl](../../example/workbench/projection/Wrapper.jl) and
   [Gallery.jl:245-255](../../example/projectured/Gallery.jl#L245).
   _Verified OPEN (2026-08-12): no `WidgetOverlay` referenced in `package/workbench/example/projection/Wrapper.jl` or `package/projectured/example/Gallery.jl`._
8. **⏳ OPEN: Tests** — update
   [package/substrate/test/projection/ProjectionConfiguringTest.jl](../../test/substrate/projection/ProjectionConfiguringTest.jl):
   - "stacks control above document" → asserts a `WidgetOverlay` with
     `elements[1] === doc (base)` and `elements[2] === control_widget (top)`.
   - toggle test: drive the **per-projection** gesture (Ctrl+H for highlighting)
     and assert `ShowWidgetOperation`/`HideWidgetOperation`; Escape hides.
   - end-to-end click/typing tests: re-root the control edits through the
     overlay's control layer instead of the split-pane slot.
   - add a `test_widget()`-level case for `WidgetOverlay` rendering + hit-test
     (top layer wins the click).
   Run the **narrowest** scope: `test_projection_configuring()` plus the new
   widget overlay test; only sweep wider if those pass. (Per repo testing rules
   — do not default to `test_all()`.)

## Files touched

- `package/widget/main/Widget.jl` — `WidgetOverlay` document.
- `package/widget/main/ProjectionConfiguring.jl` and
  `package/widget/main/WidgetToGraphics.jl` — `WidgetOverlayToGraphicsCanvas` +
  dispatch registration; printer overlay swap, reader slot/gesture changes,
  configuration trait + defaults. There is no umbrella `Projectured.jl` to
  export from any more — each package exports its own symbols.
- `package/text/main/TextHighlighting.jl`, `package/text/main/TextFiltering.jl`
  — per-projection `configuration_*` methods.
- `package/workbench/example/projection/Wrapper.jl`,
  `package/projectured/example/Gallery.jl` — comments / wiring confirmation.
- `package/substrate/test/projection/ProjectionConfiguringTest.jl` (+ a widget overlay test).

## Risks / things to verify during implementation

- **Reference re-rooting through the overlay.** The exact `ConcreteReferencePath`
  shape of a control edit once it comes back through `WidgetOverlay` (which child
  index, what `RangeReference.start`) must be confirmed against the new renderer
  before rewriting `_strip_control_layer`; this is the main correctness risk
  (the split-pane version relied on `elements`/`RangeReference.start == 0`).
- **Hit-test z-order.** Clicks must reach the floating control first; ensure the
  base document does not also consume the same click. The visible-gated empty
  canvas for a hidden control must let clicks fall through to the document.
- **Gesture collisions.** Confirm chosen per-projection triggers don't shadow
  existing global gestures (search `@event_case` / `is_*_gesture`).
- **Anchored layout sizing.** Overlay layers are content-sized and absolutely
  placed; verify measurement works with the `measure`/`available_size` context
  the configuring examples pass.

## Open questions resolved

- Overlay mechanism → **new z-layered `WidgetOverlay`** (not a floating window).
- Gesture → **per inner projection** (highlighting ≠ filtering), declared by the
  inner projection and surfaced in F1 help.

## Still to confirm with the user (non-blocking)

- Exact gesture letters per projection (proposed `Ctrl+H` highlighting,
  `Ctrl+R` filtering) — pending the collision audit.
- Default anchor/placement of the overlay control (proposed top-left corner).
