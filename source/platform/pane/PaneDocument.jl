# Fragment of `PaneModule` — the pane document types: the abstract
# `PaneDocument`, the tab that names a content document, and the containers
# that arrange them.

abstract type PaneDocument <: Document end

# ── PaneTabTitle ───────────────────────────────────────────────────────────

"""
    PaneTabTitle(name; icon = nothing, badges = nothing, tooltip = nothing)

The title of a tab: the `name` that a person types and renames, the `icon`
before it, the `badges` after it, and the `tooltip` that the tab shows when the
pointer rests on it.

Use it when a tab must say more than a name, such as the state of the work that
its content does. `name` is a string or a [`PrimitiveString`](@ref); a rename
edits it with the gestures of every other string, and nothing else changes it.
`icon` is the name of an icon (a `Symbol`), `badges` a vector of `WidgetBadge`s
and `tooltip` a string or a document. Each of the three takes a value, a cell
that holds it, or a function of no arguments that computes it, so a title
follows the state that its function reads with no write: no operation and no
entry in the undo list.

# Example

    finished = Cell(0)
    title = PaneTabTitle("Fingerprint tests";
                         icon = () -> finished[] == 40 ? :circle_check : :loader,
                         badges = () -> Any[WidgetBadge(string(finished[], "/40"); role = :accent)],
                         tooltip = "the fingerprint tests of showcases/tsn")
    PaneTab(title, group_document)

A file of a layout keeps the name and the values of the three parts at the time
of the save, and not the functions that computed them.

See also `PaneTab`, `WidgetTabLabel`, `WidgetBadge`.
"""
@document struct PaneTabTitle <: PaneDocument
    name::Any
    icon::Any = nothing
    badges::Any = nothing
    tooltip::Any = nothing
end

PaneTabTitle(name::AbstractString; kwargs...) = PaneTabTitle(PrimitiveString(String(name)); kwargs...)
PaneTabTitle(name::PrimitiveString; icon = nothing, badges = nothing, tooltip = nothing) =
    PaneTabTitle(name, _make_title_part_cell(icon), _make_title_part_cell(badges),
                 _make_title_part_cell(tooltip))

# A part of a title takes a value, a cell or a function, and keeps the value as it is.
_make_title_part_cell(part::AbstractCell) = part
_make_title_part_cell(part::Function) = Cell(@computation part())
_make_title_part_cell(part) = Cell(part)

# ── PaneTab ────────────────────────────────────────────────────────────────

"""
    PaneTab(title, content[, icon])

One tab: a [`PaneTabTitle`](@ref) and a `content` document. `PaneTab("name",
doc)` makes a title with that name, and `PaneTab("name", doc, icon)` gives it an
icon too. The name is a [`PrimitiveString`](@ref), which is what makes the
in-place rename an ordinary text edit: the tab strip prints the name through an
editable widget and the `PrimitiveString` gestures do the editing.

Use it to give a document a title in a group; `open_pane!` makes one for you,
and a `PaneSplit` you write by hand needs them.

# Example

    PaneTab("Delay", make_result_plot(frame))

See also `PaneTabTitle`, `PaneGroup`, `open_pane!`.
"""
@document struct PaneTab <: PaneDocument
    title::Any
    content::Any
end

# A name makes a title. More specific than the macro's positional form, so a
# caller that passes a `PaneTabTitle` keeps reaching the raw constructor.
PaneTab(title::AbstractString, content) = PaneTab(PaneTabTitle(title), content)
PaneTab(title::PrimitiveString, content) = PaneTab(PaneTabTitle(title), content)
PaneTab(title::Union{AbstractString,PrimitiveString}, content, icon) =
    PaneTab(PaneTabTitle(title; icon), content)

# A file names the title of a tab as a `PaneTabTitle`, or as a name with an
# `icon` beside it; both build the same tab.
function make_pred_document(::Type{PaneTab}, positional, keywords)
    isempty(positional) || return PaneTab(positional...)
    values = Dict{Symbol,Any}(keywords)
    title = values[:title]
    icon = get(values, :icon, nothing)
    (icon === nothing || title isa PaneTabTitle) && return PaneTab(title, values[:content])
    PaneTab(title, values[:content], icon)
end

# A person edits what a tab shows.
get_edited_field(::PaneTab) = :content

"""
    default_new_pane_tab() -> PaneTab

The tab an empty new-tab gesture opens: one with an empty name, holding the
empty placeholder. A projection takes a factory of its own when an application
wants something else in a fresh tab.

The content is a [`DocumentNothing`](@ref), not an empty string, because a fresh
tab has no domain yet. The placeholder is a document any other document can
replace: Alt+click selects it whole, a paste puts the clipboard in its place, and
a printable key turns it into an insertion. An empty string offers none of that —
it renders nothing, so a click in the tab body answers nothing and the selection
stays on the tab.

The name is empty so that the tab is called after what it holds: see
[`get_pane_tab_title_string`](@ref).
"""
default_new_pane_tab() = PaneTab("", DocumentNothing())

"""
    get_pane_tab_title_string(tab) -> String

The tab's title as a plain string, whatever document carries it.

A tab with an empty name is called after its content: the content's own title
(`get_document_title`), and "untitled" when the content has none. A pasted
object therefore names the tab it fills. A description of the content is never
used, because it changes as the content does, and a tab must not rename itself.
"""
function get_pane_tab_title_string(tab::PaneTab)
    title = _title_string(tab.title)
    isempty(title) || return title
    named = get_document_title(tab.content)
    (named isa AbstractString && !isempty(strip(named))) ? String(named) : "untitled"
end
_title_string(title::PaneTabTitle) = _title_string(title.name)
_title_string(title::PrimitiveString) = something(title.value, "")
_title_string(title::AbstractString) = String(title)
_title_string(title) = string(title)

# What the REPL and the answer of a tool show of a tab: its title and what it
# shows, as the REPL shows that. A tab that holds a table then says how many rows
# the table has. Julia's own display of a value, so a `print` or a `show` of the
# tab is as it was.
function Base.show(io::IO, mime::MIME"text/plain", tab::PaneTab)
    print(io, "PaneTab(", repr(get_pane_tab_title_string(tab)), ", ")
    show(io, mime, tab.content)
    print(io, ")")
end

# A paste never takes the place of a pane, and a pane is never pasted: the tree
# of a window is changed by the pane's own edits, which keep it well formed. A
# paste fills or replaces the content of a tab.
accepts_pasted_replacement(::PaneDocument, ::Any) = false
accepts_pasted_replacement(::Any, ::PaneDocument) = false
accepts_pasted_replacement(::PaneDocument, ::PaneDocument) = false

# A copy or a note of a focused tab takes what the tab shows. A group, a split
# and the tree of a window show no document of their own.
find_clipboard_document(tab::PaneTab) = tab.content
find_clipboard_document(::PaneDocument) = nothing

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

# `tabs` has no field default, so the macro gives the bare name no keyword
# constructor, only the bracketed positional one (`PaneGroup([t1, t2])`) —
# `pred_arguments` always writes a document's fields as keywords, so the file
# format needs this one.
make_pred_document(::Type{PaneGroup}, positional, keywords) =
    PaneGroup(isempty(positional) ? only(keywords).second : positional[1])

# ── PaneSplit ──────────────────────────────────────────────────────────────

"""
    PaneSplit(orientation, elements; weights)

An inner node. `orientation` is `:vertical` (children side by side) or
`:horizontal` (children stacked). `elements` holds two or more
[`PaneGroup`](@ref)/[`PaneSplit`](@ref) children, and `weights` holds one
`Float64` per child. An empty `weights` means equal weights.

Use it to put panes side by side, `:vertical`, or one above the other,
`:horizontal`, with `weights` for their share of the space: write it at a
reference with `replace_referenced_value!` to split the window.

# Example

    tree_reference = find_pane_tree_reference(editor)
    tree = evaluate_reference(editor.document, tree_reference)
    replace_referenced_value!(editor, concat_references(tree_reference, @reference(tree, root)),
        PaneSplit(:vertical, [PaneGroup([PaneTab("Plot", plot)]), tree.root]; weights = [0.4, 0.6]))

See also `PaneGroup`, `PaneTab`, `replace_referenced_value!`.
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

Use it to read the whole layout: its `root` is the group or the split that holds
everything. For a replace, its complete reference is the path to the tree
followed by `root`:
`concat_references(tree_reference, @reference(tree, root))`.

# Example

    tree_reference = find_pane_tree_reference(editor)
    tree = evaluate_reference(editor.document, tree_reference)
    println(typeof(tree.root))

See also `PaneSplit`, `PaneGroup`, `show_layout`.

`drag` is transient state holding a tab drag in progress, or `nothing`. It is
not part of the layout and is not meant to be serialized.
"""
@document struct PaneTree <: PaneDocument
    root::Any
    drag::Any = nothing
end

# A drag in progress is not layout: it is a pointer's own transient state, gone
# the moment the button comes up, and never something a save should freeze.
pred_arguments(tree::PaneTree) = (), Pair{Symbol,Any}[:root => tree.root]

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
