"""
    PaneModule

The **pane tree** — a layout of tab groups and splits, and the generic way to
organize documents on the screen.

A pane tree has four node kinds:

  * [`PaneTab`](@ref)   — a title and a content document.
  * [`PaneGroup`](@ref) — a tab group: an ordered list of tabs.
  * [`PaneSplit`](@ref) — an orientation, two or more children, and one weight
    per child.
  * [`PaneTree`](@ref)  — the root, plus the transient drag state.

**Focus is the selection.** No node carries a focus or an active-tab field. The
tree's selection names the focused tab (`root.elements[2].tabs[3]`), and each
node's own injected `selection` names the part of it that is on that path — so
the tab a group shows is the tab its own selection names. Every focus move and
every tab switch is one `ReplaceSelectionOperation`.

**Vertical and horizontal.** A `:vertical` split has a vertical divider, so its
children sit side by side; a `:horizontal` split stacks them. The symbol
`WidgetSplitPane` takes names the opposite thing — the axis the children lay out
along — and `PaneToWidget` is the one place that translates.

The tree edits live in `PaneSurgery.jl`, and they build generic operations; this
slice declares no operation of its own.
"""
module PaneModule

using ..CellModule
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..PrimitiveModule
using ..DomainModule
using ..SelectionModule
import ..SelectionModule: has_dormant_selection
export PaneDocument, PaneTree, PaneSplit, PaneGroup, PaneTab,
       get_pane_tab_title_string, default_new_pane_tab,
       get_opposite_pane_orientation, get_pane_split_axis,
       get_pane_weight, get_pane_weights, get_pane_normalized_weights,
       get_pane_groups, get_pane_parent
using ..OperationModule
using ..DraggingModule
export get_pane_path, get_pane_collection_path,
       get_pane_focus, get_pane_focused_group, get_pane_focused_tab_index, get_pane_focus_title,
       get_pane_shown_tab_index,
       get_pane_tab_reference, make_pane_focus_operation,
       get_pane_title_path, make_pane_title_caret_operation, make_pane_retarget_title_operation,
       make_pane_open_tab_operation, make_pane_close_tab_operation, make_pane_split_operation,
       make_pane_move_tab_operation, make_pane_drop_split_operation, make_pane_resize_operation,
       apply_pane_operation!
export get_pane_rectangles, get_pane_rectangle, get_pane_neighbour_group, get_pane_next_group,
       get_pane_group_at_point, get_pane_drop_zone, get_pane_zone_orientation
using ..LayoutModule
export show_layout, get_referenced_value, replace_referenced_value!,
       open_pane!, focus_pane!,
       get_window_tree, describe_document, get_document_title,
       pane_group_to_avoid, make_pane_api
using ..GestureBindingModule
using ..EventModule
using ..ProjectionModule
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..IntentModule
using ..WidgetModule
using ..IoMapModule
using ..ProjectionAlgebraModule
export PaneTreeToWidget, PaneTreeToWidgetIoMap,
       PaneSplitToWidgetSplitPane, PaneSplitToWidgetSplitPaneIoMap,
       PaneGroupToWidgetTabbedPane, PaneGroupToWidgetTabbedPaneIoMap,
       PaneToWidget




# ── PaneDocument (abstract base) ───────────────────────────────────────────

"""
    PaneDocument

Abstract base type of every pane-tree node. Subtypes the `Document` contract, so
`@document` injects `selection::Union{Nothing, Reference}` into each node.
"""
abstract type PaneDocument <: Document end

# ── PaneTab ────────────────────────────────────────────────────────────────

"""
    PaneTab(title, content[, icon])

One tab: a `title` document and a `content` document. `PaneTab("name", doc)`
wraps the title in a [`PrimitiveString`](@ref), which is what makes the in-place
rename an ordinary text edit — the tab strip prints the title through an editable
widget and the existing `PrimitiveString` gestures do the editing.
"""
@document struct PaneTab <: PaneDocument
    title::Any
    content::Any
    icon::Any = nothing
end

# String sugar. More specific than the macro's positional form, so the two
# coexist (a caller passing a document keeps reaching the raw constructor).
PaneTab(title::AbstractString, content) = PaneTab(PrimitiveString(String(title)), content)
PaneTab(title::AbstractString, content, icon) =
    PaneTab(PrimitiveString(String(title)), content, icon)

"""
    default_new_pane_tab() -> PaneTab

The tab an empty new-tab gesture opens: one named "untitled", holding the empty
placeholder. A projection takes a factory of its own when an application wants
something else in a fresh tab.

The content is a [`DocumentNothing`](@ref), not an empty string, because a fresh
tab has no domain yet. The placeholder is a document any other document can
replace: Alt+click selects it whole, a paste puts the clipboard in its place, and
a printable key turns it into an insertion. An empty string offers none of that —
it renders nothing, so a click in the tab body answers nothing and the selection
stays on the tab.
"""
default_new_pane_tab() = PaneTab("untitled", DocumentNothing())

"""
    get_pane_tab_title_string(tab) -> String

The tab's title as a plain string, whatever document carries it.
"""
get_pane_tab_title_string(tab::PaneTab) = _title_string(tab.title)
_title_string(title::PrimitiveString) = something(title.value, "")
_title_string(title::AbstractString) = String(title)
_title_string(title) = string(title)

# ── PaneGroup ──────────────────────────────────────────────────────────────

"""
    PaneGroup(tabs)

A tab group. `tabs` is a `CellVector` of [`PaneTab`](@ref); `PaneGroup([t1, t2])`
wraps a plain vector. A group can be empty — `PaneGroup(PaneTab[])` is the start
state of a fresh layout.

The tab the group shows is the tab its own `selection` names. There is no
`active` field.
"""
@document struct PaneGroup <: PaneDocument
    tabs::CellVector
end

# ── PaneSplit ──────────────────────────────────────────────────────────────

"""
    PaneSplit(orientation, elements; weights)

An inner node. `orientation` is `:vertical` (children side by side) or
`:horizontal` (children stacked). `elements` holds two or more
[`PaneGroup`](@ref)/[`PaneSplit`](@ref) children, and `weights` holds one
`Float64` per child. An empty `weights` means equal weights.
"""
@document struct PaneSplit <: PaneDocument
    orientation::Symbol
    elements::CellVector
    weights::CellVector = CellVector()
end

# Vector sugar. Two collection-typed fields mean the macro emits no wrapping
# constructor of its own, so this is the one that takes plain vectors.
function PaneSplit(orientation::Symbol, elements::AbstractVector; weights = nothing)
    ws = weights === nothing ? CellVector() : CellVector(Cell[Cell(Float64(w)) for w in weights])
    PaneSplit(Cell(orientation), CellVector(elements), ws, Cell(nothing))
end

# ── PaneTree ───────────────────────────────────────────────────────────────

"""
    PaneTree(root)

The whole layout. `root` is a [`PaneGroup`](@ref) or a [`PaneSplit`](@ref).

`drag` is transient state holding a tab drag in progress, or `nothing`. It is
not part of the layout and is not meant to be serialized.
"""
@document struct PaneTree <: PaneDocument
    root::Any
    drag::Any = nothing
end

# ── Tree walks ─────────────────────────────────────────────────────────────

"""
    get_pane_groups(tree) -> Vector{PaneGroup}

Every group of the tree, in the order a depth-first walk reaches them. This is
the traversal order the Tab chord follows.
"""
get_pane_groups(tree::PaneTree) = get_pane_groups(tree.root)
get_pane_groups(group::PaneGroup) = PaneGroup[group]
function get_pane_groups(split::PaneSplit)
    result = PaneGroup[]
    for i in 1:length(split.elements)
        append!(result, get_pane_groups(split.elements[i]))
    end
    result
end
get_pane_groups(::Any) = PaneGroup[]

"""
    get_pane_parent(tree, node) -> (owner, index) | Nothing

The node that holds `node`: `(tree, 0)` for the root, or `(split, k)` for the
`k`-th element of a split. `nothing` when the node is not in the tree.
"""
function get_pane_parent(tree::PaneTree, node)
    node === tree.root && return (tree, 0)
    _parent_walk(tree.root, node)
end

_parent_walk(::Any, node) = nothing
function _parent_walk(split::PaneSplit, node)
    elements = split.elements
    for i in 1:length(elements)
        elements[i] === node && return (split, i)
    end
    for i in 1:length(elements)
        found = _parent_walk(elements[i], node)
        found === nothing || return found
    end
    nothing
end

# ── Orientation ────────────────────────────────────────────────────────────

"""
    get_opposite_pane_orientation(orientation) -> Symbol

`:vertical` ⇄ `:horizontal`.
"""
get_opposite_pane_orientation(orientation::Symbol) =
    orientation === :vertical ? :horizontal : :vertical

"""
    get_pane_split_axis(split) -> Symbol

The axis a split's children lay out along, which is what `WidgetSplitPane` calls
its orientation: a `:vertical` split lays its children out `:horizontal`ly. The
one translation between the two vocabularies.
"""
get_pane_split_axis(split::PaneSplit) = get_opposite_pane_orientation(split.orientation)
get_pane_split_axis(orientation::Symbol) = get_opposite_pane_orientation(orientation)

# ── Weights ────────────────────────────────────────────────────────────────

"""
    get_pane_weights(split) -> Vector{Float64}

The split's weights, materialized. An empty `weights` field yields equal weights,
so a caller never branches on the empty case.
"""
function get_pane_weights(split::PaneSplit)
    n = length(split.elements)
    n == 0 && return Float64[]
    stored = split.weights
    length(stored) == n || return fill(1.0 / n, n)
    Float64[Float64(stored[i]) for i in 1:n]
end

"""
    get_pane_weight(split, index) -> Float64

The weight of one child.
"""
function get_pane_weight(split::PaneSplit, index::Integer)
    ws = get_pane_weights(split)
    (1 <= index <= length(ws)) ? ws[index] : 0.0
end

"""
    get_pane_normalized_weights(weights) -> Vector{Float64}

`weights` scaled to sum to 1.0. A zero or negative total falls back to equal
weights, so a degenerate input can not make a pane vanish.
"""
function get_pane_normalized_weights(weights::AbstractVector)
    n = length(weights)
    n == 0 && return Float64[]
    total = sum(Float64, weights)
    (isfinite(total) && total > 0) || return fill(1.0 / n, n)
    Float64[Float64(w) / total for w in weights]
end

# ── Dormant selections ─────────────────────────────────────────────────────
#
# Focus is the selection, and a group shows the tab its own selection names. So a
# group that loses the focus must keep that selection, or it forgets which tab it
# was showing; a tab must keep its own, or it forgets the caret inside it; and a
# split must keep its, or a nested split forgets which side had the focus.
#
# What they keep is dormant: still stored, still drawable, never acted on, and
# live again the moment the focus comes back.
has_dormant_selection(::PaneGroup) = true
has_dormant_selection(::PaneTab) = true
has_dormant_selection(::PaneSplit) = true


include("PaneSurgery.jl")
include("PaneGeometry.jl")
include("PaneProgram.jl")
include("PaneGestures.jl")
include("PaneToWidget.jl")

end # module PaneModule
