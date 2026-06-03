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

A tooltip is just another `WindowDocument` (with `style = :tooltip`) inside the
`ScreenDocument.windows` list. The backend reconciler already opens, moves,
resizes, and closes the native window once a `WindowDocument` is present;
this plan's job is to decide **when to add and remove** that window — and to do
it *through the existing operation pipeline*, not by mutating the projection
output.

Two new pieces:

1. **`TooltipSource`** — a document that wraps a child node and carries
   tooltip metadata (content, style, id). Lives in the input tree at every
   point where a tooltip *could* appear.
2. **`TooltipDecoratorProjection`** — projects a `TooltipSource` by
   transparently projecting its child, while its reader watches for the
   trigger condition. When the tooltip should appear, the reader emits an
   `OpenWindowOperation`; when it should disappear, a `CloseWindowOperation`.

These operations climb up the reader chain (the standard "operations bubble
up with reference-prefixing" mechanism) until they reach a
**`WindowManagerProjection`** wrapping the `ScreenDocument` case of the type
dispatcher. The manager intercepts them and applies them as mutations on the
`ScreenDocument.windows` `CellVector` of its input — pushing a new
`WindowDocument` for open, removing the matching one for close.

The next frame, the printer runs over the now-modified input, the new
`WindowDocument` flows through the existing pipeline, and the backend
reconciler opens the native tooltip window. Closing is the symmetric path.

Net effect: the tooltip is a normal `WindowDocument` produced by mutating
input state, just like every other window. No printer-side appendage, no
backend changes, no new event routing.

---

## Motivation

Before multiple windows, supporting tooltips meant inventing a multi-canvas
output type *and* teaching the backend to manage extra windows. With multiple
windows in place, the same need reduces to "ensure a `WindowDocument` exists
in `screen.windows` exactly when a tooltip should be visible".

A natural temptation is to do this by *appending a window in the printer* —
have a decorator projection inject an extra `WindowDocument` into the output
`ScreenDocument` when triggered. That works, but it splits state across two
places (the input tree describes most of the windows, the printer fabricates
the rest), and it makes printer output depend on out-of-band timer state.

This plan goes the other way: keep all window state in the input document
tree, and let the tooltip projection *request* a window via an operation.
That matches how every other state change in the system already works —
events become operations, operations mutate the input, the printer is a
pure function of the input.

Goals:

- Give projections a clean way to ask for a tooltip window without owning
  the window list.
- Keep tooltip content, trigger, and position decisions inside the
  projection layer, not in the editor or the backend.
- Stay consistent with the rule from multiple-windows.md that "every 'open
  a window' feature is 'add a `WindowDocument` to the input'".

---

## Design

### Pipeline shape

```julia
projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument  => WindowManagerProjection(
            inner = CopyingProjection(),
        ),
        WindowDocument  => CopyingProjection(),
        TooltipSource => TooltipDecoratorProjection(
            inner    = CopyingProjection(),
            trigger  = (tooltip, selection, event) -> ...,
            content  = (tooltip, selection) -> ...,
            position = (tooltip, selection) -> (x, y, w, h),
            style    = :tooltip,
            id       = (tooltip) -> :tooltip,
            delay_ms = 300,
        ),
        Any             => domain_projection,
    )
)
```

Two new projection types: `TooltipDecoratorProjection` (input
`TooltipSource`) and `WindowManagerProjection` (input `ScreenDocument`).
Their print sides are transparent passthroughs to `inner`; the interesting
behaviour is on the reader side, where operations flow.

### `TooltipSource`

A new document type that wraps a child node and carries tooltip metadata:

```julia
@document struct TooltipSource <: Document
    child::Document         # the actual node being decorated
    content::Document       # tooltip body (rendered like any other document)
    style::Symbol           # forwarded to the eventual WindowDocument
    id::Symbol              # backend window id (must be unique per screen)
    selection::Reference
end
```

Use sites wrap whichever sub-tree they want tooltipped:

```julia
JsonObject(...,
    # wrap a property's value in a TooltipSource so hovering it pops a
    # window showing its JSON path.
    value = TooltipSource(
        child   = original_value,
        content = TextDocument("foo.bar.baz"),
        style   = :tooltip,
        id      = :path_tooltip,
    ),
)
```

`TooltipSource` is a *transparent wrapper* from the projection's point
of view: its print output is whatever `child` projects to, so visually
nothing changes when you wrap a node in one. Its purpose is to mark a
sub-tree as a potential tooltip source and carry the metadata the decorator
needs.

### `TooltipDecoratorProjection`

**Print side.** Delegates to `inner` (typically `CopyingProjection`) which
recurses into `child` via the outer recursion. Output is the projected
child — no window is added here. Tooltip metadata fields are not part of
the visual output; they exist only for the reader.

**Read side.** This is where the work happens. The reader observes the
events being routed into this `TooltipSource`'s sub-tree (selection
changes, mouse motion, frame ticks) and decides whether the tooltip should
currently be open.

State held on the projection instance (per-tooltip):

```julia
mutable struct TooltipDecoratorProjection <: Projection
    inner::Projection
    trigger::Function
    content::Function
    position::Function
    style::Symbol
    id_of::Function           # tooltip -> Symbol
    delay_ms::Int
    # transient state:
    arm_time::Cell{Union{Nothing, Float64}}  # when trigger most recently turned on
    is_open::Cell{Bool}                      # whether OpenWindowOperation has been emitted
end
```

On each event arriving at the reader:

1. Forward the event to `inner` first so child operations bubble up normally.
2. Evaluate `trigger(tooltip, selection, event)`.
3. State machine:
   - `trigger == true`, `arm_time == nothing` → set `arm_time = time()`;
     emit nothing (yet).
   - `trigger == true`, `arm_time` set, `time() - arm_time >= delay_ms/1000`,
     `is_open == false` → emit `OpenWindowOperation`, set `is_open = true`.
   - `trigger == false`, `is_open == true` → emit `CloseWindowOperation`,
     clear `arm_time`, set `is_open = false`.
   - `trigger == false`, `is_open == false` → clear `arm_time`; emit nothing.
4. If the child reader produced an operation, return that. If the decorator
   itself produced an open/close, return that. (Composing both into a
   single returned value is one of the open questions below — see
   "Multiple ops per event".)

The delay timer is driven by whatever events the projection sees. In
practice the editor's frame loop produces enough events (or a periodic
"tick") that the open transition fires on the first event after the delay
elapses. See **Show delay** below.

### `OpenWindowOperation` and `CloseWindowOperation`

```julia
struct OpenWindowOperation <: Operation
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
    bg::NTuple{4,UInt8}
    style::Symbol
    content::Document
end

struct CloseWindowOperation <: Operation
    id::Symbol
end
```

These are ordinary `Operation` subtypes. They climb up through the reader
chain exactly like `ReplaceSelectionOperation` and the string-mutation ops
already do. Each parent reader gets a chance to handle them; intermediate
readers that don't know about them pass them through (with reference-path
prefixing if the operation carried one — these don't, since they don't
target a specific reference in the input tree).

They eventually reach the top of the type-dispatcher pipeline. The
`WindowManagerProjection` wrapping the `ScreenDocument` case intercepts
them there.

### `WindowManagerProjection`

**Print side.** Pure passthrough to `inner` (typically the
`CopyingProjection` that copies `ScreenDocument` through). No mutation of
output.

**Read side.** First, route the event to `inner` so child operations bubble
up the normal way. Inspect the resulting operation:

- `OpenWindowOperation` → construct a `WindowDocument` from its fields and
  push it onto the input `ScreenDocument.windows` `CellVector`. Then
  produce no further upward operation (the request has been served).
- `CloseWindowOperation` → find the `WindowDocument` with matching `id` in
  `windows` and remove it. Produce nothing upward.
- Any other operation → pass through unchanged.

If a tooltip with that `id` already exists when `OpenWindowOperation`
arrives, the duplicate open is logged and ignored (or replaces the
existing one — pick a convention; see open questions). Likewise a
`CloseWindowOperation` for a missing `id` is a no-op with a debug log.

The mutation is applied *immediately during reading*, which is the same
mechanism the editor already uses to settle `ReplaceSelectionOperation`
and friends. On the next frame the printer sees the updated input and
the new `WindowDocument` flows through to the backend reconciler.

> **Note (during implementation):** `CopyingProjection` builds its
> output `CellVector` of windows eagerly at print time, so a later push
> to the input's `windows` cell does *not* propagate to the output on
> its own. The manager therefore mutates *both* sides explicitly:
> it stores the outer `recursion` and `ctx` it was called with, projects
> the new `WindowDocument` through them, and pushes the result onto the
> output `windows` alongside the input push. The same pattern handles
> duplicate-id updates (replace geometry in place on both sides).

### How events reach the tooltip projection

`TooltipSource` sits somewhere inside a `WindowDocument.content`'s
sub-tree. Events arrive at the editor's top-level read in an
`EventEnvelope`; the `CopyingProjection` on `ScreenDocument` routes by
`window_id` into the matching `WindowDocument.content` iomap; that iomap
descends through the child structure until it reaches the
`TooltipDecoratorProjection`'s iomap, which receives the bare event.

Selection-based triggers work without extra machinery: a selection event
that lands on the decorated child passes through the tooltip projection's
reader, where the `trigger` function can inspect the selection vs. the
tooltip's input reference and decide.

### Hover vs selection as the trigger

v1 uses selection-based triggers because the selection cursor is already a
first-class concept, and pointer routing is the harder piece of work. The
`trigger` callback signature is `(source, event) -> Bool` — projections
can inspect anything they like on the source (in practice, the current
implementation reads `source.child.selection` to decide).

### Show delay

The same wall-clock-in-the-reader mechanism the original plan described,
just relocated from the printer to the reader (where it more naturally
belongs now that the decision drives an operation, not output).

- `arm_time` is held per `source.id` on the projection instance.
- On every event reaching the reader, re-evaluate `trigger`; update
  `arm_time` and `is_open` per the state machine above.
- The editor's frame loop produces frequent enough events that
  `time() >= arm_time + delay` is observed promptly. If the gap is too
  large in practice, introduce a periodic frame-tick event (delivered to
  all readers) or a proper `TimerCell` that self-invalidates after a
  duration.

Reading `time()` in the reader breaks reactive purity in the same way the
original plan did in the printer. Same trade-off; document it.

### Style

`WindowDocument.style = :tooltip` is already part of multiple-windows'
schema. The backend's window-flag mapping handles borderless / always-on-top.
The tooltip projection just forwards `style` to `OpenWindowOperation`.

### Multiple simultaneous tooltips / preview panels

Multiple `TooltipSource` wrappers in the tree, each with its own `id`
(e.g. `:type_tooltip`, `:error_tooltip`, `:preview`). The
`TooltipDecoratorProjection` keeps per-`id` state, so a single decorator
instance independently emits `OpenWindowOperation` / `CloseWindowOperation`
for each source. The `WindowManagerProjection` maintains the windows list
as the union of all open requests.

### Per-tooltip content projections

`TooltipSource.content` is a `Document`. The
`OpenWindowOperation.content` field carries a `Document`, which becomes
the new `WindowDocument.content`. The outer
`RecursiveProjection(TypeDispatchingProjection(...))` projects it through
the existing dispatcher entries on the next frame — no per-window
projection machinery needed.

If the tooltip needs a different projection than the domain projection,
add another entry to the dispatcher keyed on the tooltip content's
concrete type, exactly as in multiple-windows.

---

## Implementation Steps Completed

### Step 2 — `TooltipSource` and the operations

- `@document struct TooltipSource` with `child`, `content`, `style`,
  `id`, `selection` fields. Lives in
  [program/src/document/Tooltip.jl](../../program/src/document/Tooltip.jl).
- `OpenWindowOperation` and `CloseWindowOperation` structs alongside
  `QuitEditorOperation` and `ReplaceSelectionOperation` in
  [program/src/common/Operation.jl](../../program/src/common/Operation.jl).

### Step 3 — `WindowManagerProjection`

- Struct with `inner::Projection`, holding the outer `recursion` and
  `ctx` so new windows can be projected on the output side.
- Printer: delegates to `inner`.
- Reader: routes to `inner`, then post-processes the returned operation —
  applies `OpenWindowOperation`/`CloseWindowOperation` to *both* input and
  output `ScreenDocument.windows` (mutation in place for duplicate ids,
  push/delete for the new/gone case) and swallows the operation.
- Lives in
  [program/src/projection/higherorder/WindowManager.jl](../../program/src/projection/higherorder/WindowManager.jl).
- Smoke-tested in
  [test/src/projection/TooltipTest.jl](../../test/src/projection/TooltipTest.jl)
  for both the open/close round-trip and the duplicate-id geometry update.

### Step 4 — `TooltipDecoratorProjection` skeleton

- Struct with `trigger`, `position`, `title`, `delay_ms`, and a per-`id`
  `state::Dict` holding `(arm_time, is_open)`.
- Printer: delegates to the recursion projecting `source.child`.
- Reader: implements the state machine described in **Design**; emits
  `OpenWindowOperation` / `CloseWindowOperation` based on `trigger`.
- Child operations take priority — if the child reader produced an op,
  the decorator's transition is held back and re-attempted on the next
  event.
- Reference mapping passes through the child for forward/backward; input
  references go through a `FieldReference("child")` step.
- Lives in
  [program/src/projection/higherorder/TooltipDecorator.jl](../../program/src/projection/higherorder/TooltipDecorator.jl).
- Smoke-tested in
  [TooltipTest.jl](../../test/src/projection/TooltipTest.jl): a JSON-like
  example with a `TooltipSource` wrapping a node and a trigger flag
  flipped from the test; confirms the tooltip window opens, stays open
  on subsequent events, closes on trigger off, and reopens after close.

### Step 5 — Show delay (logic)

- The `state::Dict` carries `arm_time`; `OpenWindowOperation` is gated on
  `(now - arm_time) * 1000 >= delay_ms`.
- `delay_ms = 0` is the default (open on first event where the trigger is
  true). The non-zero path is implemented but not yet exercised by an
  example.

### Step 1 — `:tooltip` style on the backend (partial)

- `_WINDOW_FLAGS_TOOLTIP` in
  [program/src/backend/Sdl.jl](../../program/src/backend/Sdl.jl) combines
  `SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_ALLOW_HIGHDPI`.
  `_window_flags(:tooltip)` returns it.
- The non-focusable / skip-taskbar flag is **not** set, and there is no
  `screen_origin(backend, id)` helper yet. See the pending plan.

### Step 7 — Example tooltips (path tooltip only)

- `run_example(...; tooltip=true)` in
  [example/src/Examples.jl](../../example/src/Examples.jl) wraps each
  example's content in a `TooltipSource` via `_make_tooltip_source`.
- The `content` is a reactive `TextText` whose thunk re-reads the wrapped
  document's selection each frame and rebuilds the colored spans via
  `ReferenceToText`. The trigger is `source.child.selection !== nothing`.
- `_multi_window_projection_tooltipped` wires up the
  `WindowManagerProjection` + `TooltipDecoratorProjection` + `TextText`
  entries in front of the existing per-example reference dispatch.

### Step 8 — Multiple simultaneous tooltips (supported by construction)

- The decorator's `state::Dict{Symbol, ...}` is keyed by `source.id`, so
  one decorator instance multiplexes any number of distinct sources.
- The manager keeps windows independent (open/close is per `id`).
- An explicit test of two sources in different sub-trees is not yet
  present.

---

## Resolved Open Questions

- **Where does the show-delay timestamp live?** On the projection instance,
  in a `state::Dict{Symbol, ...}` keyed by source id (so one decorator
  instance can serve many sibling sources).

- **Time in the reactive system.** `time()` is read in the reader. Same
  reactive-purity trade-off as the printer-side approach the original
  plan considered. Acceptable for v1.

- **Multiple ops per event.** Resolved by priority: if the child reader
  produced an op, that op is returned and the decorator transition is
  held back. State is committed only when the decorator op is actually
  emitted, so the next event re-attempts the transition.

- **Duplicate open / close.** Open of an already-open id updates geometry
  in place (replace semantics). Close of an absent id is a silent no-op.

## Relationship to the Multiple Windows Plan

| Concern | Multiple windows handles | This plan adds |
|---------|--------------------------|----------------|
| Multi-window output type | `ScreenDocument` / `WindowDocument` | — |
| Opening / closing native windows | `write_to_devices(::ScreenDocument)` reconciler | — |
| Per-window event routing | `EventEnvelope { window_id, event }` | Drops envelopes for tooltip window in v1 |
| Per-window style | `WindowDocument.style` + backend flag mapping | Defines `:tooltip` window flags (borderless, always-on-top) |
| Window list as state | `ScreenDocument.windows` `CellVector` | `WindowManagerProjection` mutates it in response to `Open`/`CloseWindowOperation` |
| Trigger to show a window | Out of scope — push/remove `WindowDocument` | `TooltipDecoratorProjection.trigger` + show-delay timestamp + `OpenWindowOperation` |
| What goes in the tooltip | Out of scope — any `Document` | `TooltipSource.content`, carried into `OpenWindowOperation.content` and rendered via the existing type dispatcher |
| Multiple tooltips at once | Trivial — multiple `WindowDocument`s | Multiple `TooltipSource` wrappers, each with its own id |

Net effect: tooltips became a side product of the same
input → operation → input → printer loop that drives every other state
change in the editor.
