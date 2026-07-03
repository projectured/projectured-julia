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

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection,
       pure_print_document, pure_print_child
import ..IntentModule: Intent
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation,
                          ReplaceReferencedValueOperation, CompoundOperation, SelectNextInsertionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..CellModule: Cell, AbstractCell
import ..DocumentModule: snapshot
import ..ReferenceModule: EmptyReferencePath
import ..PrinterContextModule: PrinterContext
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..KeyboardModule: KeyPress, KeyDown
import ..MouseModule: MousePress
import ..DocumentApiModule: Document, document_read

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
_pure_snapshot(x) = x isa Document ? snapshot(x) : x
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
    # stay in sync with `OperationRerootingModule.prepend_steps_to_op`. A new
    # path-bearing operation missing from either is silently passed through with
    # its reference left in the wrong domain. See documentation/operations.md.
    if operation isa Union{KeyPress, KeyDown, MousePress}
        # Generic event fallback: a leaf projection with no authoring reader of
        # its own delegates a raw input gesture to the projection-independent
        # `document_read` of its input document. This generalizes the per-projection
        # delegation `SyntaxToText`/`TextToGraphics` already do by hand, so any
        # `@gestures`-declared domain is reachable through any projection with no
        # bespoke reader. (Higher-order projections route events through their own
        # 4-arg readers and never reach this leaf default.)
        input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
        return input isa Document ? document_read(input, operation) : nothing
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
    elseif operation isa ReplaceStringRangeOperation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return ReplaceStringRangeOperation(input_ref, operation.replacement)
    elseif operation isa ReplaceNumberRangeOperation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return ReplaceNumberRangeOperation(input_ref, operation.replacement)
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

Generic bridge from the symmetric 4-arg `Intent` interface to the legacy 3-arg
reader. For any projection without its own 4-arg method, unwrap the `Intent` and
dispatch the legacy `read_intent(p, iomap, payload)` on the operation (when one
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
"""
macro projection(structdef)
    structdef.head === :struct || error("@projection expects a struct definition")
    # Default the supertype to `Projection` unless one is written explicitly, so
    # `@projection struct Foo … end` means `struct Foo <: Projection … end`. An
    # explicit supertype always wins. The injected `:Projection` resolves in the
    # caller's scope (the result is `esc`'d) — same mechanic as `@iomap`/`IoMap`.
    name_expr = structdef.args[2]
    if name_expr isa Expr && name_expr.head === :(<:)
        struct_name = name_expr.args[1]
    else
        struct_name = name_expr
        structdef.args[2] = Expr(:(<:), name_expr, :Projection)
    end
    body = structdef.args[3]
    cell_fields = Symbol[]
    defaults = Pair{Symbol, Any}[]   # field => default-value expr (declaration order)
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            ex.args[2] = :Cell
        elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2
            # `name = v` / `name::T = v` — @kwdef-style default. Strip the default
            # out of the (plain) struct body and remember it for the keyword ctor.
            lhs = ex.args[1]
            fname = lhs isa Symbol ? lhs : lhs.args[1]
            push!(cell_fields, fname)
            push!(defaults, fname => ex.args[2])
            body.args[i] = :($(fname)::Cell)
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

    # Keyword constructor (only when ≥1 default is declared) that forwards into
    # the positional inner ctor above, so Cell auto-wrapping is unchanged. Fields
    # without a default become required keywords, à la `Base.@kwdef`.
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        kw_params = map(all_fields) do (fname, _)
            haskey(default_map, fname) ? Expr(:kw, fname, default_map[fname]) : fname
        end
        kwctor = :(function $(struct_name)(; $(kw_params...))
            $(Expr(:call, struct_name, (f[1] for f in all_fields)...))
        end)
        push!(extra, kwctor)
    end

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop, extra...))
end

end # module
