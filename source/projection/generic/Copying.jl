# Fragment of `ProjectionAlgebraModule`.
#
# Domain-independent copying projection. For CellVector inputs it creates
# per-element iomaps eagerly. For ListNode inputs it maps lazily — only the
# head is projected immediately; `prev`/`next` are reactive thunks that
# project on demand. For struct Documents it creates per-field iomaps for
# every non-selection field. Primitives are identity. The iomap stores all
# child iomaps so that map_reference_backward can delegate through them
# (enabling e.g. SortingProjection to remap indices).
struct CopyingProjection <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────

# For a reactive CellVector input `children` and `output` are computed cells, so
# the IoMap keeps its identity while a structural edit reconciles children and
# re-derives output (PAR-STABLE-IOMAP-IDENTITY); the mappers read `iomap.children`
# as the value. The other input shapes pass eager values that @iomap wraps.
@iomap struct CopyingIoMap
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
    CopyingIoMap(p, input, output, children, nothing, nothing, nothing)
end

# ── ListNode path (lazy) ─────────────────────────────────────────────────

function print_document(p::CopyingProjection, recursion, input::ListNode, ctx)
    output_head = _map_node(p, input, recursion, ctx, 1)
    CopyingIoMap(p, input, output_head, nothing, nothing, recursion, ctx)
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
    CopyingIoMap(p, input, output, children, nothing, nothing, nothing)
end

function print_document(p::CopyingProjection, recursion, input, ctx)
    input isa Document || return CopyingIoMap(p, input, input, Any[], nothing, nothing, nothing)
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
    # `typeof` is the node's cell-kind struct (`RCFoo`), which carries no
    # constructor; the constructors live on the document's UnionAll wrapper
    # (`Foo`) and auto-wrap a plain value in a Cell.
    output = Base.typename(T).wrapper(field_vals...)
    iomap = CopyingIoMap(p, input, output, children, names, nothing, nothing)
    iomap_cell[] = iomap
    return iomap
end

# ── Child IoMap accessors ─────────────────────────────────────────────────
# A parent projection that lets CopyingProjection handle one of its document
# parts (e.g. JsonObjectToSyntaxNode routes the object's entries through a
# CopyingProjection) can reach the stored child IoMap to delegate its own
# reference mapping through it — the School-A pattern. These accessors keep
# that delegation from poking at CopyingIoMap's fields directly.

"""
    make_copying_field_iomap(iomap, name) -> child_iomap_or_nothing

The child IoMap for the struct field `name`, or `nothing` if `iomap` is not a
struct-shaped `CopyingIoMap` or has no projected field of that name.
"""
make_copying_field_iomap(::Any, ::AbstractString) = nothing
function make_copying_field_iomap(iomap::CopyingIoMap, name::AbstractString)
    iomap.field_names isa Vector || return nothing
    idx = findfirst(==(name), iomap.field_names)
    idx === nothing ? nothing : iomap.children[idx]
end

"""
    make_copying_element_iomap(iomap, i) -> child_iomap_or_nothing

The child IoMap for the 1-based element `i` of a vector-shaped
`CopyingIoMap`, or `nothing` when out of range / not vector-shaped.
"""
make_copying_element_iomap(::Any, ::Integer) = nothing
function make_copying_element_iomap(iomap::CopyingIoMap, i::Integer)
    iomap.children isa Vector || return nothing
    (1 <= i <= length(iomap.children)) ? iomap.children[i] : nothing
end

# ── Reference mapping helpers ─────────────────────────────────────────────

"""
The child io map that a navigation step names. Three answers, and both the
mappers and the reader need all three:

- an io map — the step names that child.
- `missing` — the step names no child of this node: a primitive, a field that
  holds no document, or a list step that is not an element step.
- `nothing` — the step names a child that does not exist.
"""
function _child_iomap(iomap::CopyingIoMap, h)
    if h isa RangeReferenceStep && iomap.field_names === nothing
        if iomap.children isa Vector
            isempty(iomap.children) && return missing   # primitive
            j = h.start + 1
            return (1 <= j <= length(iomap.children)) ? iomap.children[j] : nothing
        elseif iomap.children === nothing && iomap.recursion !== nothing
            # ListNode: walk to the indexed node and project on demand.
            is_element_reference_step(h) || return missing
            return _get_listnode_child_iomap(iomap, h.start + 1)
        end
    elseif h isa FieldReferenceStep && iomap.field_names isa Vector
        idx = findfirst(==(h.name), iomap.field_names)
        return idx === nothing ? missing : iomap.children[idx]   # non-document field
    end
    missing
end

function _map_ref(fn, iomap::CopyingIoMap, reference)
    # Skip canonical TypeReferenceStep checkpoints before dispatching on the head's
    # navigation step (index vs. field); the child mapper re-canonicalizes.
    reference isa ConcreteReference || return reference
    h = get_reference_head(reference)
    child_im = _child_iomap(iomap, h)
    child_im === missing && return reference   # names no child — identity
    child_im === nothing && return nothing     # names a child that is not there
    mapped = fn(child_im.projection, child_im, get_reference_tail(reference))
    mapped === nothing && return nothing
    # Copying preserves order and field names, so the step itself passes through.
    # A field step is rebuilt from its name: the child mapper re-canonicalizes the
    # type checkpoint below it.
    ConcreteReference(h isa FieldReferenceStep ? FieldReferenceStep(h.name) : h, mapped)
end

function _get_listnode_child_iomap(iomap::CopyingIoMap, index::Int)
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

function map_reference_backward(::CopyingProjection, iomap::CopyingIoMap, reference)
    _map_ref(map_reference_backward, iomap, reference)
end

function map_reference_forward(::CopyingProjection, iomap::CopyingIoMap, reference)
    _map_ref(map_reference_forward, iomap, reference)
end

# ── read_intent ───────────────────────────────────────────────────────────────
#
# A copied node is a container, and a container reader routes: it offers the
# payload to the child the payload belongs to before it answers anything itself.
# `LayoutToGraphics` routes the same way — by coordinate for a pointer event, by
# the `selection` for a key.
#
# The route is what a mapper can not replace. `map_reference_backward` moves a
# reference; it can not change what an operation IS, and a child may have to:
# `ObjectFieldToWidget` turns a character range in its control into a write on the
# object its field names. That conversion happens only if the operation reaches
# that child's reader. Without the route a form of copied nodes types into the
# rendering and never into the document behind it.
function read_intent(p::CopyingProjection, iomap::CopyingIoMap, payload)
    routed = _route_to_child(iomap, payload)
    if routed !== nothing
        (child_im, inner) = routed
        answer = read_intent(child_im.projection, child_im, inner)
        (answer !== nothing && _needs_no_prefix(answer)) && return answer
    end
    invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, payload)
end

# The child a payload belongs to, and the payload as that child sees it.
#
# An operation that says WHERE it acts is routed there, and this node's own step
# comes off its reference. Every other payload — a key, an operation that names
# its own subject — is routed to the child the `selection` points at and reaches
# it unchanged.
function _route_to_child(iomap::CopyingIoMap, payload)
    reference = operation_reference(payload)
    if reference isa ConcreteReference
        child_im = _child_iomap(iomap, get_reference_head(reference))
        _is_child(child_im) || return nothing
        return (child_im, retarget_operation(payload, get_reference_tail(reference)))
    end
    step = _selection_step(iomap)
    step === nothing && return nothing
    child_im = _child_iomap(iomap, step)
    _is_child(child_im) ? (child_im, payload) : nothing
end

_is_child(child_im) = !(child_im === missing || child_im === nothing)

# The step of this node's own selection that names a child.
function _selection_step(iomap::CopyingIoMap)
    input = _unwrap(iomap.input)
    input isa Document || return nothing
    selection = get_stored_selection(input)
    selection isa ConcreteReference ? get_reference_head(selection) : nothing
end

# An answer this node must not prefix, because it carries its own root or it
# travels. Both conditions are the kernel default reader's own: a
# `ReplaceReferencedValueOperation` that names its document is forwarded
# unchanged there, and so is an operation that reports no reference and declares
# that it travels. An answer that still names a place is in the child's own
# domain and needs this node's step in front of it, which is what the generic
# bridge builds through `map_reference_backward`.
_needs_no_prefix(op) =
    op isa ReplaceReferencedValueOperation ? op.document !== nothing :
    operation_travels_unchanged(op)
