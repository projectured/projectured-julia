"""
    PaneProgramModule

**The window's layout, as something a language model can read and change.**

Three verbs. [`show_layout`](@ref) prints the pane tree as a Julia program,
[`get_referenced_value`](@ref) answers the node a reference names, and [`replace_referenced_value!`](@ref)
writes a new value at a reference.

**The level is the reference, not the verb.** A replace at `root` rearranges the
whole window; a replace at `root.elements[1]` moves one side of a split; a
replace at `root.elements[1].tabs[1].content` changes what one pane holds. One
verb reaches all three, because a layout is a document and a reference names any
part of one.

# What the model reads

`show_layout` answers the program that rebuilds the window as it stands:

```julia
window = get_window_tree(editor)

runner    = get_referenced_value(editor, @reference(window, root.elements[1].tabs[1]))   # Runner — the run form
assistant = get_referenced_value(editor, @reference(window, root.elements[2].tabs[1]))   # Assistant — this conversation

replace_referenced_value!(editor, @reference(window, root),
    PaneSplit(:vertical, [
        PaneGroup([runner]),
        PaneGroup([assistant])], weights = [0.3, 0.7]))
```

**A reference is written against the window**, which is what the first line binds.
`@reference(window, path)` fills in the type of every node from the tree itself,
so a path needs no `::T` spelled by hand and is wrong at once rather than later
when it names a node that is not there.

Paste it back unchanged and the window does not move. A model that wants a change
therefore edits the text it was given — it swaps two names, changes a weight, or
puts two names in one `PaneGroup` — rather than composing a program out of a
docstring. And each name binds the `PaneTab` object that is already there, so the
tree that is written holds the same tabs and no pane re-prints.

# The numbering

`[…]` counts elements, from 1: `root.elements[1].tabs[2]` is the second tab of
the first group, and `tabs[2, 3]` is the second and third tabs together. That is
the whole of what a caller needs to know.

# What else the model may write

A layout is written with `PaneSplit`, `PaneGroup`, `GridLayout` and `@reference`,
and this module exports none of them — [`pane_api`](@ref) declares them **by
name** instead. A declaration is not an export, so each of those names still has
exactly one owning module, and the program says them plainly.

Their modules are not declared, and that is the point. `@document` exports about
thirty generated schema variants per document type — `APaneSplit`, `ACPaneSplit`,
`DCPaneSplit`, each with no documentation of its own. Declared whole,
`PaneModule` and `ReferenceModule` take the surface from 10 names to 122, and a
search for "what panes are open" then answers with those variants instead of
`show_layout`. Measured, not feared.

`GridLayout` is what one pane holds several documents with: `GridLayout(cells, 2)`
written at a tab's `.content` puts four plots in a pane in two rows, with one tab
strip over them rather than four.

# Adding a description

[`describe_document`](@ref) is the one line the program's comment carries
for a pane. Write a method for each document this window can show, beside the
ones below.
"""
module PaneProgramModule

import ..ReferenceModule
import ..ReferenceModule:
    Reference, EmptyReference, FieldReferenceStep, RangeReferenceStep,
    evaluate_reference, strip_reference_types, get_reference_steps,
    is_fully_typed_reference, annotate_reference_types, var"@reference"
import ..OperationModule: ReplaceReferencedValueOperation
import ..SelectionModule: replace_selection!
import ..PaneModule
import ..PaneModule:
    PaneTree, PaneSplit, PaneGroup, PaneTab, pane_groups, pane_tab_title_string,
    pane_parent, pane_weights, pane_normalized_weights
import ..PaneGeometryModule: pane_rectangles
# The pane package binds it, so a layout costs this package no dependency of its
# own and the window's closure is what it was.
import ..LayoutModule
import ..LayoutModule: LayoutDocument
import ..PaneSurgeryModule:
    apply_pane_operation!, pane_focus, pane_focus_operation, pane_shown_tab_index,
    pane_close_tab_operation, pane_move_tab_operation, pane_drop_split_operation,
    pane_resize_operation, pane_open_tab_operation, pane_focused_group

export show_layout, get_referenced_value, replace_referenced_value!,
       open_pane!, focus_pane, close_pane, move_pane, resize_pane,
       get_window_tree, describe_document, pane_group_to_avoid, pane_api

"""
    pane_api() -> Vector

What a model needs declared to write the program [`show_layout`](@ref) prints:
this module's verbs, and the borrowed names the program says.

The borrowed ones are listed **by name**. Their modules export far more than a
layout needs, and a declared module puts every one of its exported names in the
model's search — this module's own documentation says what that costs.
"""
pane_api() = Any[
    PaneProgramModule,
    PaneModule      => (:PaneTree, :PaneSplit, :PaneGroup, :PaneTab),
    LayoutModule    => (:GridLayout, :HorizontalLayout, :VerticalLayout,
                        :FlowLayout, :StackLayout),
    ReferenceModule => (Symbol("@reference"),),
]

# ── The window a verb acts on ───────────────────────────────────────────────

"""
    get_window_tree(editor) -> PaneTree

The pane tree the editor shows.

A running editor draws a screen of windows, and a headless caller — a test, a
workload — holds the tree itself. Both arrive at a verb, so both are read.
`document.windows`, not `getfield`: the field holds a cell and the property is
what reads through it.
"""
get_window_tree(tree::PaneTree) = tree

function get_window_tree(editor)
    document = getfield(editor, :document)
    document isa PaneTree && return document
    windows = document.windows
    isempty(windows) && error("The editor shows no window.")
    first(windows).content
end

# ── What a pane holds ───────────────────────────────────────────────────────

"""
    describe_document(document) -> String

One short line saying what a document is.

It is the comment `show_layout` writes beside each pane, and it is the sentence a
caller asks for about a value it holds: `describe_document(batch)` says how far a
set of runs has got, whether that set is in a pane or in a hand.

**Say what changes.** "18 runs: 12 done, 6 running" tells a reader the set is not
finished, which is the fact they need next; "a SimulationBatchDocument" tells
them nothing.

The default answers the type's name, so a document with no method of its own
still says something. **Each application writes the methods for the documents it
holds**, beside those documents — this package can only describe what it knows,
which is a layout and an empty pane.
"""
describe_document(content) = String(nameof(typeof(content)))
describe_document(::Nothing) = "empty"

# A pane that holds a layout holds several documents at once, and how many is the
# fact a reader needs first.
describe_document(layout::LayoutDocument) =
    "a layout of " * string(length(layout.children))
describe_document(row::LayoutModule.HorizontalLayout) =
    "a row of " * string(length(row.children))
describe_document(column::LayoutModule.VerticalLayout) =
    "a column of " * string(length(column.children))
describe_document(flow::LayoutModule.FlowLayout) =
    "a wrapped row of " * string(length(flow.children))
describe_document(stack::LayoutModule.StackLayout) =
    "a stack of " * string(length(stack.children))
function describe_document(grid::LayoutModule.GridLayout)
    columns = Int(grid.columns)
    "a grid of " * string(length(grid.children)) * " in " * string(columns) *
        (columns == 1 ? " column" : " columns")
end
# ── Opening a pane ──────────────────────────────────────────────────────────

"""
    pane_group_to_avoid(tree) -> PaneGroup or nothing

The group [`open_pane!`](@ref) should not open in. `nothing` by default.

**An answer must not cover the question.** A window whose conversation sits in a
group of its own wants a new pane anywhere else, or the thing the person asked
for replaces the asking. Which group that is belongs to the application, so the
application writes the method — this package holds no idea of a conversation.
"""
pane_group_to_avoid(tree::PaneTree) = nothing

"""
    open_pane!(editor, document; title = nothing) -> Reference

Put `document` in a new tab, and answer a reference to the tab it made.

**This is the one placement verb.** Everything else a layout can be asked for —
move a pane, resize a split, close a tab, change what a pane holds — is
[`replace_referenced_value!`](@ref) at a reference, and the program
[`show_layout`](@ref) prints is the text to edit. What a replace cannot say
without naming a group by hand is *where a new pane goes*, and that policy is
this verb: the focused group, and never the one
[`pane_group_to_avoid`](@ref) names.

**It answers a reference, not a title.** A reference names any part of any
document and a title names a tab, so the reference is what the next call takes:

```julia
where = open_pane!(editor, chart)
focus_pane(editor; pane = where)
replace_referenced_value!(editor, where, PaneTab(other, "something else"))
```

`title` is what the tab is called. A title already taken gets a number, so two
panes are never one name, and the name is for a person to read rather than for a
caller to address the pane by.
"""
function open_pane!(editor, document; title = nothing)
    tree = get_window_tree(editor)
    groups = pane_groups(tree)
    isempty(groups) && error("The window has no group to open a pane in.")
    avoid = pane_group_to_avoid(tree)
    elsewhere = avoid === nothing ? groups : [g for g in groups if g !== avoid]
    isempty(elsewhere) && (elsewhere = groups)
    group = pane_focused_group(tree)
    (group === nothing || !(group in elsewhere)) && (group = first(elsewhere))

    name = _unique_pane_title(tree, title === nothing ? describe_document(document) :
                                                        String(title))
    tab = PaneTab(name, document)
    operation = pane_open_tab_operation(tree, group, tab)
    operation === nothing && error("The window has no group to open a pane in.")
    apply_pane_operation!(tree, operation)
    reference = _reference_of_tab(tree, tab)
    reference === nothing &&
        error("The pane was opened and then could not be found again.")
    reference
end

# A title no other tab carries. A person reads a title, so two panes reading the
# same is a window nobody can talk about.
function _unique_pane_title(tree::PaneTree, wanted::AbstractString)
    taken = Set(pane_tab_title_string(tab)
                for group in pane_groups(tree) for tab in group.tabs)
    String(wanted) in taken || return String(wanted)
    index = 2
    while String(wanted) * " (" * string(index) * ")" in taken
        index += 1
    end
    String(wanted) * " (" * string(index) * ")"
end

"""
    _reference_of_tab(tree, tab) -> Reference or nothing

Where `tab` sits, as a reference the model can write.

Built by identity and then annotated against the tree, which is what
`@reference(window, path)` does at its call site: every node records the type of
what it stands on, and a bare path is refused by [`get_referenced_value`](@ref).
"""
function _reference_of_tab(tree::PaneTree, tab)
    steps = _tab_steps(tree.root, tab, Any[FieldReferenceStep("root")])
    steps === nothing && return nothing
    annotate_reference_types(tree, Reference(steps...))
end

# The steps from `node` down to `tab`, or nothing when it is not under `node`.
# `[i]` counts elements from 1 and `RangeReferenceStep` counts gaps from 0, so
# the element `i` is the range `i-1` to `i`.
function _tab_steps(node, tab, prefix::Vector{Any})
    if node isa PaneGroup
        for index in 1:length(node.tabs)
            node.tabs[index] === tab || continue
            return vcat(prefix, Any[FieldReferenceStep("tabs"),
                                    RangeReferenceStep(index - 1, index)])
        end
    elseif node isa PaneSplit
        for index in 1:length(node.elements)
            found = _tab_steps(node.elements[index], tab,
                               vcat(prefix, Any[FieldReferenceStep("elements"),
                                                RangeReferenceStep(index - 1, index)]))
            found === nothing || return found
        end
    end
    nothing
end

# ── Reading one node ────────────────────────────────────────────────────────

"""
    get_referenced_value(editor, reference) -> Document

The node `reference` names, resolved against the window's pane tree.

The reference is rooted at the **tree**, not at the editor, so `root` is the
tree's own field whether the editor holds a screen of windows or the bare tree.
Write it with the reference macro against the window:
`get_referenced_value(editor, @reference(window, root.elements[1].tabs[1]))`.

Throws when the path reaches nothing, naming the path, because a path that no
longer resolves is a layout that moved under the caller.
"""
function get_referenced_value(editor, reference::Reference)
    tree = get_window_tree(editor)
    _refuse_stale(reference)
    path = strip_reference_types(reference)
    node = try
        evaluate_reference(tree, path)
    catch error
        throw(ArgumentError("No node at " * _path_text(path) * ": " * sprint(showerror, error)))
    end
    node === nothing && throw(ArgumentError("No node at " * _path_text(path) * "."))
    node
end

# ── Writing ─────────────────────────────────────────────────────────────────

"""
    replace_referenced_value!(editor, reference, value) -> Text

Put `value` where `reference` points, and answer the window's new program.

This is one `ReplaceReferencedValueOperation`, so the person undoes it with one
press. A reference whose last step is a range **splices**: replacing
`root.elements[1].tabs[2, 3]` with a vector of tabs writes those two tabs, and
with `[]` removes them.

```julia
replace_referenced_value!(editor, @reference(window, root),
                          PaneSplit(:vertical, [a, b], weights = [0.3, 0.7]))
replace_referenced_value!(editor, @reference(window, root.elements[1].tabs[1].content),
                          GridLayout(cells, 2))
```

Two things it repairs, which the caller never has to think about: the pane that
had the focus keeps it wherever it landed, and a group that was showing its
second tab goes on showing that tab.

It refuses a write it can see is wrong — an empty reference, a range outside its
collection, or a value of a type that slot can not hold — rather than leaving the
window in a shape nothing can draw.
"""
function replace_referenced_value!(editor, reference::Reference, value)
    tree = get_window_tree(editor)
    _refuse_stale(reference)
    path = strip_reference_types(reference)
    _refuse_bad_write(tree, path, value)

    focused = _focused_tab(tree)
    shown = _shown_tabs(tree)
    apply_pane_operation!(tree, ReplaceReferencedValueOperation(nothing, path, value))
    _restore_shown!(tree, shown)
    _restore_focus!(tree, focused)
    show_layout(editor)
end

# What the tree can not accept, said before anything is written. The three cases
# are the ones a caller reaches by editing a path by hand: a reference that names
# no slot, a range past the end of its collection, and a node put where its kind
# does not belong.
# A reference written against the window — `@reference(window, …)` — takes the
# type of every node from the tree it is written against. A node the tree does
# not have takes none, so a path that is not fully typed is a path that named
# something the window no longer holds. Saying that is better than following it
# to whatever the slot now is.
function _refuse_stale(reference::Reference)
    is_fully_typed_reference(reference) && return reference
    throw(ArgumentError("The path " * _path_text(strip_reference_types(reference)) *
                        " names nothing in this window. `show_layout` prints what it holds."))
end

function _refuse_bad_write(tree::PaneTree, path::Reference, value)
    steps = get_reference_steps(path)
    isempty(steps) &&
        throw(ArgumentError("An empty reference names no slot. The layout is at `root`."))

    parent = length(steps) == 1 ? tree : evaluate_reference(tree, Reference(steps[1:end-1]...))
    parent === nothing && throw(ArgumentError("No node at " * _path_text(path) * "."))

    terminal = steps[end]
    if terminal isa RangeReferenceStep
        n = length(parent)
        (0 <= terminal.start <= terminal.stop <= n) ||
            throw(ArgumentError("The range " * _step_text(terminal) * " is outside a collection of " *
                                string(n) * "."))
    end
    _refuse_bad_kind(steps, value)
end

# Which kind a slot holds is said by the field the path went through last:
# `tabs` holds tabs, `elements` and `root` hold groups and splits. Nothing else
# in a pane tree is a slot a caller writes.
function _refuse_bad_kind(steps, value)
    field = nothing
    for step in steps
        step isa FieldReferenceStep && (field = step.name)
    end
    expected = field == "tabs" ? (PaneTab,) :
               field in ("elements", "root") ? (PaneGroup, PaneSplit) : nothing
    expected === nothing && return
    for one in (value isa AbstractVector ? value : (value,))
        any(t -> one isa t, expected) && continue
        throw(ArgumentError("A " * String(nameof(typeof(one))) * " can not go in `" * field *
                            "`, which holds " * join(String.(nameof.(expected)), " or ") * "."))
    end
end

# ── The focus, and the tab each group shows ────────────────────────────────
#
# Focus is the selection, and the selection is a path into the tree the write
# replaced. A fresh `PaneGroup` carries no selection at all, so it would show its
# first tab. Both are repaired by object identity: a tab that is still in the
# tree is the same object it was, whatever path now reaches it.

_focused_tab(tree::PaneTree) = begin
    focus = pane_focus(tree)
    (focus === nothing || focus[2] == 0) ? nothing : focus[1].tabs[focus[2]]
end

_shown_tabs(tree::PaneTree) =
    Any[group.tabs[pane_shown_tab_index(group)]
        for group in pane_groups(tree) if length(group.tabs) > 0]

function _restore_shown!(tree::PaneTree, shown)
    for group in pane_groups(tree)
        n = length(group.tabs)
        n == 0 && continue
        index = findfirst(i -> any(t -> t === group.tabs[i], shown), 1:n)
        index === nothing && continue
        replace_selection!(group, @reference(group, tabs[index]))
    end
end

function _restore_focus!(tree::PaneTree, focused)
    focused === nothing && return
    for group in pane_groups(tree)
        for i in 1:length(group.tabs)
            group.tabs[i] === focused || continue
            apply_pane_operation!(tree, pane_focus_operation(tree, group, i))
            return
        end
    end
end

# ── One pane, one act ───────────────────────────────────────────────────────
#
# Each of these is one `PaneSurgery` operation behind one word. A model can do
# all of them by editing the program `show_layout` prints, and for a window of
# ten panes that is ten names restated to move one — so the whole-window rewrite
# and the single act are both here, and a model picks by which one is smaller.
#
# **They name a pane by its title**, because that is the word the person used.
# `CampaignAgentModule` addresses its panes the same way, and a title is unique
# in a window the runner opened. Two panes a person renamed to one thing are
# refused, with the count.

"""
    focus_pane(editor; pane) -> Text

Show `pane` and give it the focus, and answer the window's new program.
"""
function focus_pane(editor; pane)
    tree = get_window_tree(editor)
    group, index = _pane_named(tree, pane)
    _apply(editor, tree, pane_focus_operation(tree, group, index), "focus", pane)
end

"""
    close_pane(editor; pane) -> Text

Close `pane`, and answer the window's new program.

The group goes too when this was its last tab, and the split goes when that
leaves it with one child. Closing is its own word because it destroys something:
a rearrangement never does, and this always does.
"""
function close_pane(editor; pane)
    tree = get_window_tree(editor)
    group, index = _pane_named(tree, pane)
    _apply(editor, tree, pane_close_tab_operation(tree, group, index), "close", pane)
end

"""
    move_pane(editor; pane, next_to, side = "tab") -> Text

Move `pane` to `next_to`, and answer the window's new program.

`side` says where it lands: `"left"`, `"right"`, `"above"` or `"below"` splits
the pane it lands on, and `"tab"` — the default — makes it another tab of the
same group.
"""
function move_pane(editor; pane, next_to, side = "tab")
    tree = get_window_tree(editor)
    source, index = _pane_named(tree, pane)
    target, _ = _pane_named(tree, next_to)
    word = lowercase(String(side))
    operation = if word == "tab"
        pane_move_tab_operation(tree, source, index, target, length(target.tabs) + 1)
    else
        orientation, edge = _split_side(word)
        pane_drop_split_operation(tree, source, index, target, orientation, edge)
    end
    _apply(editor, tree, operation, "move", pane)
end

_SIDES = (left = :vertical, right = :vertical, above = :horizontal, below = :horizontal)

function _split_side(word::AbstractString)
    edge = Symbol(word)
    haskey(_SIDES, edge) ||
        throw(ArgumentError("There is no side called " * repr(word) *
                            ". They are: left, right, above, below, tab."))
    (getfield(_SIDES, edge), edge)
end

"""
    resize_pane(editor; pane, fraction) -> Text

Give `pane` that share of the space its split divides, and answer the window's
new program. `fraction` is between 0 and 1, and what the other children of that
split had is scaled to fit the rest.
"""
function resize_pane(editor; pane, fraction)
    tree = get_window_tree(editor)
    group, _ = _pane_named(tree, pane)
    parent = pane_parent(tree, group)
    (parent !== nothing && parent[1] isa PaneSplit) ||
        throw(ArgumentError("The pane " * repr(String(pane)) *
                            " is not inside a split, so it already has the whole window."))
    split, slot = parent
    share = Float64(fraction)
    (0 < share < 1) ||
        throw(ArgumentError("A share is between 0 and 1, and " * string(share) * " is not."))
    weights = pane_normalized_weights(pane_weights(split))
    rest = 1.0 - weights[slot]
    scale = rest <= 0 ? 0.0 : (1.0 - share) / rest
    resized = Float64[i == slot ? share : weights[i] * scale for i in 1:length(weights)]
    _apply(editor, tree, pane_resize_operation(tree, split, resized), "resize", pane)
end

# The pane a title names, or a refusal that says what the window does hold.
function _pane_named(tree::PaneTree, title)
    wanted = String(title)
    found = Tuple{PaneGroup,Int}[]
    for group in pane_groups(tree), i in 1:length(group.tabs)
        pane_tab_title_string(group.tabs[i]) == wanted && push!(found, (group, i))
    end
    isempty(found) &&
        throw(ArgumentError("No pane is called " * repr(wanted) * ". The panes are: " *
                            join(_pane_titles(tree), ", ") * "."))
    length(found) == 1 ||
        throw(ArgumentError(string(length(found)) * " panes are called " * repr(wanted) *
                            ". Rename one, or write the change with replace_referenced_value!."))
    found[1]
end

_pane_titles(tree::PaneTree) =
    [pane_tab_title_string(tab) for group in pane_groups(tree) for tab in group.tabs]

# `PaneSurgery` answers `nothing` for an edit that does not apply, and a verb
# that answered the unchanged window would look as though it had worked.
function _apply(editor, tree::PaneTree, operation, act::AbstractString, pane)
    operation === nothing &&
        throw(ArgumentError("Nothing to " * act * ": the window can not " * act * " " *
                            repr(String(pane)) * " that way."))
    apply_pane_operation!(tree, operation)
    show_layout(editor)
end

# ── The program ─────────────────────────────────────────────────────────────

"""
    show_layout(editor) -> Text

Which panes are open, where each one sits and what it holds, as the Julia
program that rebuilds the window.

It answers a `Text`, not a `String`, so the program arrives as the lines it is.
A `String` would reach a model through `repr` and arrive as one line of `\n`
escapes, which is a program a reader has to decode before it can edit it.

Every pane gets a name bound to the tab that is there, and the comment says what
that pane holds. The last statement is the [`replace_referenced_value!`](@ref) call that makes
this very layout, so the way to change the window is to edit the program and give
it back.
"""
function show_layout(editor)
    tree = get_window_tree(editor)
    panes = _Pane[]
    _collect_panes!(panes, tree.root, "root", _pane_shares(tree))
    isempty(panes) && return Text("The window holds no pane.")

    _name_panes!(panes)
    names = Dict(p.path => p.name for p in panes)
    focused = _focused_tab(tree)

    calls = [p.name * _pad(p.name, maximum(length(q.name) for q in panes)) *
             " = get_referenced_value(editor, @reference(window, " *
             p.path * "))" for p in panes]
    width = maximum(length, calls)
    lines = String[]
    for (call, pane) in zip(calls, panes)
        note = pane.title * " — " * pane.description *
               (isempty(pane.share) ? "" : " · " * pane.share) *
               (pane.tab !== nothing && pane.tab === focused ? " (focused)" : "")
        push!(lines, call * _pad(call, width) * "  # " * note)
    end

    Text("window = get_window_tree(editor)\n\n" * join(lines, "\n") *
         "\n\nreplace_referenced_value!(editor, @reference(window, root),\n    " *
         _build_node(tree.root, "root", names, 4) * ")\n")
end

struct _Pane
    path::String
    title::String
    description::String
    share::String     # how much of the window this pane has, or "" for the whole of it
    tab::Any
    name::String
end

_pad(s::AbstractString, width::Integer) = " " ^ max(0, width - length(s))

# How much of the window each group has, as a percentage of each axis. It comes
# from the weights alone — `pane_rectangles` walks the tree and divides the unit
# square — so it needs no printed window and no measurement. A group that has all
# of both axes says nothing, because "100% × 100%" on every line of a one-pane
# window is noise.
function _pane_shares(tree::PaneTree)
    shares = Dict{PaneGroup,String}()
    for (group, rectangle) in pane_rectangles(tree)
        percent(value) = string(round(Int, 100 * value)) * "%"
        shares[group] = (rectangle.w >= 0.999 && rectangle.h >= 0.999) ? "" :
                        percent(rectangle.w) * " × " * percent(rectangle.h)
    end
    shares
end

function _collect_panes!(panes::Vector{_Pane}, node, path::String, shares)
    if node isa PaneGroup
        share = get(shares, node, "")
        for i in 1:length(node.tabs)
            tab = node.tabs[i]
            tab_path = path * ".tabs[" * string(i) * "]"
            title = pane_tab_title_string(tab)
            push!(panes, _Pane(tab_path, title,
                               describe_document(tab.content), share, tab, ""))
            _collect_cells!(panes, tab.content, tab_path, title)
        end
    elseif node isa PaneSplit
        for i in 1:length(node.elements)
            _collect_panes!(panes, node.elements[i],
                            path * ".elements[" * string(i) * "]", shares)
        end
    end
    panes
end

# A pane that holds a layout holds several documents, and each of them gets a
# name too, one level down. That is what lets a model move a cell: it has the
# reference, and the comment says what is in it.
#
# The layout itself is not printed as a construction. Its knobs — the columns,
# the gaps, the alignments, a policy per column and per row — would have to be
# printed exactly or the program would not rebuild the window it describes, and a
# model that wants a different arrangement writes
# `GridLayout(cells, 2)` at the pane's `.content` from the names
# below.
function _collect_cells!(panes::Vector{_Pane}, content, tab_path::String, title::AbstractString)
    content isa LayoutDocument || return panes
    for k in 1:length(content.children)
        push!(panes, _Pane(tab_path * ".content.children[" * string(k) * "]",
                           title * " cell " * string(k),
                           describe_document(content.children[k]), "", nothing, ""))
    end
    panes
end

# A name says which pane a reader means, so it comes from the title — the
# person's own word for it. It carries no meaning to a verb: the reference does.
function _name_panes!(panes::Vector{_Pane})
    taken = Set{String}()
    for (i, pane) in enumerate(panes)
        base = _identifier(pane.title)
        isempty(base) && (base = "pane")
        name = base
        k = 1
        while name in taken || name in ("editor", "window")
            k += 1
            name = base * string(k)
        end
        push!(taken, name)
        panes[i] = _Pane(pane.path, pane.title, pane.description, pane.share,
                         pane.tab, name)
    end
    panes
end

function _identifier(title::AbstractString)
    out = IOBuffer()
    break_pending = false
    for c in lowercase(title)
        if isletter(c) || isdigit(c)
            (break_pending && position(out) > 0) && print(out, '_')
            break_pending = false
            print(out, c)
        else
            break_pending = true
        end
    end
    text = String(take!(out))
    (isempty(text) || !isletter(first(text))) ? "pane" * text : text
end

function _build_node(node, path::String, names, indent::Int)
    if node isa PaneGroup
        items = [names[path * ".tabs[" * string(i) * "]"] for i in 1:length(node.tabs)]
        return "PaneGroup([" * join(items, ", ") * "])"
    end
    node isa PaneSplit || return "nothing"
    pad = " " ^ (indent + 4)
    children = [pad * _build_node(node.elements[i],
                                  path * ".elements[" * string(i) * "]", names, indent + 4)
                for i in 1:length(node.elements)]
    "PaneSplit(" * repr(node.orientation) * ", [\n" * join(children, ",\n") * "]" *
        _weights_text(node) * ")"
end

# The weights are printed only when the split carries them. An empty `weights`
# field means equal shares, and printing the numbers it would compute would write
# a document the person never made.
function _weights_text(split::PaneSplit)
    stored = split.weights
    length(stored) == 0 && return ""
    ", weights = [" * join((string(Float64(stored[i])) for i in 1:length(stored)), ", ") * "]"
end

# ── Saying a path back ──────────────────────────────────────────────────────

_path_text(path::Reference) = _path_text(get_reference_steps(path))
_path_text(steps::AbstractVector) =
    isempty(steps) ? "the whole tree" : rstrip(join(map(_step_text, steps), ""), '.')

_step_text(step::FieldReferenceStep) = "." * step.name
_step_text(step::RangeReferenceStep) =
    step.stop == step.start + 1 ? "[" * string(step.stop) * "]" :
    "[" * string(step.start + 1) * ", " * string(step.stop) * "]"
_step_text(step) = "." * string(step)

end # module PaneProgramModule
