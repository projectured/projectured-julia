"""
    ReflectionToWidgetModule

A `ReflectedNode` tree rendered as a [`WidgetTree`](@ref), where clicking a
chevron drives the **bounded sync** rather than merely hiding a row.

The laziness lives in the sync (see `DocumentReflectionModule`), so this
projection has none of its own: it prints whatever the shadow holds, which is
small because the shadow was grown to a bound. A node whose `children` slot holds
an `UnsyncedDocument` is a node nobody has opened yet; expanding it sets that
marker's `requested` flag, and the *next* sync fills it in one level deeper.

# Why a tree and not `ObjectToWidget`

`ObjectToWidget`'s advantage was that it already knew how to reflect an object.
`DocumentReflection` now does that ahead of any widget, so both would be
rendering the same node tree and only density is left to choose on — one compact
row per node against one card per node. For something meant to be drilled into,
that is not close. `ObjectToWidget` also offers editing, which is the wrong
affordance for a running engine's internals.

# The round trip

`WidgetTree` keeps its expansion state as `collapsed`, a set of index paths, and
its chevron emits a `ReplaceReferencedValueOperation` writing a new set. That
state is *derived* here, not owned: the printer collects the path of every node
standing on a marker, and the reader diffs the incoming set against it to find
the paths that toggled and RETURNS a `SetReflectedDisclosureOperation` naming
them; evaluating that is what writes the shadow. The widget's own copy is never
written to — the shadow is the only place expansion is recorded.
"""
module ReflectionToWidgetModule

import ..ProjectionApiModule: print_document, read_intent, Projection
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, ComputedCell
import ..WidgetModule: WidgetTree, WidgetTreeNode, Point2D
import ..OperationModule: ReplaceReferencedValueOperation, ReplaceSelectionOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep
import ..DocumentReflectionModule: AReflectedNode, SetReflectedDisclosureOperation
import ..BoundedSyncModule: AUnsyncedDocument

export ReflectionToWidget

"""
    ReflectionToWidget(; show_kind = true)

Projects a `ReflectedNode` tree to a `WidgetTree`. `show_kind` appends each
node's type name to its label.
"""
struct ReflectionToWidget <: Projection
    show_kind::Bool
end
ReflectionToWidget(; show_kind::Bool = true) = ReflectionToWidget(show_kind)

@iomap struct ReflectionToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    nodes::Dict{Vector{Int}, Any}      # tree path → the ReflectedNode it came from
    collapsed::Set{Vector{Int}}        # paths standing on a marker, derived from the shadow
end

# ── print_document ────────────────────────────────────────────────────────────

function print_document(p::ReflectionToWidget, recursion, node, ctx)
    nodes = Dict{Vector{Int}, Any}()
    collapsed = Set{Vector{Int}}()
    root = _tree_node(p, node, Int[1], nodes, collapsed)
    output = WidgetTree(Point2D(0, 0), Any[root])
    output.collapsed = collapsed
    ReflectionToWidgetIoMap(p, node, output, nodes, collapsed)
end

print_document(p::ReflectionToWidget, node) = print_document(p, nothing, node, nothing)

function _tree_node(p::ReflectionToWidget, node, path::Vector{Int}, nodes, collapsed)
    nodes[copy(path)] = node
    kids = node.children

    if kids isa AUnsyncedDocument
        push!(collapsed, copy(path))
        # A chevron is drawn only for a node that has children, so a collapsed
        # node needs one to stand on. It is never rendered — the path is in
        # `collapsed` — so its only job is to say how much is behind the chevron.
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
                        _tree_node(p, child, path, nodes, collapsed))
        pop!(path)
    end
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

# The chevron writes a whole new `collapsed` set. Exactly one path differs from
# what the printer derived, and that path names the node the user acted on.
function read_intent(p::ReflectionToWidget, iomap::ReflectionToWidgetIoMap,
                     op::ReplaceReferencedValueOperation)
    (op.document === iomap.output && _field_name(op) == "collapsed") || return op
    next = op.value
    next isa AbstractSet || return op

    # PAR-READER-IS-PURE: collect what changed and RETURN the edit; the shadow is
    # written by evaluating SetReflectedDisclosureOperation, never here. The
    # widget's own `collapsed` is still never written — the returned operation
    # targets the shadow, so expansion stays recorded there.
    changes = Pair{Any,Bool}[]
    for path in symdiff(next, iomap.collapsed)
        node = get(iomap.nodes, path, nothing)
        node === nothing && continue
        push!(changes, node => !(path in next))
    end
    isempty(changes) ? nothing : SetReflectedDisclosureOperation(changes)
end

# A row click selects; there is no reflected-domain cursor to move it to.
read_intent(::ReflectionToWidget, ::ReflectionToWidgetIoMap, ::ReplaceSelectionOperation) = nothing

read_intent(::ReflectionToWidget, ::ReflectionToWidgetIoMap, op) = op

# The operation carries a `Reference`; the writes we care about are the
# single-field form `tree.collapsed`.
function _field_name(op::ReplaceReferencedValueOperation)
    r = op.reference
    r isa ConcreteReference || return ""
    h = r.head
    h isa FieldReferenceStep ? String(h.name) : ""
end

end # module
