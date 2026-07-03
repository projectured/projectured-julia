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
import ..ReactiveModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          ElementReference, is_element_reference, head, tail
import ..PrinterContextModule: PrinterContext, make_child_context
import ..CollectionModule: CellVector, ListNode
import ..IoMapApiModule: IoMap

export CopyingProjection, CopyingProjectionIoMap, make_copying_field_iomap, make_copying_element_iomap

struct CopyingProjection <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────

struct CopyingProjectionIoMap <: IoMap
    projection::CopyingProjection
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
    children = [print_child(recursion, input[i],
                    make_child_context(ctx, ElementReference(i)))
                for i in 1:length(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    output.selection = input.selection
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
                     make_child_context(ctx, ElementReference(index)))

    # Create output node
    out_node = ListNode(elem_iomap.output)

    # Lazy next
    set_function!(getfield(out_node, :next), () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        next_out = _map_node(p, next_input, recursion, ctx, index + 1)
        # Link back: prevent recreating current node on backward traversal
        set_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    set_function!(getfield(out_node, :prev), () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        prev_out = _map_node(p, prev_input, recursion, ctx, index - 1)
        # Link forward: prevent recreating current node on forward traversal
        set_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── Vector{Cell} and struct paths ─────────────────────────────────────────

function print_document(p::CopyingProjection, recursion, input::Vector{Cell}, ctx)
    children = [print_child(recursion, c[],
                    make_child_context(ctx, ElementReference(i)))
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
            push!(field_vals, Cell(() -> begin
                im = iomap_cell[]
                im === nothing && return nothing
                sel = hasproperty(input, :selection) ? input.selection : nothing
                sel === nothing && return nothing
                map_reference_forward(p, im, sel)
            end))
        elseif _is_doc_field(fv)
            child_ctx = make_child_context(ctx, FieldReference(string(nm)))
            im = print_child(recursion, _unwrap(fv), child_ctx)
            push!(children, im); push!(names, string(nm))
            push!(field_vals, im.output)
        else
            push!(field_vals, fv)
        end
    end
    output = T(field_vals...)
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
    # Skip canonical TypeReference checkpoints before dispatching on the head's
    # navigation step (index vs. field); the child mapper re-canonicalizes.
    reference = reference
    reference isa ConcreteReferencePath || return reference
    h = head(reference)
    rest = tail(reference)
    if h isa RangeReference && iomap.field_names === nothing
        if iomap.children isa Vector
            isempty(iomap.children) && return reference   # primitive — pass through
            j = h.start + 1
            (j < 1 || j > length(iomap.children)) && return nothing
            child_im = iomap.children[j]
            mapped = fn(child_im.projection, child_im, rest)
            mapped === nothing && return nothing
            # Copying preserves order, so the index step passes through unchanged
            # (mirrors the ListNode branch below).
            return ConcreteReferencePath(h, mapped)
        elseif iomap.children === nothing && iomap.recursion !== nothing
            # ListNode path: walk to the indexed node and project on demand
            is_element_reference(h) || return reference
            index = h.start + 1
            child_iomap = _get_listnode_child_iomap(iomap, index)
            child_iomap === nothing && return nothing
            mapped = fn(child_iomap.projection, child_iomap, rest)
            mapped === nothing && return nothing
            return ConcreteReferencePath(h, mapped)
        end
    elseif h isa FieldReference && iomap.field_names isa Vector
        name = h.name
        idx = findfirst(==(name), iomap.field_names)
        idx === nothing && return reference   # non-document field — identity
        child_im = iomap.children[idx]
        mapped = fn(child_im.projection, child_im, rest)
        mapped === nothing && return nothing
        return ConcreteReferencePath(FieldReference(name), mapped)
    end
    return reference
end

function _get_listnode_child_iomap(iomap::CopyingProjectionIoMap, index::Int)
    input_node = _walk_to_index(iomap.input::ListNode, index)
    input_node === nothing && return nothing
    return print_child(iomap.recursion, input_node.value,
               make_child_context(iomap.base_ctx, ElementReference(index)))
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
