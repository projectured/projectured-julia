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
- Default `projection_read` — handles `ReplaceSelectionOperation` for backward mapping

These defaults work for simple projections where the output structure
directly mirrors the input structure.
"""
module ProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..ReactiveModule: Cell
import ..ReferenceModule: EmptyReferencePath
import ..PrinterContextModule: PrinterContext
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"

export @projection

function projection_print(projection, input)
    projection_print(projection, nothing, input, PrinterContext())
end

"""
    map_reference_forward(projection::Projection, iomap, reference)

Default implementation for forward reference mapping. Strips the projection
wrapper from a reference, returning the inner reference path. This works
for simple projections where output elements directly correspond to input elements.
"""
function map_reference_forward(projection::Projection, iomap, reference)
    @reference_case reference begin
        ∅ => @reference()                          # whole-element selection: identity
        proj(^(projection), inner) => inner
    end
end

"""
    map_reference_backward(projection::Projection, iomap, reference)

Default implementation for backward reference mapping. Wraps a reference
with the projection to create a reference that points to the output of
the projection. This works for simple projections where input elements
directly correspond to output elements.
"""
function map_reference_backward(projection::Projection, iomap, reference)
    reference isa EmptyReferencePath && return @reference()
    @reference proj(projection, ^(reference))
end

"""
    projection_read(projection::Projection, iomap, operation)

Default implementation for projection operation reading. Re-targets any
operation that carries a reference from output space to input space using
`map_reference_backward`: the selection path of a `ReplaceSelectionOperation`,
and the `reference` of a `StringReplaceRangeOperation` /
`NumberReplaceRangeOperation` (so edits flow back through generic projections
such as `SortingProjection`/`ReversingProjection`/`CopyingProjection` without a
bespoke reader). `ToggleCollapseOperation` is forwarded unchanged; all other
operation types return `nothing`.
"""
function projection_read(projection::Projection, iomap, operation)
    # INVARIANT: the set of reference-carrying operation types handled here must
    # stay in sync with `OperationRerootingModule.prepend_steps_to_op`. A new
    # path-bearing operation missing from either is silently passed through with
    # its reference left in the wrong domain. See guide/operations.md.
    if operation isa ReplaceSelectionOperation
        input_selection = map_reference_backward(projection, iomap, operation.path)
        input_selection === nothing && return nothing
        return ReplaceSelectionOperation(input_selection)
    elseif operation isa StringReplaceRangeOperation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return StringReplaceRangeOperation(input_ref, operation.replacement)
    elseif operation isa NumberReplaceRangeOperation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return NumberReplaceRangeOperation(input_ref, operation.replacement)
    elseif operation isa ToggleCollapseOperation
        # Collapse state lives at the syntax layer; every other projection
        # forwards the operation up the chain unchanged.
        return operation
    else
        return nothing
    end
end

"""
    projection_read(p::Projection, recursion, change::Change, iomap)

Generic bridge from the symmetric 4-arg `Change` interface to the legacy 3-arg
reader. For any projection without its own 4-arg method, unwrap the `Change` and
dispatch the legacy `projection_read(p, iomap, payload)` on the operation (when one
has already been produced) or otherwise the gesture (the gesture→operation stage),
then re-wrap the result as a `Change` with the gesture preserved. Compound
projections that must thread the change to their children override this with a
4-arg method of their own.
"""
function projection_read(p::Projection, recursion, change::Change, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = projection_read(p, iomap, payload)
    return Change(change.gesture, op)
end

"""
    @projection struct T [<: Super] ... end

Annotate a Projection struct whose `::Cell` fields should be transparent.
`obj.field` reads the Cell value, `obj.field = val` writes to it;
raw Cells remain accessible via `getfield(obj, :field)`.
"""
macro projection(structdef)
    structdef.head === :struct || error("@projection expects a struct definition")
    name_expr = structdef.args[2]
    struct_name = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[1] : name_expr
    body = structdef.args[3]
    cell_fields = Symbol[]
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            ex.args[2] = :Cell
        end
    end
    isempty(cell_fields) && return esc(structdef)

    cell_set = Set(cell_fields)

    # Collect all field names/types for the auto-wrapping constructor
    all_fields = Tuple{Symbol, Any}[]
    for ex in body.args
        if ex isa Symbol
            push!(all_fields, (ex, nothing))
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(all_fields, (ex.args[1], ex.args[2]))
        end
    end

    # Replace the default inner constructor with one that auto-wraps
    # non-Cell values into Cell for Cell-typed fields.
    if !isempty(all_fields)
        arg_names = [gensym(f[1]) for f in all_fields]
        new_args = map(enumerate(all_fields)) do (i, (fname, ftype))
            a = arg_names[i]
            fname in cell_set ? :($a isa Cell ? $a : Cell($a)) : a
        end
        ctor = :(function $(struct_name)($(arg_names...))
            $(Expr(:call, :new, new_args...))
        end)
        push!(body.args, ctor)
    end

    # Build if-elseif chain for getproperty
    get_body = :(getfield(obj, name))
    for fname in reverse(cell_fields)
        get_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[]),
                        get_body)
    end
    getprop = :(function Base.getproperty(obj::$(struct_name), name::Symbol)
        $get_body
    end)

    # Build if-elseif chain for setproperty!
    set_body = :(setfield!(obj, name, val))
    for fname in reverse(cell_fields)
        set_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[] = val),
                        set_body)
    end
    setprop = :(function Base.setproperty!(obj::$(struct_name), name::Symbol, val)
        $set_body
    end)

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop))
end

end # module
