"""
    ProjectionApiModule

Shared projection interface. Declares the four generic functions every
projection implements — `projection_print`, `projection_read`,
`map_reference_forward`, `map_reference_backward` — dispatched on by all
projection types, primitive and higher-order alike. Keeping the interface here
avoids circular dependencies between projection modules.

The four functions form two symmetric pairs, one per direction of data flow:

- **Forward (printing).** `projection_print` transforms input → output and, for
  the cursor, calls `map_reference_forward` to map the input selection into an
  output selection.
- **Backward (reading).** `projection_read` turns an output-domain event/
  operation back into an input-domain operation and, for the cursor, calls
  `map_reference_backward` to map an output reference into an input reference.

Rule of thumb: **`projection_print` uses `map_reference_forward`;
`projection_read` uses `map_reference_backward`.** The two mappers are the
single source of truth for how a path crosses this projection — written once,
reused on both sides. See [guide/projection-system.md](../../../guide/projection-system.md)
for worked recipes and [guide/selection-deep-dive.md](../../../guide/selection-deep-dive.md)
for the selection mechanism.
"""
module ProjectionApiModule

export projection_print, projection_read, map_reference_forward, map_reference_backward, Projection,
       Change, as_change

"""
    Projection

Abstract base type for all projection types, primitive and higher-order alike.
Subtype this to register with the default `map_reference_forward`,
`map_reference_backward`, and `projection_read` fallbacks (defined in
`ProjectionModule`, `program/src/common/Projection.jl`).
"""
abstract type Projection end

"""
    Change(gesture, operation = nothing)

The backward-flowing unit of the reader pipeline — the symmetric dual of the
document that flows forward through the printer. It carries the same user change
in two coordinate frames:

- `gesture` — the originating input (a device event such as `MousePress`/`KeyDown`,
  or an `EventEnvelope` at the screen layer). **Invariant**: it is threaded
  unchanged through the whole reader chain, so any reader can inspect *what the
  user did*, not just what it currently means.
- `operation` — the change expressed in the current projection's input domain.
  Starts as `nothing` (a "nothing-change") and is filled in / re-mapped by the
  readers as the change travels one domain inward at each step.

A reader returns a `Change`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Change` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`).
"""
struct Change
    gesture::Any
    operation::Any
end

Change(gesture) = Change(gesture, nothing)

"""
    as_change(payload) -> Change

Wrap a legacy reader payload (a raw gesture/event, an `EventEnvelope`, or a
backward-threaded operation) into a `Change`. Used by the 3-argument
compatibility shims so existing 3-arg `projection_read(projection, iomap, x)`
call sites keep working against the 4-arg `Change` interface. The payload goes in
the gesture slot; the generic reader bridge falls back to the gesture slot
whenever the operation slot is empty, so an operation passed this way is still
applied correctly.
"""
as_change(payload) = payload isa Change ? payload : Change(payload, nothing)

"""
    projection_print(projection, recursion, input, context::PrinterContext) -> iomap

Forward half of a projection: transform `input` from this projection's input
domain into its output domain. Returns an `IoMap` recording `projection`,
`input`, `output`, and whatever the reader and the reference maps need to
invert the transformation — crucially the **child IoMaps** when the projection
recurses. Each concrete projection adds a method; compound projections such as
`SequentialProjection` compose arbitrary projections purely via this dispatch.

# Arguments
- `recursion` — the projection to invoke when descending into a child. A leaf
  projection that never descends ignores it. A node projection must thread it
  **twice** — as the projection to call *and* as that call's own `recursion`
  argument:

      projection_print(recursion, recursion, child, child_ctx)

  so the child re-enters the whole pipeline (normally a `RecursiveProjection`
  wrapping a `TypeDispatchingProjection`) instead of this single projection.
  Passing `projection` or `nothing` in either slot silently breaks
  heterogeneous recursion. The 2-arg overload `projection_print(p, input)`
  supplies `nothing`.
- `context::PrinterContext` — downward-flowing per-invocation data: a
  `reference` path locating `input` relative to the document root, plus
  optional layout extent (`available_width`/`available_height`) and an
  extensible `properties` Dict. Extend it for a child with
  `child_context(ctx, step…)` (or `child_context(ctx, full_path)`) before
  recursing; the top level passes a fresh `PrinterContext()`.

# Implementing a printer
1. Build the output document from `input`.
2. If `input` has children, **recurse** into each via `recursion` (see above)
   with `child_context(ctx, <step to that child>)`, **store the returned child
   IoMaps in your own IoMap** (`ChildrenIoMap`, or a bespoke field), and build
   your output's children from each `child_iomap.output`. Storing the child
   IoMaps is what lets the reader and the reference maps recurse in lockstep.
3. **Wire the output selection.** The output document's `selection::Cell` is
   computed reactively, not threaded as a parameter. The canonical form maps
   the input selection forward through this projection's own mapper:

       output.selection = Cell(() -> map_reference_forward(p, iomap, input.selection))

   making `map_reference_forward` the one definition of the path mapping.
   Two practical wrinkles:
   - A node projection's `iomap` does not exist yet when the selection cell is
     built. Use the deferred-iomap trick: `iomap_cell = Cell(nothing)`, close
     over it in the thunk, and assign `iomap_cell[] = iomap` after constructing
     the IoMap (see `CopyingProjection`).
   - A leaf whose input and output selection formats are identical may instead
     *share* the same `selection::Cell` (`getfield(input, :selection)`) on both
     sides — writes are then visible on both with no mapping. Valid only
     leaf-to-leaf (selection deep dive §7).
"""
function projection_print end

"""
    projection_read(projection, recursion, change::Change, iomap) -> Change

Backward half of a projection — the symmetric dual of `projection_print`: both
read `(projection, recursion, payload, context)`. The payload is a `Change`
(gesture + operation); the context is the printer's `iomap` (the correspondence
that the forward pass recorded). The reader turns an output-domain change into an
input-domain one, returning a `Change` whose `operation` is filled in / re-mapped
and whose `gesture` is preserved, or a nothing-change (`operation === nothing`) if
this projection has nothing to say about it.

Most projections need no `projection_read` method at all: the generic bridge in
`ProjectionModule` unwraps the `Change` and dispatches the legacy 3-arg
`projection_read(projection, iomap, event_or_op)` on the gesture (when no
operation has been produced yet) or the operation, then re-wraps the result with
the gesture preserved. Leaf projections therefore keep their 3-arg methods; only
compound projections that thread the change to children override the 4-arg form.

The editor hands the raw device event (key press, mouse click) to the
**top-level** projection's `projection_read`; from there, routing is entirely
up to each projection. A `SequentialProjection` forwards the event down its
chain and threads the operation that comes back up through each earlier step,
translating it one domain closer to the input at every step. A different
projection might instead dispatch the event to the sub-projection of one of its
document parts (e.g. `CopyingProjection` over a multi-window screen routes each
event to the matching window's content). So `event_or_op` is a raw event when a
parent handed this projection the bare event, or an `Operation` another
projection already produced — and the method returns an `Operation` in *this*
projection's input domain, or `nothing`.

The default method (in `ProjectionModule`) handles `ReplaceSelectionOperation`
by mapping its path with `map_reference_backward`, so a projection that only
moves the cursor needs **no** `projection_read` method. When you do write one,
these are the moves available — from the lightest touch to the most involved:

- **Re-target the references.** Most often the incoming operation is the right
  *kind* and only its references need moving from the output domain to the input
  domain with `map_reference_backward` — rewrite the `.reference` of a
  `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`, or the `.path`
  of a `ReplaceSelectionOperation` (what the default does), then rebuild the op.
- **Convert to a different operation.** It is perfectly valid to turn the
  incoming operation into a *completely different* one — retype it (e.g.
  `JsonNumberToSyntaxLeaf` turns an incoming `StringReplaceRangeOperation` into a
  `NumberReplaceRangeOperation` so the evaluator re-parses the value), or replace
  it outright with whatever operation expresses the same intent in this
  projection's input domain.
- **Recurse, then extend.** When `projection_print` descended into children, the
  reader mirrors it: forward the event/operation to the matching child's
  `projection_read`, take the operation it returns, and extend that operation to
  *this* projection's context — typically by prepending the reference steps that
  reach the child (reuse `map_reference_backward`).
- **Probe a child to decide.** A reader may *speculatively* recurse into a
  document part's reader just to see what operation it would return, and use that
  answer to decide its own final operation — e.g. to choose among alternatives,
  or to act only when the child declines by returning `nothing`.

Whichever moves it makes, a projection returns an `Operation` in its own input
domain (or `nothing`); the operation the **top-level** projection ultimately
returns is the final answer the editor applies to the document.
"""
function projection_read end

"""
    map_reference_forward(projection, iomap, reference) -> reference_or_nothing

Map an **input reference** (steps understood from `projection`'s input
document) to an **output reference** (steps understood from its output
document). Returns `nothing` when the input reference has no image in the
output (e.g. an element dropped by a filtering projection).

This is the mapper `projection_print` uses to wire the output selection (see
its docstring), so getting it right gives the forward cursor mapping for free.

- Express the cases with `@reference_case` (see
  [guide/editor/reference.md](../../../guide/editor/reference.md)).
- **Recurse in lockstep with the printer.** If `projection_print` recursed into
  children, so must this: peel only the steps this projection owns, look up the
  child the peeled step selects in the **stored child IoMaps**, and delegate the
  remaining tail to that child projection's own `map_reference_forward`. Do *not*
  re-walk the input document dispatching on each child's concrete type — that
  couples the projection to its children's domains and breaks composition with
  other domains (see [guide/projection-system.md](../../../guide/projection-system.md)).
- If the input reference begins with `ProjectionReference(projection, output_path)`,
  strip that step and return `output_path` directly — it exists precisely to
  embed an already-translated output reference inside an input reference, and
  forward mapping is where it gets unwrapped.
"""
function map_reference_forward end

"""
    map_reference_backward(projection, iomap, reference) -> reference_or_nothing

Map an **output reference** (steps understood from `projection`'s output
document) to an **input reference** (steps understood from its input document).
Returns `nothing` when the output reference has no pre-image in the input.

This is the mapper `projection_read` uses (directly in the default method) to
translate selections — and the one you reuse to re-target edit operations. Like
its forward twin it must **recurse in lockstep with the printer**: peel the
output steps that lead to a child, look that child up in the **stored child
IoMaps**, delegate the tail to its own `map_reference_backward`, then prepend the
input-domain steps that reach the child. As in the forward direction, delegate
through the child IoMap rather than dispatching on the child's concrete type, so
the projection stays independent of whatever domain rendered each child.

## Positions with no input pre-image

When part of the output reference is projection-introduced (a delimiter,
separator, bracket, indentation) it has no input counterpart. Represent it by
crossing into the output domain **as late as possible**: keep input-domain
steps for as long as the path still has a pre-image, then wrap *only the
genuinely output-only tail* in this projection's own step —

    matched_input_prefix + ProjectionReference(projection, unmatched_output_suffix)

The resulting path reads like a sentence: the input steps say where in the
document you are, and the `ProjectionReference(projection, …)` step marks the
exact point where you cross into something that exists only in `projection`'s
output. Because `map_reference_forward` strips that same step, the path
round-trips cleanly. (When a projection's introduced positions are not separately
addressable — the brackets/commas of a node, say — it is fine to collapse the
whole group to a single flattened character offset, `ProjectionReference(p,
{flat})`, which `_syntax_to_flat` inverts; the `*ToSyntax` node readers use this
for the delimiters they own. Use the fine-grained form above when the individual
positions matter.)
"""
function map_reference_backward end

end # module
