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

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          FieldReference, PositionReference, RangeReference,
                          ElementReference, append_reference, is_element_reference, head, tail
import ..ReferenceBuilderModule: var"@reference"
import ..CollectionModule: CellVector, ListNode
import ..IoMapApiModule: IoMap

export CopyingProjection, CopyingProjectionIoMap

struct CopyingProjection <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────

struct CopyingProjectionIoMap <: IoMap
    projection::CopyingProjection
    input::Any
    output::Any
    children::Any        # Vector of child iomaps (CellVector/struct) or nothing (ListNode)
    field_names::Any     # Vector{String} for struct; nothing otherwise
    recursion::Any       # stored for lazy ListNode reference mapping
    base_reference::Any  # stored for lazy ListNode reference mapping
end

# ── Helpers ───────────────────────────────────────────────────────────────

_is_doc_field(x) = x isa Document
_is_doc_field(c::Cell) = c[] isa Document
_unwrap(x) = x
_unwrap(c::Cell) = c[]

# ── projection_print ──────────────────────────────────────────────────────

function projection_print(p::CopyingProjection, input::CellVector, recursion, reference)
    children = [projection_print(recursion, input[i], recursion,
                    @reference ^(reference){i})
                for i in 1:length(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    output.selection = input.selection
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

# ── ListNode path (lazy) ─────────────────────────────────────────────────

function projection_print(p::CopyingProjection, input::ListNode, recursion, reference)
    output_head = _map_node(p, input, recursion, reference, 1)
    CopyingProjectionIoMap(p, input, output_head, nothing, nothing, recursion, reference)
end

function _map_node(p::CopyingProjection, input_node::ListNode, recursion, reference, index::Int)
    # Project current element
    elem_iomap = projection_print(recursion, input_node.value, recursion,
                     @reference ^(reference)[index])

    # Create output node
    out_node = ListNode(elem_iomap.output)

    # Lazy next
    setfn!(getfield(out_node, :next), () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        next_out = _map_node(p, next_input, recursion, reference, index + 1)
        # Link back: prevent recreating current node on backward traversal
        setval!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    setfn!(getfield(out_node, :prev), () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        prev_out = _map_node(p, prev_input, recursion, reference, index - 1)
        # Link forward: prevent recreating current node on forward traversal
        setval!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── Vector{Cell} and struct paths ─────────────────────────────────────────

function projection_print(p::CopyingProjection, input::Vector{Cell}, recursion, reference)
    children = [projection_print(recursion, c[], recursion,
                    @reference ^(reference){i})
                for (i, c) in enumerate(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

function projection_print(p::CopyingProjection, input, recursion, reference)
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
            child_ref = @reference ^(reference).field(string(nm))
            im = projection_print(recursion, _unwrap(fv), recursion, child_ref)
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

# ── Reference mapping helpers ─────────────────────────────────────────────

function _map_ref(fn, iomap::CopyingProjectionIoMap, reference)
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
            return ConcreteReferencePath(PositionReference(j), mapped)
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
    return projection_print(iomap.recursion, input_node.value, iomap.recursion,
               @reference ^(iomap.base_reference)[index])
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

end # module
