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

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..OperationModule: ReplaceSelectionOperation
import ..ReactiveModule: Cell
import ..ReferenceModule: EmptyReferencePath
import ..ProjectionContextModule: ProjectionContext
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"

export @projection

function projection_print(projection, input)
    projection_print(projection, input, nothing, ProjectionContext())
end

"""
    map_reference_forward(projection::Projection, iomap, reference)

Default implementation for forward reference mapping. Strips the projection
wrapper from a reference, returning the inner reference path. This works
for simple projections where output elements directly correspond to input elements.
"""
function map_reference_forward(projection::Projection, iomap, reference)
    @reference_case reference begin
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
    @reference proj(projection, ^(reference))
end

"""
    projection_read(projection::Projection, iomap, operation)

Default implementation for projection operation reading. Handles
`ReplaceSelectionOperation` by mapping the selection path backward
from output space to input space using `map_reference_backward`.
Returns `nothing` for other operation types.
"""
function projection_read(projection::Projection, iomap, operation)
    if operation isa ReplaceSelectionOperation
        input_selection = map_reference_backward(projection, iomap, operation.path)
        input_selection === nothing && return nothing
        return ReplaceSelectionOperation(input_selection)
    else
        return nothing
    end
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
