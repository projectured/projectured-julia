"""
    ProjectionApiModule

Shared projection interface. Declares the four generic functions every
projection implements — `print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward` — dispatched on by all
projection types, primitive and higher-order alike. Keeping the interface here
avoids circular dependencies between projection modules.

The four functions form two symmetric pairs, one per direction of data flow:

- **Forward (printing).** `print_document` transforms input → output and, for
  the cursor, calls `map_reference_forward` to map the input selection into an
  output selection.
- **Backward (reading).** `read_intent` turns an output-domain event/
  operation back into an input-domain operation and, for the cursor, calls
  `map_reference_backward` to map an output reference into an input reference.

Rule of thumb: **`print_document` uses `map_reference_forward`;
`read_intent` uses `map_reference_backward`.** The two mappers are the
single source of truth for how a path crosses this projection — written once,
reused on both sides.

# The recursion contract

These four functions are **the** interface every projection implements — nothing
else is universal. The contract that keeps arbitrary projections composable is:

> Recursion across projections flows **only** through these four functions. When a
> projection descends into a child document, each function hands that child to the
> **child projection's own** version of *the same* function. The vehicles are the
> `recursion` parameter — invoked via `print_child(recursion, child,
> ctx)` on the printer side — and the **stored child IoMaps**
> (`ChildrenIoMap.child_iomaps`) that the reader and both mappers walk on the
> backward side. Each function maps its **own single level** and delegates the rest.

Two things are therefore **forbidden**:

1. **No fifth recursive function.** A projection must not introduce a *new*
   generic function to perform descent. The four above are implemented by every
   projection; a fifth would not be, so the first pipeline that composes a
   projection needing it with one that does not breaks at that boundary. All
   descent must ride the functions everyone already implements. (This is also why
   the contract is validated *externally*, by a harness driving these four — see
   [documentation/testing.md](../../../../documentation/testing.md) — never by adding
   an interface method.)
2. **No self-walking / flattening by child type.** A function must not recurse over
   the input (or output) subtree itself, dispatching on each child's concrete type,
   and bake the whole subtree into its result. That hard-codes which projection
   renders each descendant and forecloses composing a child with another domain or
   a substituted projection — the "School B" anti-pattern. Delegate through the
   child IoMap / `recursion` instead ("School A").

See [package/kernel/doc/projection-system.md](../../doc/projection-system.md)
("The recursion contract" and "Recursion across projections") for worked recipes
and [package/kernel/doc/selection.md](../../doc/selection.md)
for the selection mechanism.
"""
module ProjectionApiModule

export print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection,
       pure_print_document, pure_print_child

"""
    Projection

Abstract base type for all projection types, primitive and higher-order alike.
Subtype this to register with the default `map_reference_forward`,
`map_reference_backward`, and `read_intent` fallbacks (defined in
`ProjectionModule`, `package/kernel/main/common/Projection.jl`).
"""
abstract type Projection end

"""
    print_document(projection, recursion, input, context::PrinterContext) -> iomap

Forward half of a projection: transform `input` from this projection's input
domain into its output domain. Returns an `IoMap` recording `projection`,
`input`, `output`, and whatever the reader and the reference maps need to
invert the transformation — crucially the **child IoMaps** when the projection
recurses. Each concrete projection adds a method; compound projections such as
`ChainingProjection` compose arbitrary projections purely via this dispatch.

# Arguments
- `recursion` — the projection to invoke when descending into a child. A leaf
  projection that never descends ignores it. A node projection recurses into a
  child with the `print_child` helper:

      print_child(recursion, child, child_ctx)

  which expands to `print_document(recursion, recursion, child, child_ctx)` —
  `recursion` is *both* the projection to call and that call's own `recursion`
  argument, so the child re-enters the whole pipeline (normally a
  `RecursiveProjection` wrapping a `TypeDispatchingProjection`) instead of this
  single projection. Always recurse through the helper rather than open-coding
  the doubled argument. The 2-arg overload `print_document(p, input)` supplies
  `nothing`.
- `context::PrinterContext` — downward-flowing per-invocation data: a
  `reference` path locating `input` relative to the document root, plus
  optional layout extent (`available_width`/`available_height`) and an
  extensible `properties` Dict. Extend it for a child with
  `make_child_context(ctx, step…)` (or `make_child_context(ctx, full_path)`) before
  recursing; the top level passes a fresh `PrinterContext()`.

# Implementing a printer
1. Build the output document from `input`.
2. If `input` has children, **recurse** into each via `recursion` (see above)
   with `make_child_context(ctx, <step to that child>)`, **store the returned child
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

# Delegate one level; never flatten the subtree

**Transform only your own node and hand every child to `recursion`** — even when
the child is the same domain you are. The preferred design is to recurse as
*little* as possible: a node projection descends exactly one level and delegates
each child through `recursion`, rather than walking its input subtree itself and
baking the whole tree into its output. Self-walking a subtree hard-codes which
projection renders each descendant and forecloses **unforeseen combinations of
documents and projections** — a child might be a different domain, or rendered by
a substituted projection, and only delegation lets the recursion follow whatever
projection actually runs. This is the printer-side form of the "delegate, don't
re-walk by type" rule the reference mappers follow (see `map_reference_forward`).
"""
function print_document end

"""
    print_child(recursion, input, ctx) -> iomap

Project a child by re-entering the whole pipeline. Equivalent to
`print_document(recursion, recursion, input, ctx)`: `recursion` is both the
projection to invoke *and* that call's own `recursion` argument, so the child
goes back through the full pipeline (normally a `RecursiveProjection` wrapping a
`TypeDispatchingProjection`) instead of one projection. Node printers should
recurse through this helper so the doubled `recursion` argument lives in exactly
one place and call sites read as "recurse into this child".
"""
print_child(recursion, input, ctx) =
    print_document(recursion, recursion, input, ctx)

"""
    pure_print_document(projection, recursion, input, ctx) -> output tree

The **pure** forward half: a second interpreter of a projection that produces the
projected *output document tree directly* — no iomap, no reactive cells, no
selection wiring — for batch/export use (write_image / write_pdf / text
serialization) where nothing is edited and no selection is mapped back. Output
nodes are immutable-kind, so the tree is cheap to allocate and cheap to traverse
repeatedly (multi-page layout, serialization).

Higher-order projections (Sequential / Recursive / TypeDispatching) thread it so a
whole *pipeline* is pure; every concrete projection falls back to a snapshot of the
reactive output (`copy_document(ImmutableCell, print_document(...).output[])`) — slower (it builds the
reactive machinery first, then copies), but total, so `pure_print` works end-to-end
for any pipeline. A genuinely fast per-projection interpreter is future work,
justified only where a profile shows it pays (most render-stage projections are
hand-written, not template-generated). See plan/pending/cell-kind-documents.md,
Phase 6.
"""
function pure_print_document end

"""
    pure_print_child(recursion, input, ctx) -> output tree

Pure analogue of [`print_child`](@ref): recurse into a child
through the whole pipeline, producing pure (immutable) output.
"""
pure_print_child(recursion, input, ctx) =
    pure_print_document(recursion, recursion, input, ctx)

"""
    read_intent(projection, recursion, change::Intent, iomap) -> Intent

Backward half of a projection — the symmetric dual of `print_document`: both
read `(projection, recursion, payload, context)`. The payload is a `Intent`
(gesture + operation); the context is the printer's `iomap` (the correspondence
that the forward pass recorded). The reader turns an output-domain change into an
input-domain one, returning a `Intent` whose `operation` is filled in / re-mapped
and whose `gesture` is preserved, or a nothing-change (`operation === nothing`) if
this projection has nothing to say about it.

Most projections need no `read_intent` method at all: the generic bridge in
`ProjectionModule` unwraps the `Intent` and dispatches the legacy 3-arg
`read_intent(projection, iomap, event_or_op)` on the gesture (when no
operation has been produced yet) or the operation, then re-wraps the result with
the gesture preserved. Leaf projections therefore keep their 3-arg methods; only
compound projections that thread the change to children override the 4-arg form.

The editor hands the raw device event (key press, mouse click) to the
**top-level** projection's `read_intent`; from there, routing is entirely
up to each projection. A `ChainingProjection` forwards the event down its
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
moves the cursor needs **no** `read_intent` method. When you do write one,
these are the moves available — from the lightest touch to the most involved:

- **Re-target the references.** Most often the incoming operation is the right
  *kind* and only its references need moving from the output domain to the input
  domain with `map_reference_backward` — rewrite the `.reference` of a
  `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`, or the `.path`
  of a `ReplaceSelectionOperation` (what the default does), then rebuild the op.
- **Convert to a different operation.** It is perfectly valid to turn the
  incoming operation into a *completely different* one — retype it (e.g. a
  projection over a numeric leaf turns an incoming `ReplaceStringRangeOperation`
  into a `ReplaceNumberRangeOperation` so the evaluator re-parses the edited text
  as a number), or replace it outright with whatever operation expresses the same
  intent in this projection's input domain.
- **Recurse, then extend.** When `print_document` descended into children, the
  reader mirrors it: forward the event/operation to the matching child's
  `read_intent`, take the operation it returns, and extend that operation to
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
function read_intent end

"""
    map_reference_forward(projection, iomap, reference) -> reference_or_nothing

Map an **input reference** (steps understood from `projection`'s input
document) to an **output reference** (steps understood from its output
document). Returns `nothing` when the input reference has no image in the
output (e.g. an element dropped by a filtering projection).

This is the mapper `print_document` uses to wire the output selection (see
its docstring), so getting it right gives the forward cursor mapping for free.

- Express the cases with `@reference_case` (see
  [package/kernel/doc/reference.md](../../doc/reference.md)).
- **Recurse in lockstep with the printer.** If `print_document` recursed into
  children, so must this: peel only the steps this projection owns, look up the
  child the peeled step selects in the **stored child IoMaps**, and delegate the
  remaining tail to that child projection's own `map_reference_forward`. Do *not*
  re-walk the input document dispatching on each child's concrete type — that
  couples the projection to its children's domains and breaks composition with
  other domains (see [package/kernel/doc/projection-system.md](../../doc/projection-system.md)).
- **The output domain may be coordinates, not only structure.** "Output
  reference" means *whatever reference addresses this projection's output
  domain*. At the bottom of a render chain that is a **coordinate** domain, where
  a positioned element's image is a `PointReference` (its location), not a
  structural path. So a forward map legitimately returns a `PointReference` once
  the chain reaches that coordinate domain. A container that places a child at a
  pixel offset then contributes **only its own offset**: if the child's image is a
  `PointReference` (a coordinate), add this container's offset to it; if it is a
  structural path, prepend / pass the structural steps unchanged. Distinguish by
  the *result*, never by the child's type — **coordinates accumulate, paths stay
  paths**. This is what lets the one mapper serve both selection wiring (paths)
  and position resolution (coordinates — e.g. anchoring a follower element to the
  one that triggered it).
- **Do not add a parallel "resolve position" generic.** Because forward mapping
  is this *single* recursive map method, every compositional wrapper
  (`ChainingProjection`, `RecursiveProjection`, `TypeDispatchingProjection`, …)
  already threads or composes it for free. A second generic for coordinate
  resolution would force each of those wrappers to re-implement the same
  composition. Reuse `map_reference_forward` instead: a projection takes part
  just by mapping its own one step. An element nests in any container and vice
  versa precisely because each step is self-contained — peel your step, delegate
  the tail, add only your own contribution.
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

This is the mapper `read_intent` uses (directly in the default method) to
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
{flat})`, which the projection's own flat-offset reader inverts; this is the usual
choice for the delimiters a node owns. Use the fine-grained form above when the
individual positions matter.)

## Coordinates are an input domain too

The mirror of `map_reference_forward`'s "the output domain may be coordinates":
at the bottom of a render chain the *output* reference handed to this mapper can
be a `PointReference` (a click point) rather than a structural step. A container
inverts its own placement — subtract the offset it positioned the child at, then
delegate the translated point to the child's own `map_reference_backward` — never
dispatching on the child's type. Coordinates and structural paths travel the same
single mapper in both directions; do not add a parallel generic for either.
"""
function map_reference_backward end

end # module
