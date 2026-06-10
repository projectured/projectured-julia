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
import ..PrinterContextModule: PrinterContext, child_context, with_available_size
import ..CollectionModule: CellVector, ListNode
import ..IoMapApiModule: IoMap
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope
import ..ReferenceDispatchingModule: ReferenceDispatchingIoMap

export CopyingProjection, CopyingProjectionIoMap, copying_field_iomap, copying_element_iomap

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

# ── projection_print ──────────────────────────────────────────────────────

function projection_print(p::CopyingProjection, recursion, input::CellVector, ctx)
    children = [projection_print(recursion, recursion, input[i],
                    child_context(ctx, PositionReference(i)))
                for i in 1:length(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    output.selection = input.selection
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

# ── ListNode path (lazy) ─────────────────────────────────────────────────

function projection_print(p::CopyingProjection, recursion, input::ListNode, ctx)
    output_head = _map_node(p, input, recursion, ctx, 1)
    CopyingProjectionIoMap(p, input, output_head, nothing, nothing, recursion, ctx)
end

function _map_node(p::CopyingProjection, input_node::ListNode, recursion, ctx, index::Int)
    # Project current element
    elem_iomap = projection_print(recursion, recursion, input_node.value,
                     child_context(ctx, ElementReference(index)))

    # Create output node
    out_node = ListNode(elem_iomap.output)

    # Lazy next
    setfn!(getfield(out_node, :next), () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        next_out = _map_node(p, next_input, recursion, ctx, index + 1)
        # Link back: prevent recreating current node on backward traversal
        setval!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    setfn!(getfield(out_node, :prev), () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        prev_out = _map_node(p, prev_input, recursion, ctx, index - 1)
        # Link forward: prevent recreating current node on forward traversal
        setval!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── Vector{Cell} and struct paths ─────────────────────────────────────────

function projection_print(p::CopyingProjection, recursion, input::Vector{Cell}, ctx)
    children = [projection_print(recursion, recursion, c[],
                    child_context(ctx, PositionReference(i)))
                for (i, c) in enumerate(input)]
    out_cells = Cell[Cell(im.output) for im in children]
    output = CellVector(out_cells)
    CopyingProjectionIoMap(p, input, output, children, nothing, nothing, nothing)
end

function projection_print(p::CopyingProjection, recursion, input, ctx)
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
            child_ctx = child_context(ctx, FieldReference(string(nm)))
            # A WindowDocument is a natural source of layout extent: its
            # `width`/`height` fields are the window's pixel size. Seed
            # them on the context when descending into `content` so any
            # layout-aware descendant (split/tabbed/scroll panes) can
            # size itself to the window without needing a WidgetShell.
            if input isa WindowDocument && nm == :content
                w_cell = getfield(input, :width)
                h_cell = getfield(input, :height)
                child_ctx = with_available_size(child_ctx;
                                                width=w_cell, height=h_cell)
            end
            im = projection_print(recursion, recursion, _unwrap(fv), child_ctx)
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
    copying_field_iomap(iomap, name) -> child_iomap_or_nothing

The child IoMap for the struct field `name`, or `nothing` if `iomap` is not a
struct-shaped `CopyingProjectionIoMap` or has no projected field of that name.
"""
copying_field_iomap(::Any, ::AbstractString) = nothing
function copying_field_iomap(iomap::CopyingProjectionIoMap, name::AbstractString)
    iomap.field_names isa Vector || return nothing
    idx = findfirst(==(name), iomap.field_names)
    idx === nothing ? nothing : iomap.children[idx]
end

"""
    copying_element_iomap(iomap, i) -> child_iomap_or_nothing

The child IoMap for the 1-based element `i` of a vector-shaped
`CopyingProjectionIoMap`, or `nothing` when out of range / not vector-shaped.
"""
copying_element_iomap(::Any, ::Integer) = nothing
function copying_element_iomap(iomap::CopyingProjectionIoMap, i::Integer)
    iomap.children isa Vector || return nothing
    (1 <= i <= length(iomap.children)) ? iomap.children[i] : nothing
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
    return projection_print(iomap.recursion, iomap.recursion, input_node.value,
               child_context(iomap.base_ctx, ElementReference(index)))
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

# ── Event envelope routing ────────────────────────────────────────────────
# When a ScreenDocument is being copied, the projection output is itself
# a ScreenDocument with per-window content already projected through the
# inner recursion. Events from the backend arrive tagged with the
# originating window id; route each envelope to the matching
# WindowDocument.content's sub-iomap so the inner projection's reader
# sees the bare event. Operations the inner reader produces have paths
# rooted at the inner content document; we prepend the steps that lead
# from the ScreenDocument root down to that content so
# `evaluate_operation` can walk them against the editor's root.

function projection_read(p::CopyingProjection, iomap::CopyingProjectionIoMap, env::EventEnvelope)
    input = iomap.input
    if input isa ScreenDocument
        # Find the windows-field child iomap (CellVector path).
        windows_iomap = _struct_field_iomap(iomap, "windows")
        windows_iomap === nothing && return nothing
        windows_iomap.children isa Vector || return nothing
        for (i, raw_child) in enumerate(windows_iomap.children)
            child_input = raw_child.input
            child_input isa WindowDocument || continue
            child_input.id === env.window_id || continue
            op = projection_read(raw_child.projection, raw_child, env)
            return _prefix_op_with_steps(op,
                (FieldReference("windows"), ElementReference(i)))
        end
        return nothing
    elseif input isa WindowDocument
        # We're inside the matching window: descend into the content field
        # and hand the bare event to its reader.
        content_iomap = _struct_field_iomap(iomap, "content")
        content_iomap === nothing && return nothing
        op = projection_read(content_iomap.projection, content_iomap, env.event)
        return _prefix_op_with_steps(op, (FieldReference("content"),))
    else
        return nothing
    end
end

# Field-keyed lookup of a struct child iomap. Strips transparent wrappers
# (e.g. ReferenceDispatchingIoMap) so the returned iomap is the actual
# CopyingProjectionIoMap whose `.children` we want to walk further.
function _struct_field_iomap(iomap::CopyingProjectionIoMap, name::AbstractString)
    iomap.field_names isa Vector || return nothing
    idx = findfirst(==(name), iomap.field_names)
    idx === nothing && return nothing
    return _unwrap_to_copying(iomap.children[idx])
end

_unwrap_to_copying(im) = im
_unwrap_to_copying(im::ReferenceDispatchingIoMap) = _unwrap_to_copying(im.inner_iomap)

# Prepend `steps` to the reference path inside `op` (if the op carries one).
# Operations that target a captured Julia value directly (e.g. workbench
# tool ops that hold their target document) need no prefixing and are
# returned unchanged. `nothing` passes through unchanged.
function _prefix_op_with_steps(op, steps::Tuple)
    op === nothing && return nothing
    if op isa StringReplaceRangeOperation
        return StringReplaceRangeOperation(_prepend_path(steps, op.reference), op.replacement)
    elseif op isa NumberReplaceRangeOperation
        return NumberReplaceRangeOperation(_prepend_path(steps, op.reference), op.replacement)
    elseif op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(_prepend_path(steps, op.path))
    else
        return op
    end
end

function _prepend_path(steps::Tuple, path::ReferencePath)
    result = path
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

end # module
