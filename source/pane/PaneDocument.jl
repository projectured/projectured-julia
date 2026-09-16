# Fragment of `PaneModule` — the pane document types: the abstract
# `PaneDocument`, the tab that names a content document, and the containers
# that arrange them.

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

Use it to give a document a title in a group; `open_pane!` makes one for you,
and a `PaneSplit` you write by hand needs them.

# Example

    PaneTab("Delay", make_result_plot(frame))

See also `PaneGroup`, `open_pane!`.

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

Use it to hold tabs in one place on the screen; a split divides groups, and
`open_pane!` adds a tab to a group.

# Example

    PaneGroup([PaneTab("Runs", batch), PaneTab("Delay", plot)])

See also `PaneSplit`, `PaneTab`.

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

Use it to put panes side by side, `:vertical`, or one above the other,
`:horizontal`, with `weights` for their share of the space: write it at a
reference with `replace_referenced_value!` to split the window.

# Example

    replace_referenced_value!(editor, @reference(window, root),
        PaneSplit(:vertical, [PaneGroup([PaneTab("Plot", plot)]), get_window_tree(editor).root]; weights = [0.4, 0.6]))

See also `PaneGroup`, `PaneTab`, `replace_referenced_value!`.

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

Use it to read the whole layout: its `root` is the group or the split that holds
everything, and `@reference(window, root)` names it for a replace.

# Example

    tree = get_window_tree(editor)
    println(typeof(tree.root))

See also `PaneSplit`, `PaneGroup`, `show_layout`.

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
