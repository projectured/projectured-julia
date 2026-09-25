# Fragment of `ProjectionModule` — the projection **contract**: the `Projection`
# abstract type every projection subtypes, and the four open generics every one
# of them implements. Nothing here carries a body — the fallback of each generic
# lives in `ProjectionDefaults.jl`, the `@projection` codegen in
# `ProjectionMacro.jl`, and the template engine that writes most concrete
# projections in `ProjectionTemplate.jl`.


"""
    Projection

A rule that shows one kind of document as another.

Use it as the type of anything that turns what a document holds into what a
reader sees: a tree of data into text, text into what is drawn, a chart into
lines and words. A projection pairs a printer, which goes one way, with a
reader, which brings an edit back, so what is shown can be edited.

# Example

    struct BoxToText <: Projection end
    print_document(::BoxToText, recursion, box, context) = SimpleIoMap(...)

See also `print_document` and `read_intent`, the two halves, and the guide
`kernel/projection-system`.

Abstract base type for all projection types, primitive and higher-order alike.
Subtype this to inherit the default `map_reference_forward`,
`map_reference_backward` and `read_intent` behaviour, which every projection
gets unless it overrides the function it wants to change.
"""
abstract type Projection end

"""
    print_document(projection, recursion, input, context::PrinterContext) -> iomap

Show a document as another one: the half of a projection that goes from what is
held to what is seen.

Use it to run a projection over a document and get both the result and the map
back to where each part came from. Call it to draw a document, to serialize
one, or to see what a projection makes of an input while writing one. What it
answers is an IoMap: the output, and what a later edit needs to find its way
home.

# Example

    iomap = print_document(projection, projection, document, PrinterContext())
    drawn = iomap.output

See also `read_intent`, which brings an edit back the other way,
`map_reference_forward`, which follows a place through, and the guide
`kernel/projection-system`.

Forward half of a projection: transform `input` from this projection's input
domain into its output domain. Returns an `IoMap` recording `projection`,
`input`, `output`, and whatever the reader and the reference maps need to
invert the transformation — crucially the **child IoMaps** when the projection
recurses. Each concrete projection adds a method; compound projections compose
arbitrary projections purely via this dispatch.

# Arguments
- `recursion` — the projection to invoke when descending into a child. A leaf
  projection that never descends ignores it. A node projection recurses into a
  child with the `print_child` helper:

      print_child(recursion, child, child_ctx)

  which expands to `print_document(recursion, recursion, child, child_ctx)` —
  `recursion` is *both* the projection to call and that call's own `recursion`
  argument, so the child re-enters the whole pipeline (normally a
  recursive projection wrapping a type-dispatcher) instead of this
  single projection. Always recurse through the helper rather than open-coding
  the doubled argument. The 2-arg overload `print_document(p, input)` supplies
  `nothing`.
- `context::PrinterContext` — downward-flowing per-invocation data: a
  `reference` path locating `input` relative to the document root, plus
  the range of each axis (`minimum_width`/`maximum_width`,
  `minimum_height`/`maximum_height`) and an extensible `properties` Dict. Extend it for a child with
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

       output.selection =
           Cell(@computation map_reference_forward(p, iomap, input.selection))

   making `map_reference_forward` the one definition of the path mapping.
   Two practical wrinkles:
   - A node projection's `iomap` does not exist yet when the selection cell is
     built. Use the deferred-iomap trick: `iomap_cell = Cell(nothing)`, close
     over it in the thunk, and assign `iomap_cell[] = iomap` after constructing
     the IoMap.
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
goes back through the full pipeline (normally a recursive projection wrapping a
type-dispatcher) instead of one projection. Node printers should
recurse through this helper so the doubled `recursion` argument lives in exactly
one place and call sites read as "recurse into this child".
"""
function print_child end

"""
    print_document_pure(projection, recursion, input, ctx) -> output tree

The **pure** forward half: a second interpreter of a projection that produces the
projected *output document tree directly* — no iomap, no reactive cells, no
selection wiring — for batch/export use (write_image / write_pdf / text
serialization) where nothing is edited and no selection is mapped back. Output
nodes are immutable-kind, so the tree is cheap to allocate and cheap to traverse
repeatedly (multi-page layout, serialization).

Higher-order projections (Sequential / Recursive / TypeDispatching) thread it so a
whole *pipeline* is pure; every concrete projection falls back to a snapshot of the
reactive output (`copy_document(ImmutableCell, print_document(...).output[])`) — slower (it builds the
reactive machinery first, then copies), but total, so `print_pure` works end-to-end
for any pipeline. A genuinely fast per-projection interpreter is future work,
justified only where a profile shows it pays (most render-stage projections are
hand-written, not template-generated). See plan/pending/cell-kind-documents.md,
Phase 6.
"""
function print_document_pure end

"""
    print_child_pure(recursion, input, ctx) -> output tree

Pure analogue of [`print_child`](@ref): recurse into a child
through the whole pipeline, producing pure (immutable) output.
"""
function print_child_pure end

"""
    read_intent(projection, recursion, change::Intent, iomap) -> Intent

Turn what a person did on what they see into an edit of what the document
holds: the half of a projection that comes back.

Use it to say what a key press, a click or a drag means for the input of a
projection. It takes the gesture or the edit that the output domain received,
and answers the edit for the input domain, or nothing when this projection has
nothing to say about it. Most projections need no method of their own: the
default moves the cursor by mapping its place back.

# Example

    read_intent(::BoxToText, iomap, event::KeyDown) =
        event.key == :backspace ? ShrinkBoxOperation(iomap.input) : nothing

See also `print_document`, which goes the other way, `map_reference_backward`,
which brings a place back, and the guide `kernel/projection-system`.

Backward half of a projection — the symmetric dual of `print_document`: both
read `(projection, recursion, payload, context)`. The payload is a `Intent`
(gesture + operation); the context is the printer's `iomap` (the correspondence
that the forward pass recorded). The reader turns an output-domain change into an
input-domain one, returning a `Intent` whose `operation` is filled in / re-mapped
and whose `gesture` is preserved, or a nothing-change (`operation === nothing`) if
this projection has nothing to say about it.

Most projections need no `read_intent` method at all: the generic bridge in
`ProjectionModule` unwraps the `Intent` and dispatches the 3-arg
`read_intent(projection, iomap, event_or_op)` on the gesture (when no
operation has been produced yet) or the operation, then re-wraps the result with
the gesture preserved. Leaf projections therefore keep their 3-arg methods; only
compound projections that thread the change to children override the 4-arg form.

The editor hands the raw device event (key press, mouse click) to the
**top-level** projection's `read_intent`; from there, routing is entirely
up to each projection. A chaining projection forwards the event down its
chain and threads the operation that comes back up through each earlier step,
translating it one domain closer to the input at every step. A different
projection might instead dispatch the event to the sub-projection of one of its
document parts (e.g. a projection over a multi-window screen routes each
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
  text- or number-range replace operation, or the `.path`
  of a `ReplaceSelectionOperation` (what the default does), then rebuild the op.
- **Convert to a different operation.** It is perfectly valid to turn the
  incoming operation into a *completely different* one — retype it (e.g. a
  projection over a numeric leaf turns an incoming text-range replace
  into a number-range replace so the evaluator re-parses the edited text
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

Follow a place in a document to where it is shown.

Use it to carry a selection, a caret or a coordinate from what a document holds
to what a reader sees, through one projection. It answers nothing when the
place is not shown at all, which is what a projection that hides a part says.
The printer wires the shown selection with it, so a projection that maps its own
one step gets the moving cursor for nothing.

# Example

    shown = map_reference_forward(projection, iomap, document.selection)

See also `map_reference_backward`, which goes the other way, and the guide
`kernel/reference`.

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
  a positioned element's image is a `PointReferenceStep` (its location), not a
  structural path. So a forward map legitimately returns a `PointReferenceStep` once
  the chain reaches that coordinate domain. A container that places a child at a
  pixel offset then contributes **only its own offset**: if the child's image is a
  `PointReferenceStep` (a coordinate), add this container's offset to it; if it is a
  structural path, prepend / pass the structural steps unchanged. Distinguish by
  the *result*, never by the child's type — **coordinates accumulate, paths stay
  paths**. This is what lets the one mapper serve both selection wiring (paths)
  and position resolution (coordinates — e.g. anchoring a follower element to the
  one that triggered it).
- **Do not add a parallel "resolve position" generic.** Because forward mapping
  is this *single* recursive map method, every compositional wrapper
  (chaining, recursive, type-dispatching, …)
  already threads or composes it for free. A second generic for coordinate
  resolution would force each of those wrappers to re-implement the same
  composition. Reuse `map_reference_forward` instead: a projection takes part
  just by mapping its own one step. An element nests in any container and vice
  versa precisely because each step is self-contained — peel your step, delegate
  the tail, add only your own contribution.
- **A popup is not placed by a reference.** The widget that opens one answers
  its position in its own frame, and each reader that read the widget with a
  press moves that position back into its own frame on the way up, with
  `map_operation_position` of the graphics package. The reader that moved the
  press down is the one that moves the popup up, so the two can not disagree.
- If the input reference begins with `ProjectionReferenceStep(projection, output_path)`,
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

    matched_input_prefix + ProjectionReferenceStep(projection, unmatched_output_suffix)

The resulting path reads like a sentence: the input steps say where in the
document you are, and the `ProjectionReferenceStep(projection, …)` step marks the
exact point where you cross into something that exists only in `projection`'s
output. Because `map_reference_forward` strips that same step, the path
round-trips cleanly. (When a projection's introduced positions are not separately
addressable — the brackets/commas of a node, say — it is fine to collapse the
whole group to a single flattened character offset, `ProjectionReferenceStep(p,
{flat})`, which the projection's own flat-offset reader inverts; this is the usual
choice for the delimiters a node owns. Use the fine-grained form above when the
individual positions matter.)

## Coordinates are an input domain too

The mirror of `map_reference_forward`'s "the output domain may be coordinates":
at the bottom of a render chain the *output* reference handed to this mapper can
be a `PointReferenceStep` (a click point) rather than a structural step. A container
inverts its own placement — subtract the offset it positioned the child at, then
delegate the translated point to the child's own `map_reference_backward` — never
dispatching on the child's type. Coordinates and structural paths travel the same
single mapper in both directions; do not add a parallel generic for either.
"""
function map_reference_backward end

# ── The children-container seam (methods in ChildrenContainer.jl) ──────

"""
    make_children_container(cells_or_thunk) -> children container

Construct a children container from either a `Vector` of cells or a
`Function` (a zero-argument thunk producing the child sequence
reactively).
"""
function make_children_container end

"""
    get_children_container_type() -> Type

The concrete children container type a registrant supplies. Used by the
template engine for `TypeReferenceStep(...)` markers.
"""
function get_children_container_type end
