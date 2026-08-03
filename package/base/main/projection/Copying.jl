"""
    CopyingProjectionModule

Domain-independent copying projection. For CellVector inputs it creates
per-element iomaps eagerly. For ListNode inputs it maps lazily — only the
head is projected immediately; `prev`/`next` are reactive thunks that
project on demand. For struct Documents it creates per-field iomaps for
every non-selection field. Primitives are identity. The iomap stores all
child iomaps so that map_reference_backward can delegate through them
(enabling e.g. SortingProjection to remap indices).
"""
module CopyingProjectionModule

import ..ProjectionApiModule: print_document, print_child, map_reference_forward, map_reference_backward, Projection
import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..DocumentModule: Document
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          ElementReferenceStep, is_element_reference_step, head, tail
import ..PrinterContextModule: PrinterContext, make_child_context
import ..CollectionModule: CellVector, ComputedCellVector, ListNode
import ..IoMapModule: IoMap, var"@iomap", reconcile_child_iomaps

export CopyingProjection, CopyingProjectionIoMap, make_copying_field_iomap, make_copying_element_iomap

struct CopyingProjection <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────

# For a reactive CellVector input `children` and `output` are computed cells, so
# the IoMap keeps its identity while a structural edit reconciles children and
# re-derives output (AR-STABLE-IOMAP-IDENTITY); the mappers read `iomap.children`
# as the value. The other input shapes pass eager values that @iomap wraps.
@iomap struct CopyingProjectionIoMap
    projection::Any
    input::Any
    output::Any
    children::Any        # Vector of child iomaps (CellVector/struct) or nothing (ListNode)
    field_names::Any     # Vector{String} for struct; nothing otherwise
    recursion::Any       # stored for lazy ListNode reference mapping
    base_ctx::Any        # stored PrinterContext for lazy ListNode reference mapping
end

# ── Helpers ───────────────────────────────────────────────────────────────

_is_doc_field(x) = x isa Document
_is_doc_field(c::Cell) = c[] isa Document
_unwrap(x) = x
_unwrap(c::Cell) = c[]

# ── print_document ──────────────────────────────────────────────────────

function print_document(p::CopyingProjection, recursion, input::CellVector, ctx)
    children = reconcile_child_iomaps(
        () -> input,
        (i, x) -> print_child(recursion, x,
            make_child_context(ctx, ElementReferenceStep(i))))
    output = ComputedCellVector(() -> [im.output for im in children[]])
    set_cell_function!(getfield(output, :selection), () -> input.selection)
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

# ── ListNode path (lazy) ─────────────────────────────────────────────────

function print_document(p::CopyingProjection, recursion, input::ListNode, ctx)
    output_head = _map_node(p, input, recursion, ctx, 1)
    CopyingProjectionIoMap(p, input, output_head, nothing, nothing, recursion, ctx)
end

function _map_node(p::CopyingProjection, input_node::ListNode, recursion, ctx, index::Int)
    # Project current element
    elem_iomap = print_child(recursion, input_node.value,
                     make_child_context(ctx, ElementReferenceStep(index)))

    # Create output node
    out_node = ListNode(elem_iomap.output)

    # Lazy next
    set_cell_function!(getfield(out_node, :next), () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        next_out = _map_node(p, next_input, recursion, ctx, index + 1)
        # Link back: prevent recreating current node on backward traversal
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    set_cell_function!(getfield(out_node, :prev), () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        prev_out = _map_node(p, prev_input, recursion, ctx, index - 1)
        # Link forward: prevent recreating current node on forward traversal
        set_cell_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── Vector{Cell} and struct paths ─────────────────────────────────────────

function print_document(p::CopyingProjection, recursion, input::Vector{Cell}, ctx)
    children = [print_child(recursion, c[],
                    make_child_context(ctx, ElementReferenceStep(i)))
                for (i, c) in enumerate(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

function print_document(p::CopyingProjection, recursion, input, ctx)
    input isa Document || return CopyingProjectionIoMap(p, input, input, Any[], nothing, nothing, nothing)
    T = typeof(input)
    all_names = fieldnames(T)
    children = Any[]
    names = String[]
    field_vals = Any[]
    iomap_cell = Cell(nothing)   # filled in after construction
    for nm in all_names
        fv = getfield(input, nm)
        if nm == :selection
            push!(field_vals, ComputedCell(() -> begin
                im = iomap_cell[]
                im === nothing && return nothing
                sel = hasproperty(input, :selection) ? input.selection : nothing
                sel === nothing && return nothing
                map_reference_forward(p, im, sel)
            end))
        elseif _is_doc_field(fv)
            child_ctx = make_child_context(ctx, FieldReferenceStep(string(nm)))
            im = print_child(recursion, _unwrap(fv), child_ctx)
            push!(children, im); push!(names, string(nm))
            push!(field_vals, im.output)
        else
            push!(field_vals, fv)
        end
    end
    # `typeof` is the node's cell-kind struct (`RFoo`), which carries no
    # constructor; the constructors live on the document's UnionAll wrapper
    # (`Foo`) and auto-wrap a plain value in a Cell.
    output = Base.typename(T).wrapper(field_vals...)
    iomap = CopyingProjectionIoMap(p, input, output, children, names, nothing, nothing)
    iomap_cell[] = iomap
    return iomap
end

# ── Child IoMap accessors ─────────────────────────────────────────────────
# A parent projection that lets CopyingProjection handle one of its document
# parts (e.g. JsonObjectToSyntaxNode routes the object's entries through a
# CopyingProjection) can reach the stored child IoMap to delegate its own
# reference mapping through it — the School-A pattern. These accessors keep
# that delegation from poking at CopyingProjectionIoMap's fields directly.

"""
    make_copying_field_iomap(iomap, name) -> child_iomap_or_nothing

The child IoMap for the struct field `name`, or `nothing` if `iomap` is not a
struct-shaped `CopyingProjectionIoMap` or has no projected field of that name.
"""
make_copying_field_iomap(::Any, ::AbstractString) = nothing
function make_copying_field_iomap(iomap::CopyingProjectionIoMap, name::AbstractString)
    iomap.field_names isa Vector || return nothing
    idx = findfirst(==(name), iomap.field_names)
    idx === nothing ? nothing : iomap.children[idx]
end

"""
    make_copying_element_iomap(iomap, i) -> child_iomap_or_nothing

The child IoMap for the 1-based element `i` of a vector-shaped
`CopyingProjectionIoMap`, or `nothing` when out of range / not vector-shaped.
"""
make_copying_element_iomap(::Any, ::Integer) = nothing
function make_copying_element_iomap(iomap::CopyingProjectionIoMap, i::Integer)
    iomap.children isa Vector || return nothing
    (1 <= i <= length(iomap.children)) ? iomap.children[i] : nothing
end

# ── Reference mapping helpers ─────────────────────────────────────────────

function _map_ref(fn, iomap::CopyingProjectionIoMap, reference)
    # Skip canonical TypeReferenceStep checkpoints before dispatching on the head's
    # navigation step (index vs. field); the child mapper re-canonicalizes.
    reference = reference
    reference isa ConcreteReference || return reference
    h = head(reference)
    rest = tail(reference)
    if h isa RangeReferenceStep && iomap.field_names === nothing
        if iomap.children isa Vector
            isempty(iomap.children) && return reference   # primitive — pass through
            j = h.start + 1
            (j < 1 || j > length(iomap.children)) && return nothing
            child_im = iomap.children[j]
            mapped = fn(child_im.projection, child_im, rest)
            mapped === nothing && return nothing
            # Copying preserves order, so the index step passes through unchanged
            # (mirrors the ListNode branch below).
            return ConcreteReference(h, mapped)
        elseif iomap.children === nothing && iomap.recursion !== nothing
            # ListNode path: walk to the indexed node and project on demand
            is_element_reference_step(h) || return reference
            index = h.start + 1
            child_iomap = _get_listnode_child_iomap(iomap, index)
            child_iomap === nothing && return nothing
            mapped = fn(child_iomap.projection, child_iomap, rest)
            mapped === nothing && return nothing
            return ConcreteReference(h, mapped)
        end
    elseif h isa FieldReferenceStep && iomap.field_names isa Vector
        name = h.name
        idx = findfirst(==(name), iomap.field_names)
        idx === nothing && return reference   # non-document field — identity
        child_im = iomap.children[idx]
        mapped = fn(child_im.projection, child_im, rest)
        mapped === nothing && return nothing
        return ConcreteReference(FieldReferenceStep(name), mapped)
    end
    return reference
end

function _get_listnode_child_iomap(iomap::CopyingProjectionIoMap, index::Int)
    input_node = _walk_to_index(iomap.input::ListNode, index)
    input_node === nothing && return nothing
    return print_child(iomap.recursion, input_node.value,
               make_child_context(iomap.base_ctx, ElementReferenceStep(index)))
end

function _walk_to_index(head_node::ListNode, index::Int)
    if index >= 1
        node = head_node
        for _ in 1:(index - 1)
            node.next === nothing && return nothing
            node = node.next
        end
        return node
    else
        node = head_node
        for _ in 1:(1 - index)
            node.prev === nothing && return nothing
            node = node.prev
        end
        return node
    end
end

function map_reference_backward(::CopyingProjection, iomap::CopyingProjectionIoMap, reference)
    _map_ref(map_reference_backward, iomap, reference)
end

function map_reference_forward(::CopyingProjection, iomap::CopyingProjectionIoMap, reference)
    _map_ref(map_reference_forward, iomap, reference)
end

# CopyingProjection is domain-independent: it has no `read_intent` method of
# its own. The generic reader bridge (ProjectionModule) routes selection and
# edit operations back through `map_reference_backward`, which delegates into the
# stored child iomaps. Screen/window event routing lives in `ScreenToScreen`, the
# screen-domain projection — not here.

end # module
