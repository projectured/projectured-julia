"""
    ProjectionModule

Provides default implementations for projection reference mapping.
This module re-exports core projection types and operations from
`ProjectionApiModule`, `OperationModule`, `ReferenceCaseModule`, and
`ReferenceBuilderModule`, and provides sensible default implementations
for reference mapping functions.

The module provides:
- Default `map_reference_forward` — strips projection wrapper from forward references
- Default `map_reference_backward` — adds projection wrapper to backward references
- Default `read_intent` — handles `ReplaceSelectionOperation` for backward mapping

These defaults work for simple projections where the output structure
directly mirrors the input structure.
"""
module ProjectionModule

using ..ProjectionApiModule
# `import`, not `using`: this module defines the default methods of the four
# interface functions (plus the pure-print entry point).
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward,
                              pure_print_document
using ..IntentModule
using ..OperationModule
# The ReplaceStringRangeOperation / ReplaceNumberRangeOperation branches of
# the default read_intent live in base/projection/ReaderDefaults.jl beside
# the Primitive document types. This module stays Primitive-free.
using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..PrinterContextModule
using ..KeyboardModule
using ..MouseModule
using ..GestureModule

export @projection, pure_print

function print_document(projection, input)
    print_document(projection, nothing, input, PrinterContext())
end

"""
    pure_print(projection, input) -> immutable output tree

Entry point for the pure batch printer (see
[`pure_print_document`](@ref)): project `input` to a fully-built, immutable
output tree with no iomap / reactive / selection machinery.
"""
pure_print(projection, input) =
    pure_print_document(projection, nothing, input, PrinterContext())

# Snapshot the forced output of a projection to the immutable kind, when it is a
# document; non-document outputs (a String, a graphics value) pass through.
_pure_snapshot(x) = x isa Document ? copy_document(ImmutableCell, x) : x
_force_output(o) = o isa AbstractCell ? o[] : o

# Total fallback for any projection without a specialized pure interpreter: run
# the reactive printer once and snapshot its output. Slower than a real pure
# interpreter (it builds the reactive machinery first), but it makes the pure
# pipeline total from day one — a Sequential chain can mix template stages (fast,
# pure) with hand-written stages (this fallback) transparently.
pure_print_document(p::Projection, recursion, input, ctx) =
    _pure_snapshot(_force_output(print_document(p, recursion, input, ctx).output))

"""
    map_reference_forward(projection::Projection, iomap, reference)

Default implementation for forward reference mapping. Strips the projection
wrapper from a reference, returning the inner reference path. This works
for simple projections where output elements directly correspond to input elements.
"""
function map_reference_forward(projection::Projection, iomap, reference)
    r = @reference_case reference begin
        # Whole-element selection maps by identity, but the *output* whole
        # element has the output document's type, not the input's — so the
        # empty path is retyped against `iomap.output`.
        ∅ => EmptyReferencePath(reference_node_type(iomap.output))
        proj(^(projection), inner) => inner
    end
    # Self-type the result (the unwrapped `proj` inner may be a bare path) against
    # the output document, so the strict-typing invariant holds at the source.
    (r === nothing || is_fully_typed(r)) ? r : annotate_reference_types(iomap.output, r)
end

"""
    map_reference_backward(projection::Projection, iomap, reference)

Default implementation for backward reference mapping. Wraps a reference
with the projection to create a reference that points to the output of
the projection. This works for simple projections where input elements
directly correspond to output elements.
"""
function map_reference_backward(projection::Projection, iomap, reference)
    # A whole-element output selection maps back to a whole-element input
    # selection, typed against the input document.
    reference isa EmptyReferencePath &&
        return EmptyReferencePath(reference_node_type(iomap.input))
    # The projection-introduced element has no input pre-image; build the
    # `proj`-wrapped path and annotate it against the input document (the 2-arg
    # `@reference(doc, …)` form) so its node carries the input type (a
    # `ProjectionReference` evaluates to its `output_path`, so the terminal records
    # that path's own type) — keeping the strict-typing invariant.
    @reference(iomap.input, proj(projection, ^(reference)))
end

"""
    read_intent(projection::Projection, iomap, operation)

Default implementation for projection operation reading. Re-targets any
operation that carries a reference from output space to input space using
`map_reference_backward`: the path/reference of `ReplaceSelectionOperation`,
`ReplaceStringRangeOperation`, and `ReplaceNumberRangeOperation`, plus each member
of a `CompoundOperation` recursively (so edits flow back through generic
projections such as `SortingProjection`/`ReversingProjection`/`CopyingProjection`
without a bespoke reader). A `document === nothing` (`editor.document`-rooted)
`ReplaceReferencedValueOperation` has its `reference` re-targeted — this now covers the
former document-replace and sequence-insert/delete operations, which are
`ReplaceReferencedValueOperation`s with a terminal `RangeReference`; a self-contained one
(carrying its own root) is forwarded unchanged. `ToggleCollapseOperation` is
forwarded unchanged; all other operation types return `nothing`.
"""
function read_intent(projection::Projection, iomap, operation)
    # INVARIANT: the set of reference-carrying operation types handled here must
    # stay in sync with `reroot_operation` (OperationModule, operation/Rerooting.jl).
    # A new path-bearing operation missing from either is silently passed through
    # with its reference left in the wrong domain. See package/kernel/doc/operation.md.
    if operation isa Union{KeyPress, KeyDown, MousePress}
        # Generic event fallback: a leaf projection with no authoring reader of
        # its own delegates a raw input gesture to the projection-independent
        # `read_gesture` of its input document. This generalizes the per-projection
        # delegation `SyntaxToText`/`TextToGraphics` already do by hand, so any
        # `@gestures`-declared domain is reachable through any projection with no
        # bespoke reader. (Higher-order projections route events through their own
        # 4-arg readers and never reach this leaf default.)
        input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
        return input isa Document ? read_gesture(input, operation) : nothing
    elseif operation isa ReplaceReferencedValueOperation
        # Self-contained (carries its own root): forward unchanged — this is the
        # path identity-rooted controls (`ObjectToWidget`/`WidgetToGraphics`) take
        # back through any generic projection. Document-rooted (`document === nothing`):
        # re-target the reference, like the dedicated path-bearing ops below.
        operation.document === nothing || return operation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return ReplaceReferencedValueOperation(nothing, input_ref, operation.value)
    elseif operation isa ReplaceSelectionOperation
        input_selection = map_reference_backward(projection, iomap, operation.path)
        input_selection === nothing && return nothing
        return ReplaceSelectionOperation(input_selection)
    # ReplaceString/NumberRange branches live in base/projection/ReaderDefaults.jl
    # (as more-specific `read_intent(::Projection, iomap, ::ReplaceStringRangeOperation)`
    # methods there — they take precedence over this catch-all).
    elseif operation isa CompoundOperation
        mapped = Any[read_intent(projection, iomap, o) for o in operation.operations]
        any(isnothing, mapped) && return nothing
        return CompoundOperation(mapped)
    elseif operation isa ToggleCollapseOperation
        # Collapse state lives at the syntax layer; every other projection
        # forwards the operation up the chain unchanged.
        return operation
    elseif operation isa SelectNextInsertionOperation
        # Editor-global "jump to next hole": carries no reference, so every
        # projection forwards it up the chain unchanged (it resolves against
        # `editor.document` at evaluation time).
        return operation
    else
        return nothing
    end
end

"""
    read_intent(p::Projection, recursion, change::Intent, iomap)

Generic bridge from the symmetric 4-arg `Intent` interface to the 3-arg
reader. For any projection without its own 4-arg method, unwrap the `Intent` and
dispatch `read_intent(p, iomap, payload)` on the operation (when one
has already been produced) or otherwise the gesture (the gesture→operation stage),
then re-wrap the result as a `Intent` with the gesture preserved. Compound
projections that must thread the change to their children override this with a
4-arg method of their own.
"""
function read_intent(p::Projection, recursion, change::Intent, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = read_intent(p, iomap, payload)
    return Intent(change.gesture, op)
end

"""
    @projection struct T [<: Super] ... end

Annotate a Projection struct whose `::Cell` fields should be transparent.
`obj.field` reads the Cell value, `obj.field = val` writes to it;
raw Cells remain accessible via `getfield(obj, :field)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). When at least one
default is present, a keyword constructor is also generated — fields with a
default are optional keywords, fields without one are required keywords —
forwarding into the positional auto-wrapping constructor.

This is `@cell_struct` (the cell layer's transparent-Cell struct codegen) plus
one default: a struct without an explicit supertype gets `<: Projection`. The
injected `:Projection` resolves in the caller's scope (the result is `esc`'d)
— same mechanic as `@iomap`/`IoMap`.
"""
macro projection(structdef)
    structdef.head === :struct || error("@projection expects a struct definition")
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        structdef.args[2] = Expr(:(<:), name_expr, :Projection)
    end
    return esc(cell_struct_exprs(structdef))
end

end # module
