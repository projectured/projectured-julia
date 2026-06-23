# Hover Click-Reference Inspector

> **Status: IMPLEMENTED.** Run with `run_example("json"; inspector=true)`.
>
> What shipped (all green: 20 targeted asserts + no regression in `test_tooltip`
> / `test_click_roundtrips`):
> - **New document** `ReferenceInspector` — [package/domain/src/document/ReferenceInspector.jl](../../package/domain/src/document/ReferenceInspector.jl).
> - **New projection** `ReferenceInspectorToText` (ReferenceInspector → two-section TextText) — [package/domain/src/projection/primitive/ReferenceInspectorToText.jl](../../package/domain/src/projection/primitive/ReferenceInspectorToText.jl).
> - **New projection** `HoverProbeProjection` (the hover→would-be-click probe) — [package/domain/src/projection/higherorder/HoverProbe.jl](../../package/domain/src/projection/higherorder/HoverProbe.jl).
> - **Backend** generic `pointer_position(::Backend)` ([Backend.jl](../../package/kernel/src/api/Backend.jl)) + SDL method and throttled idle-`MouseMove` forwarding ([ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl)).
> - **Wiring** `_multi_window_projection_inspector` + `run_example(...; inspector=true)` ([Examples.jl](../../package/example/src/Examples.jl)).
> - **Tests** [package/test/src/projection/HoverProbeTest.jl](../../package/test/src/projection/HoverProbeTest.jl).
>
> Decisions confirmed during implementation:
> - Kept the `ReferenceInspector` document (the recommended option) over the inline-thunk fallback.
> - **Skipped** the `HoverProbe` state-wrapper document — transient state lives on the projection instance (`open`/`last` Refs), matching `TooltipDecoratorProjection`; the probe communicates purely via window operations.
> - Following the cursor uses **`pointer_position` (global mouse) + a fixed offset** and re-issues `OpenWindowOperation` (same id updates in place) — no `MoveWindowOperation`, no `screen_origin` needed. Idle motion is throttled to ~33 Hz in the SDL backend.
> - Follower window is fixed-size (`820×240`) `:tooltip` style; closes over dead space.
> - Live SDL window open/move/render was **not** re-verified by hand — it is the exact `OpenWindowOperation`→`WindowManager`→reconciler path the tooltip already exercises; the new pipeline test asserts the `:inspector` window is added with the right content/position.

A secondary window that **follows the mouse** as it moves over a document and,
for the current pointer position, shows **the reference a single left-click
would create** — rendered in two forms simultaneously:

1. **Compact** — the Julia-printed shape (`@reference entries[1].value.value{3}`),
   color-coded.
2. **Human readable** — the reverse-order English narrative
   (`the 3rd position of the JsonString` / `the value of the JsonObjectEntry` / …).

The user moves the mouse around and sees *what is what*: every glyph, delimiter,
and gap reveals the path it stands for, without having to click and disturb the
selection.

---

## TL;DR — what is genuinely new

This feature is **one short step away from the existing path-tooltip**. Almost
everything is already built; the deltas are small and localised.

| Piece | Status |
|---|---|
| Reverse-project a pixel position → would-be click reference | **Exists** — `projection_read(projection, iomap, MousePress(:left, x, y, …))` returns a `ReplaceSelectionOperation` whose `.path` is exactly that ref. Proven by [ClickRoundtripTest.jl](../../package/test/src/editor/ClickRoundtripTest.jl). |
| Render a reference compact + human-readable, stacked | **Exists** — `ReferenceToText` + `ReferenceToHumanReadableText`, already stacked in [`_make_tooltip_source`](../../package/example/src/Examples.jl). |
| Secondary native window, open/move/close as state | **Exists** — `ScreenDocument`/`WindowDocument`, `WindowManagerProjection`, `OpenWindowOperation`/`CloseWindowOperation`. |
| **Drive the panel from hover (would-be click) instead of selection** | **NEW** — the one essential new projection. |
| **Forward idle mouse motion to the reader** | **NEW** — small backend change. |
| **Position the window at the pointer (follow)** | **Partly new** — needs `screen_origin` (already flagged in [pending/tooltip.md](tooltip.md) Step 6). |

So the answer to *"what new projections and documents do we need?"*:

- **Projections: one essential new one** — `HoverProbeProjection` (the hover →
  would-be-click-reference probe). Optionally a second tiny display projection
  if we promote the two-format panel to a first-class component.
- **Documents: zero are strictly required.** We reuse `WindowDocument` for the
  follower window and the existing reactive-`TextText` content pattern.
  **Recommended:** introduce **one** display document, `ReferenceInspector`, so
  the two-format panel becomes a reusable, testable component instead of an
  example-local thunk.

Everything else is reuse.

---

## Why a click maps to a reference for free

The reader chain already turns a click into a domain reference. When a
`MousePress(:left, x, y, …)` enters the pipeline, each `projection_read` step
translates it one domain inward until a `ReplaceSelectionOperation` with a
content-domain `.path` falls out — pixel → graphics → text → syntax → JSON.
`read!` then *applies* that path as the selection.

The inspector wants the **same path, not applied**. So the core mechanism is:

```julia
op = projection_read(content_projection, content_iomap,
                     MousePress(:left, hover_x, hover_y, Modifiers()))
would_be_ref = op isa ReplaceSelectionOperation ? op.path : nothing
```

`would_be_ref` is the content-domain reference to display. We never call
`set_selection!`, so the document's real selection is untouched.

(`op` may instead be a `ToggleCollapseOperation` on a fold marker, or `nothing`
on dead space — both render as "no target" or a descriptive label. The probe
must tolerate any reader result, exactly as `ClickRoundtripTest` already does.)

---

## Architecture: where the pieces sit

```
ScreenDocument                                  (reused)
├─ WindowDocument :main                          (reused)
│    content  = HoverProbe(content = <example doc>)   ← NEW wrapper (optional; see below)
│    projected by HoverProbeProjection ∘ <example projection>
└─ WindowDocument :inspector  (style = :tooltip)  (reused; follows the mouse)
     content  = ReferenceInspector(reference = …, target = <example doc>)  ← NEW display doc
     projected by ReferenceInspectorProjection → stacked TextText
```

- The **main window**'s content projection is wrapped by `HoverProbeProjection`.
  Its reader watches idle `MouseMove`s, computes `would_be_ref`, and drives the
  inspector window via window operations (open / move / close).
- The **inspector window** is an ordinary `WindowDocument` whose geometry tracks
  the pointer and whose content renders `would_be_ref` in both formats. It is a
  `:tooltip`-style window so it is borderless / always-on-top and (once the
  pending non-focusable backend work lands) does not steal focus.

---

## New documents

### `ReferenceInspector` (recommended — the display document)

```julia
@document struct ReferenceInspector <: Document
    reference::Reference         # the would-be-click reference to display (nothing = no target)
    target::Any                  # the document the reference points into; needed by
                                 # ReferenceToHumanReadableText to name parent types
    selection::Reference
end
```

Projected by `ReferenceInspectorProjection` (below) into a two-section
`TextText`. This is the only new *document* the feature really benefits from,
and it is optional: the alternative is to build the follower window's content as
a reactive `TextText` thunk inline, exactly like
[`_make_tooltip_source`](../../package/example/src/Examples.jl) does today
(re-reading the ref each frame and concatenating the two renderings). Promoting
it to a real document buys reuse + a unit test surface; the thunk buys zero new
types. **Recommendation: add `ReferenceInspector`** — it is tiny and makes the
panel a first-class component (status bars, debugger panes, the existing
selection-tooltip could all switch to it).

### `HoverProbe` (optional — the state wrapper)

```julia
@document struct HoverProbe <: Document
    content::Document            # the real document being inspected
    hovered::Reference           # would-be-click ref at the current pointer (nothing off-target)
    pointer::Any                 # last (x, y) the probe saw, content-relative
    selection::Reference
end
```

Only needed if we want the hover state to live **in the document tree** (so it
participates in references/undo/inspection) rather than as transient state on
the projection instance. The existing `TooltipDecoratorProjection` keeps its
transient trigger state on the projection instance (`state::Dict`) and emits
operations instead; we can do the same and **skip `HoverProbe` entirely**.

**Recommendation: skip `HoverProbe` for v1.** Keep the probe's transient state
on the `HoverProbeProjection` instance and communicate via window operations,
mirroring `TooltipDecoratorProjection`. Add `HoverProbe` later only if a
consumer needs to read the hovered ref from elsewhere in the tree.

---

## New projections

### `HoverProbeProjection` (essential — the heart of the feature)

A higher-order projection that wraps the main window's content projection.
Same passthrough-print / active-read shape as `TooltipDecoratorProjection`
([higherorder/TooltipDecorator.jl](../../package/domain/src/projection/higherorder/TooltipDecorator.jl)).

```julia
mutable struct HoverProbeProjection <: Projection
    inner::Projection            # the wrapped content projection (proj. produces a GraphicsCanvas)
    id::Symbol                   # inspector window id, e.g. :inspector
    offset::Tuple{Int,Int}       # pointer→window offset, e.g. (16, 16)
    # transient:
    last_ref::Cell               # last emitted would-be ref (to debounce no-op moves)
    is_open::Cell                # whether the inspector window is currently open
end
```

**Print side.** Pure passthrough: project `content` through `inner` via the
outer recursion, capture the resulting content iomap on the projection's iomap
so the reader can reuse it for the synthetic-click probe. Output is exactly the
wrapped content — wrapping a document in the probe changes nothing visually.

**Read side.** On a `MouseMove(x, y, …)` envelope routed into this content:

1. Build `MousePress(:left, x, y, Modifiers())`.
2. `op = projection_read(inner, captured_inner_iomap, the synthetic press)`.
3. `ref = op isa ReplaceSelectionOperation ? op.path : nothing`
   (a `ToggleCollapseOperation` or `nothing` → treat as a labelled/empty target).
4. Emit the window op that updates the inspector:
   - `ref !== nothing` → `OpenWindowOperation(id=:inspector, x=screen_x, y=screen_y,
     content=ReferenceInspector(reference=ref, target=content_doc), style=:tooltip)`.
     Re-issuing `OpenWindowOperation` with the same id **updates geometry +
     content in place** (already the `WindowManagerProjection` contract — see
     [done/tooltip.md](../done/tooltip.md) "Duplicate open / close"). This is how
     the window *follows* the mouse and refreshes its text every move.
   - `ref === nothing` (dead space / off content) → `CloseWindowOperation(:inspector)`.
   - Debounce: if `ref` equals `last_ref` and the window is already open at the
     new position, emit only a position update (or nothing) to avoid
     re-projecting identical content every motion event.
5. All **other** events (real clicks, keys, scroll, drag-moves) pass straight
   through to `inner` unchanged — hover probing must never interfere with real
   editing. A real `MousePress` still selects normally.

`screen_x/screen_y` = `screen_origin(backend, :main) + (x, y) + offset`, clamped
to display bounds (see Positioning below).

Reference mapping (`map_reference_forward`/`backward`) passes through the
`content` field, identical to how `TooltipDecoratorProjection` threads through
its `child`.

**Why a projection and not editor special-casing:** it keeps the rule the
tooltip plan established — *events become operations, operations mutate input,
the printer is a pure function of input*. The probe is the same idea as the
selection-tooltip, with the trigger swapped from "selection exists" to "pointer
is over a clickable glyph", and the displayed ref swapped from the selection to
the would-be click.

### `ReferenceInspectorProjection` (recommended — the display projection)

Projects a `ReferenceInspector` into a stacked `TextText` (or a small
`WidgetStack`), reusing the two existing reference projections:

```julia
short = projection_print(ReferenceToText(), nothing, inspector.reference, ctx).output
long  = projection_print(ReferenceToHumanReadableText(inspector.target), nothing,
                         inspector.reference, ctx).output
# stack: [short spans] · blank line · [long spans], optionally with section labels
```

This is literally the body of [`_make_tooltip_source`](../../package/example/src/Examples.jl)
lifted into a real projection. `reference === nothing` → a single gray
"no target" line. No reader (display-only) in v1; a later revision can map a
click on a rendered step back to a `ReplaceSelectionOperation` so the inspector
becomes a navigation aid.

If we decide to **skip** the `ReferenceInspector` document, this projection is
also skipped and the follower window content is the inline `TextText` thunk
instead.

---

## Reused, unchanged

- **`ScreenDocument` / `WindowDocument`** and the backend reconciler
  ([kernel/document/Screen.jl](../../package/kernel/src/document/Screen.jl),
  reconciler in [ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl)).
- **`WindowManagerProjection`** + `OpenWindowOperation` / `CloseWindowOperation`
  ([kernel/projection/higherorder/WindowManager.jl](../../package/kernel/src/projection/higherorder/WindowManager.jl)).
  `OpenWindowOperation` with an existing id already updates geometry/content in
  place, which is exactly "follow + refresh".
- **`ReferenceToText` / `ReferenceToHumanReadableText`**
  ([domain/projection/primitive/ReferenceToText.jl](../../package/domain/src/projection/primitive/ReferenceToText.jl)).
- **The click reverse-projection** through the whole content pipeline.
- **`EventEnvelope` window-routing** — delivers the bare per-window event into
  the content sub-iomap where `HoverProbeProjection` sits.

---

## Backend / plumbing changes

### 1. Forward idle mouse motion (required)

Today `read_from_devices` drops `SDL_MOUSEMOTION` unless a button is held:

```julia
# package/sdl/src/ProjecturedSdl.jl  (~line 1963)
buttons == :none && continue        # ← idle hover is currently dropped
```

The feature needs idle motion. Change this to forward motion regardless of
button state. Because idle motion is high-frequency, add **throttling** so we
don't probe + re-project every pixel:

- Coalesce: keep only the latest `MouseMove` per `read_from_devices` drain
  (drop superseded motions in the same poll), and/or
- Rate-limit in the `GestureRecognizer`
  ([kernel/editor/GestureRecognizer.jl](../../package/kernel/src/editor/GestureRecognizer.jl)):
  emit at most one hover `MouseMove` per ~16–30 ms.

Coalescing the SDL queue (return only the last pending motion) is the simplest
correct option and keeps the change local to the backend.

### 2. `screen_origin(backend, id)` (required for accurate follow)

The probe sees content-relative coordinates; the window manager needs
screen-absolute placement. This helper is already specified as missing work in
[pending/tooltip.md](tooltip.md) Step 6. Implement it (SDL `SDL_GetWindowPosition`
on the `:main` window handle) and combine: `screen_xy = origin + (x, y) + offset`,
clamped via `sdl_display_size`. **v1 fallback** if `screen_origin` slips: place
the inspector at the main window's configured `(x, y)` plus content offset —
follow is approximate but functional.

### 3. `:tooltip` non-focusable (soft dependency)

So the inspector never steals focus / hover from the main window. Already an
open item in [pending/tooltip.md](tooltip.md) Step 1. Until then, the
`(offset)` keeps the cursor off the inspector so it does not interfere.

### `MoveWindowOperation`? — not needed for v1

Re-issuing `OpenWindowOperation` with the same id already moves + refreshes the
window in place. Introduce a dedicated `MoveWindowOperation` only if
re-projecting content on a pure positional move proves too costly (the debounce
in `HoverProbeProjection` step 4 should make that rare).

---

## Pipeline shape

A hover-inspector variant of `_multi_window_projection_tooltipped`
([Examples.jl](../../package/example/src/Examples.jl)). The only structural
change from the tooltip pipeline is wrapping the example content projection in
`HoverProbeProjection` and adding a `ReferenceInspector` dispatcher entry:

```julia
RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument     => WindowManagerProjection(inner = ScreenToScreen()),
        WindowDocument     => ScreenToScreen(),
        CellVector         => CopyingProjection(),
        ReferenceInspector => ReferenceInspectorProjection(),      # NEW
        TextText           => SequentialProjection(WordWrapping(...), TextToGraphics(...)),
        Any                => HoverProbeProjection(                 # NEW wrapper
                                  inner = <existing per-example reference dispatch>,
                                  id    = :inspector),
    ),
)
```

(`HoverProbeProjection` wraps the `ref_dispatch` that already exists; it does not
replace it.)

---

## Implementation steps

1. **Idle-motion forwarding + throttle** — backend change #1. Verify a hovering
   mouse now produces `MouseMove` envelopes via a REPL/`play_live!` smoke test.
2. **`ReferenceInspector` document + `ReferenceInspectorProjection`** — lift the
   two-format stack out of `_make_tooltip_source` into a real doc + projection;
   unit-test it the way [reference-to-text.md](../done/reference-to-text.md)
   tests the underlying projections (line counts, first/last line, colors).
3. **`HoverProbeProjection`** — the core. Print passthrough capturing the inner
   iomap; reader does synthetic-`MousePress` probe → `OpenWindowOperation` /
   `CloseWindowOperation`. Model it on `TooltipDecoratorProjection`. Test in a
   `TooltipTest`-style file: feed `MouseMove`s at known coordinates, assert the
   emitted `OpenWindowOperation.content.reference` equals the path
   `ClickRoundtripTest` gets for a `MousePress` at the same point — i.e. the
   probe and a real click agree.
4. **`screen_origin` + positioning** — backend change #2; wire `screen_x/y`.
5. **Example wiring** — a `hover_inspector` example (or a `run_example(...;
   inspector=true)` flag) that builds the pipeline above over the JSON example,
   plus a `LiveExample` timeline that sweeps the pointer across the document so
   the follow + dual-format display can be watched/recorded.
6. **Docs** — short section in [documentation/document/workbench.md](../../documentation/document/workbench.md)
   or a new note, and cross-link from [pending/tooltip.md](tooltip.md) Step 9
   (this plan *is* the pointer-based-hover work that step deferred).

---

## Decisions taken (sensible defaults; revisit if wrong)

- **Continuous follow**, not anchored-to-element — the prompt says "follows the
  mouse as you move around". The window re-positions every (throttled) motion.
- **A native secondary window** (`WindowDocument`), not an in-canvas overlay —
  the prompt says "secondary window".
- **Close on dead space.** When the pointer is over nothing clickable
  (`would_be_ref === nothing`), close the inspector rather than show an empty
  panel. (Alternative: keep it open showing "no target" — trivial to switch.)
- **No `HoverProbe` state document in v1** — transient state on the projection
  instance + window operations, matching `TooltipDecoratorProjection`.
- **`ReferenceInspector` display document is in v1** — small, reusable, testable;
  the inline-thunk alternative is the fallback if we want zero new documents.

## Open questions

- **Throttle location** — backend queue-coalescing vs. `GestureRecognizer`
  rate-limit. Start with backend coalescing; add a recognizer rate-limit only if
  re-projection cost shows up in `[perf]` counters.
- **Probe cost** — each hover runs the full content reader once. For large
  documents, confirm one reverse-projection per throttled move is cheap (it is a
  single reader pass, same cost as one real click). Debounce on unchanged
  `would_be_ref` to skip re-projecting identical content.
- **Click-through on the inspector** — once `ReferenceInspectorProjection` gains
  a reader, clicking a rendered step could select that node. Deferred; display
  only in v1.
- **Range / multi-char references** — a hover that would produce a
  `RangeReference` (e.g. over a whole element) renders fine via `ReferenceToText`;
  no special handling needed.
</content>
</invoke>
