# Fragment of `ReflectionModule`.
#
# A `ReflectedNode` tree rendered as a [`WidgetTree`](@ref), where clicking a
# chevron drives the **bounded sync** rather than merely hiding a row.
#
# The laziness lives in the sync (see `ReflectionModule`), so this
# projection has none of its own: it prints whatever the shadow holds, which is
# small because the shadow was grown to a bound. A node whose `children` slot holds
# an `UnsyncedDocument` is a node nobody has opened yet; expanding it sets that
# marker's `requested` flag, and the *next* sync fills it in one level deeper.
#
# # Why a tree and not `ObjectToWidget`
#
# `ObjectToWidget`'s advantage was that it already knew how to reflect an object.
# `DocumentReflection` now does that ahead of any widget, so both would be
# rendering the same node tree and only density is left to choose on — one compact
# row per node against one card per node. For something meant to be drilled into,
# that is not close. `ObjectToWidget` also offers editing, which is the wrong
# affordance for a running engine's internals.
#
# # The round trip
#
# `WidgetTree` keeps its open nodes as `expanded`, a set of index paths, and its
# chevron emits a `ReplaceReferencedValueOperation` writing a new set, marked as
# view state by `ReplaceViewStateOperation`. That state is *derived* here, not
# owned: the printer collects the path of every node whose children show, and the
# reader diffs the incoming set against it to find the paths that toggled and
# RETURNS a `SetReflectedDisclosureOperation` naming them, in the same mark;
# evaluating that is what writes the shadow. The widget's own copy is never
# written to — the shadow is the only place expansion is recorded.
#
# The walk of the shadow runs in a cell, so the sync that fills an opened node
# prints the tree again. A walk done once, when `print_document` runs, would keep
# the tree of the first frame.
"""
    ReflectionToWidget(; show_kind = true)

Projects a `ReflectedNode` tree to a `WidgetTree`. `show_kind` appends each
node's type name to its label.
"""
struct ReflectionToWidget <: Projection
    show_kind::Bool
end
ReflectionToWidget(; show_kind::Bool = true) = ReflectionToWidget(show_kind)

# `tree` is a cell of the walk: `root`, the root row; `nodes`, tree path → the
# ReflectedNode it came from; and `expanded`, the paths of the nodes whose
# children show.
@iomap struct ReflectionToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    tree::Any
end

# ── print_document ────────────────────────────────────────────────────────────

function print_document(p::ReflectionToWidget, recursion, node, ctx)
    tree = Cell(@computation begin
        nodes = Dict{Vector{Int}, Any}()
        expanded = Set{Vector{Int}}()
        root = _tree_node(p, node, Int[1], nodes, expanded)
        (root = root, nodes = nodes, expanded = expanded)
    end)
    # Positional, so every declared field is named here in order: position,
    # roots, visible, margin, border, padding, style, expanded, gestures,
    # scroll_position, vertical_scroll_bar, horizontal_scroll_bar, tooltip.
    output = WidgetTree(Cell(Point2D(0, 0)), CellVector(@computation Any[tree[].root]),
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(@computation tree[].expanded),
                        Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                        Cell(nothing))
    iomap = ReflectionToWidgetIoMap(p, node, output, tree)
    # A row lights while the pointer is on it. A row is no part of the reflected
    # node, so the node holds it as a part of this view, and the tree holds its
    # forward image.
    set_cell_computation!(getfield(output, :mouse_target),
        () -> map_mouse_target_forward(node, path -> map_reference_forward(p, iomap, path)))
    iomap
end

print_document(p::ReflectionToWidget, node) = print_document(p, nothing, node, nothing)

function _tree_node(p::ReflectionToWidget, node, path::Vector{Int}, nodes, expanded)
    nodes[copy(path)] = node
    kids = node.children

    if kids isa AUnsyncedDocument
        # A chevron is drawn only for a node that has children, so a closed
        # node needs one to stand on. It is never rendered — the path is not in
        # `expanded` — so its only job is to say how much is behind the chevron.
        return WidgetTreeNode(_icon(node), _label(p, node),
                              Any[WidgetTreeNode("", _hidden_summary(kids))])
    end

    kids === nothing && return WidgetTreeNode(_icon(node), _label(p, node))

    children = Any[]
    for i in 1:length(kids)
        child = kids[i]
        push!(path, i)
        push!(children, child isa AUnsyncedDocument ?
                        WidgetTreeNode("", _hidden_summary(child)) :
                        _tree_node(p, child, path, nodes, expanded))
        pop!(path)
    end
    isempty(children) || push!(expanded, copy(path))
    WidgetTreeNode(_icon(node), _label(p, node), children)
end

# No icon: the tree already draws a chevron for every node that has children, so
# a per-node glyph beside it is redundant — and the monospace UI font has no
# glyph for the obvious decorative characters anyway, which renders as tofu.
_icon(node) = ""

function _label(p::ReflectionToWidget, node)
    name = _text(node.label)
    value = node.value
    kind = p.show_kind ? _text(node.kind) : ""
    if value !== nothing
        v = _text(value)
        isempty(name) ? v : string(name, " = ", v)
    elseif isempty(kind)
        name
    else
        isempty(name) ? kind : string(name, ": ", kind)
    end
end

# A tail or collapsed marker, as the one line standing for what is not shown.
function _hidden_summary(marker)
    n = marker.size
    n < 0 ? "..." : string(n, n == 1 ? " item" : " items", " not loaded")
end

_text(x) = x === nothing ? "" : (x isa AbstractString ? String(x) : string(x))

# ── read_intent ───────────────────────────────────────────────────────────────

# The chevron writes a whole new `expanded` set. Exactly one path differs from
# what the printer derived, and that path names the node the user acted on.
function read_intent(p::ReflectionToWidget, iomap::ReflectionToWidgetIoMap,
                     op::ReplaceReferencedValueOperation)
    (op.document === iomap.output && _field_name(op) == "expanded") || return op
    next = op.value
    next isa AbstractSet || return op

    # PAR-READER-IS-PURE: collect what changed and RETURN the edit; the shadow is
    # written by evaluating SetReflectedDisclosureOperation, never here. The
    # widget's own `expanded` is still never written — the returned operation
    # targets the shadow, so expansion stays recorded there.
    tree = iomap.tree
    changes = Pair{Any,Bool}[]
    for path in symdiff(next, tree.expanded)
        node = get(tree.nodes, path, nothing)
        node === nothing && continue
        push!(changes, node => (path in next))
    end
    isempty(changes) ? nothing : SetReflectedDisclosureOperation(changes)
end

# The tree marks a fold as view state. The disclosure that it becomes keeps the
# mark, so a history does not record it either.
function read_intent(p::ReflectionToWidget, iomap::ReflectionToWidgetIoMap,
                     op::ReplaceViewStateOperation)
    inner = get_wrapped_operation(op)
    inner isa ReplaceReferencedValueOperation || return op
    disclosure = read_intent(p, iomap, inner)
    disclosure === inner ? op :
    disclosure === nothing ? nothing : rewrap_operation(op, disclosure)
end

# A row click selects; there is no reflected-domain cursor to move it to.
read_intent(::ReflectionToWidget, ::ReflectionToWidgetIoMap, ::ReplacePathOperation) = nothing

# The part under the pointer is a row, which goes back as a part of this view.
function read_intent(p::ReflectionToWidget, iomap::ReflectionToWidgetIoMap,
                     op::ReplaceMouseTargetOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : ReplaceMouseTargetOperation(path)
end

# A move answers the leave of a part and the part under the pointer together; each
# goes back as this view reads it alone.
function read_intent(p::ReflectionToWidget, iomap::ReflectionToWidgetIoMap, op::CompoundOperation)
    has_mouse_target(op) || return op
    join_move_answers((read_intent(p, iomap, member) for member in op.operations)...)
end

read_intent(::ReflectionToWidget, ::ReflectionToWidgetIoMap, op) = op

# The operation carries a `Reference`; the writes we care about are the
# single-field form `tree.expanded`.
function _field_name(op::ReplaceReferencedValueOperation)
    r = op.reference
    r isa ConcreteReference || return ""
    h = r.head
    h isa FieldReferenceStep ? String(h.name) : ""
end
