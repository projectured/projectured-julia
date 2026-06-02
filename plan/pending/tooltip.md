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

Pointer-based triggers (true hover) require routing `MouseMotion` events
into the tree by position the same way clicks already are. That plumbing
is the same hover-precision problem the original plan flagged; treat it
as out of scope for v1 (see Open Questions).

### Hover vs selection as the trigger

Same as before: v1 uses selection-based triggers because the selection
cursor is already a first-class concept, and pointer routing is the harder
piece of work. The `trigger` callback signature is
`(tooltip, selection, event) -> Bool` — projections that want hover
behaviour can read a separate `hovered::Reference` cell once
`HoverTrackingProjection` exists.

### Show delay

The same wall-clock-in-the-reader mechanism the original plan described,
just relocated from the printer to the reader (where it more naturally
belongs now that the decision drives an operation, not output).

- `arm_time::Cell{Union{Nothing, Float64}}` is held on the projection
  instance.
- On every event reaching the reader, re-evaluate `trigger`; update
  `arm_time` and `is_open` per the state machine above.
- The editor's frame loop produces frequent enough events that
  `time() >= arm_time + delay` is observed promptly. If the gap is too
  large in practice, introduce a periodic frame-tick event (delivered to
  all readers) or a proper `TimerCell` that self-invalidates after a
  duration.

Reading `time()` in the reader breaks reactive purity in the same way the
original plan did in the printer. Same trade-off; document it.

### Position

`position(tooltip, selection) -> (x, y, w, h)` runs at the moment the
`OpenWindowOperation` is constructed. It needs:

- The screen-coordinate position of whatever the tooltip is anchored to,
  via `char_to_coord` on the relevant iomap.
- The main window's screen-coordinate origin from the backend.
- Clamping to screen bounds (helper).

`(width, height) = (0, 0)` triggers the backend's auto-sizing behaviour
from `WindowDocument`.

Because the position is baked into `OpenWindowOperation` at open time,
moving the tooltip with the cursor (continuous re-positioning) requires
either:

- Re-issuing `OpenWindowOperation` with the new geometry (the manager
  treats a duplicate `id` as "update geometry" rather than "open new"), or
- An explicit `MoveWindowOperation(id, x, y, w, h)` for the in-between
  case.

Pick `MoveWindowOperation` if continuous tracking is needed in v1, else
keep the API minimal.

### Style

`WindowDocument.style = :tooltip` is already part of multiple-windows'
schema. The backend's `_apply_style!(:tooltip, ...)` handles borderless /
always-on-top / non-focusable. The tooltip projection just forwards
`style` to `OpenWindowOperation`.

### Multiple simultaneous tooltips / preview panels

Multiple `TooltipSource` wrappers in the tree, each with its own `id`
(e.g. `:type_tooltip`, `:error_tooltip`, `:preview`). Each
`TooltipDecoratorProjection` instance independently emits its own
`OpenWindowOperation` / `CloseWindowOperation`. The
`WindowManagerProjection` maintains the windows list as the union of all
open requests.

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

## Implementation Steps

### Step 1 — `:tooltip` style on the backend

Pre-work in `SdlBackend._apply_style!`: borderless, always-on-top,
non-focusable (where the platform allows). Add `screen_origin(backend, id)`
or equivalent so tooltip positions can be expressed in screen coordinates
relative to the main window.

Strictly speaking this belongs to multiple-windows; capture it here in case
that plan does not land it.

### Step 2 — `TooltipSource` and the operations

- `@document struct TooltipSource` with `child`, `content`, `style`,
  `id`, `selection` fields.
- `OpenWindowOperation` and `CloseWindowOperation` structs.
- Add the operations to whatever module owns the built-in operation set
  (alongside `QuitEditorOperation`, `ReplaceSelectionOperation`).

### Step 3 — `WindowManagerProjection`

- Struct with `inner::Projection`.
- Printer: delegate to `inner`.
- Reader: route to `inner`, then post-process the returned operation —
  apply `OpenWindowOperation`/`CloseWindowOperation` to the input
  `ScreenDocument.windows` and swallow them; pass other ops through.
- Smoke test: call its reader with a fabricated `OpenWindowOperation` and
  assert a `WindowDocument` appears on the input; then a
  `CloseWindowOperation` and assert it disappears.

### Step 4 — `TooltipDecoratorProjection` skeleton

- Struct with `inner`, `trigger`, `content`, `position`, `style`, `id_of`,
  `delay_ms`, and the `arm_time`/`is_open` cells.
- Printer: delegate to `inner` projecting `child`.
- Reader: implement the state machine without delay (`delay_ms = 0` path);
  emit `OpenWindowOperation` / `CloseWindowOperation` based on
  `trigger`.
- Smoke test: a JSON example with `TooltipSource` wrapping a node and a
  trigger that fires when the selection lands on it. Confirm a tooltip
  window opens on selection and closes when selection moves away.

### Step 5 — Show delay

- Add the `arm_time` cell; gate `OpenWindowOperation` on elapsed time.
- Verify with two example triggers: one that is always-on (window appears
  after `delay_ms`), and one that flips on every selection move (no window
  ever appears under reasonable mouse movement).

### Step 6 — Position derivation

- Surface enough of the iomap and backend window origin to compute
  `(x, y)` near the decorated node's screen coordinates.
- Clamp to screen bounds via SDL display info.
- `(width, height) = (0, 0)` for auto-sizing.

### Step 7 — Example tooltips

Each is a different `content` + (possibly) dispatcher entry:

- **Path tooltip**: for the selected JSON node, show its JSON path as a
  short string document.
- **Type tooltip**: show inferred schema/type.
- **Error tooltip**: show validation errors on a node.
- **Documentation tooltip**: for a Julia function call node, show its
  docstring (reuses any existing Julia documentation projection).

### Step 8 — Multiple simultaneous tooltips

- Two `TooltipSource` wrappers in different parts of the tree, each
  with a distinct `id`. Verify the manager keeps both windows open /
  closed independently and that the reconciler reflects the windows list.

### Step 9 — Optional: pointer-based hover

- A `HoverTrackingProjection` whose reader updates a `hovered::Reference`
  cell on the input `ScreenDocument` in response to `MouseMotion` envelopes
  on the main window.
- Tooltip triggers can then read `hovered` instead of `selection`.
- Defer until selection-based tooltips are exercised in practice.

---

## Open Questions

- **Where does the show-delay timestamp live?** On the
  `TooltipDecoratorProjection` struct (per projection instance, leaks
  across iomaps), in the iomap (rebuilt each frame, would need explicit
  carry), or on the input `TooltipSource` (intrusive — would also
  conveniently survive projection re-instantiation). The first is the
  simplest and matches how other transient projection state would be
  held; reconsider only if it causes trouble.

- **Time in the reactive system.** The cell graph is event-driven;
  sampling `time()` in the reader breaks that purity. Acceptable for v1;
  a `TimerCell` that self-invalidates after a duration is the principled
  fix if frame cadence proves unreliable.

- **Multiple ops per event.** Today's reader contract is one op per
  reader call. If the child reader produces an op *and* the tooltip
  decorator wants to emit an `OpenWindowOperation` on the same event,
  one of them has to be deferred (or batched). Options: (a) priority —
  tooltip ops are emitted only on events that the child didn't handle;
  (b) extend the contract to return a list of operations; (c) queue the
  tooltip op for the next event. (b) is the cleanest if other places
  also start wanting it.

- **Duplicate open / close.** `OpenWindowOperation` for an already-open
  id: replace geometry vs. ignore vs. error. `CloseWindowOperation` for
  an absent id: ignore vs. error. Defaults: replace-on-open (so geometry
  updates are cheap) and ignore-on-close (so re-entry is robust).

- **`MoveWindowOperation`.** Whether continuous tooltip re-positioning is
  worth a third operation type, or whether re-issuing
  `OpenWindowOperation` with the same id is good enough.

- **Interactive tooltips.** v1 drops envelopes targeted at the tooltip
  window's content. Interactive tooltips would route those envelopes into
  the same `WindowDocument.content` sub-iomap that any other window uses
  — since the content is already a regular document, the existing
  routing should work; the only question is whether the tooltip's
  `is_open` state should react to focus/clicks. Defer until needed.

- **Where the `TooltipSource` lives in the input tree.** Wrapping
  individual nodes (`TooltipSource(child=...)`) is conceptually clean
  but requires explicit decoration at every potential tooltip site —
  intrusive for use cases like "tooltip on every JSON value". An
  alternative is a single top-level `TooltipSource` that holds a
  reference to the currently-anchored sub-tree; the trigger becomes a
  comparison against the selection. Decide which use cases warrant
  which shape (likely both, with different decorator subclasses).

- **Pointer tracking precision.** Same as the original plan: SDL motion
  events are coarse; correctly mapping them through the projection to a
  `Reference` requires the same reverse-projection plumbing as
  click-to-select. The plumbing exists; the work is wiring it up for
  motion as well as buttons.

- **Tooltip outliving its trigger.** If `content(...)` is recomputed each
  time `OpenWindowOperation` is built it stays in sync with whatever
  the trigger saw. For a "pinned" tooltip that survives the trigger
  going false, the decorator could promote the open window to an
  ordinary `WindowDocument` (i.e. stop emitting `CloseWindowOperation`
  for it) — out of scope here.

---

## Relationship to the Multiple Windows Plan

| Concern | Multiple windows handles | This plan adds |
|---------|--------------------------|----------------|
| Multi-window output type | `ScreenDocument` / `WindowDocument` | — |
| Opening / closing native windows | `write_to_devices(::ScreenDocument)` reconciler | — |
| Per-window event routing | `EventEnvelope { window_id, event }` | Drops envelopes for tooltip window in v1 |
| Per-window style | `WindowDocument.style` + `_apply_style!` | Defines `:tooltip` style semantics (borderless, on-top, non-focusable) |
| Per-window position / size | `WindowDocument.x/y/width/height` | Tooltip-specific `position` function and screen-coordinate helper |
| Window list as state | `ScreenDocument.windows` `CellVector` | `WindowManagerProjection` mutates it in response to `Open`/`CloseWindowOperation` |
| Trigger to show a window | Out of scope — push/remove `WindowDocument` | `TooltipDecoratorProjection.trigger` + show-delay timestamp + `OpenWindowOperation` |
| What goes in the tooltip | Out of scope — any `Document` | `TooltipSource.content`, carried into `OpenWindowOperation.content` and rendered via the existing type dispatcher |
| Multiple tooltips at once | Trivial — multiple `WindowDocument`s | Multiple `TooltipSource` wrappers, each with its own id |

Net effect: this plan introduces a `TooltipSource` wrapper, a
`TooltipDecoratorProjection` that watches its input and emits
`OpenWindowOperation` / `CloseWindowOperation`, and a
`WindowManagerProjection` that applies those operations to the
`ScreenDocument.windows` list of its input. Tooltips become a side
product of the same input → operation → input → printer loop that drives
every other state change in the editor.
