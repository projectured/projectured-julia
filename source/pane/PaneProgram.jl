# Fragment of `PaneModule`.
#
# **The window's layout, as something a language model can read and change.**
#
# Three verbs read and write it. [`show_layout`](@ref) prints the pane tree as a
# Julia program, [`get_referenced_value`](@ref) answers the node a reference names,
# and [`replace_referenced_value!`](@ref) writes a new value at a reference. Two
# more do what a write cannot say: [`open_pane!`](@ref) puts a document in a new
# tab and answers a reference to it, and [`focus_pane!`](@ref) moves the focus,
# which is the selection and not a value in the tree.
#
# **The level is the reference, not the verb.** A replace at `root` rearranges the
# whole window; a replace at `root.elements[1]` moves one side of a split; a
# replace at `root.elements[1].tabs[1].content` changes what one pane holds; a
# replace at `root.weights` resizes a split. One verb reaches all of them, because
# a layout is a document and a reference names any part of one — which is why
# moving, resizing and closing a pane have no words of their own.
#
# **A pane is named by reference, never by title.** A reference names any part of
# any document; a title names a tab, and two tabs can carry one title. So every
# verb here takes a reference, and the verbs that place something answer one.
#
# # What the model reads
#
# `show_layout` answers the program that rebuilds the window as it stands:
#
# ```julia
# window = get_window_tree(editor)
#
# runner    = get_referenced_value(editor, @reference(window, root.elements[1].tabs[1]))   # Runner — the run form
# assistant = get_referenced_value(editor, @reference(window, root.elements[2].tabs[1]))   # Assistant — this conversation
#
# replace_referenced_value!(editor, @reference(window, root),
#     PaneSplit(:vertical, [
#         PaneGroup([runner]),
#         PaneGroup([assistant])], weights = [0.3, 0.7]))
# ```
#
# **A reference is written against the window**, which is what the first line binds.
# `@reference(window, path)` fills in the type of every node from the tree itself,
# so a path needs no `::T` spelled by hand and is wrong at once rather than later
# when it names a node that is not there.
#
# Paste it back unchanged and the window does not move. A model that wants a change
# therefore edits the text it was given — it swaps two names, changes a weight, or
# puts two names in one `PaneGroup` — rather than composing a program out of a
# docstring. And each name binds the `PaneTab` object that is already there, so the
# tree that is written holds the same tabs and no pane re-prints.
#
# # The numbering
#
# `[…]` counts elements, from 1: `root.elements[1].tabs[2]` is the second tab of
# the first group, and `tabs[2, 3]` is the second and third tabs together. That is
# the whole of what a caller needs to know.
#
# # What else the model may write
#
# A layout is written with `PaneSplit`, `PaneGroup`, `GridLayout` and `@reference`,
# and this module exports none of them — [`make_pane_api`](@ref) declares them **by
# name** instead. A declaration is not an export, so each of those names still has
# exactly one owning module, and the program says them plainly.
#
# Their modules are not declared, and that is the point. `@document` exports about
# thirty generated schema variants per document type — `APaneSplit`, `ACPaneSplit`,
# `DCPaneSplit`, each with no documentation of its own. Declared whole,
# `PaneModule` and `ReferenceModule` take the surface from 10 names to 122, and a
# search for "what panes are open" then answers with those variants instead of
# `show_layout`. Measured, not feared.
#
# `GridLayout` is what one pane holds several documents with: `GridLayout(cells, 2)`
# written at a tab's `.content` puts four plots in a pane in two rows, with one tab
# strip over them rather than four.
#
# # Adding a description
#
# [`describe_document`](@ref) is the one line the program's comment carries
# for a pane. Write a method for each document this window can show, beside the
# ones below.
# The pane package binds it, so a layout costs this package no dependency of its
# own and the window's closure is what it was.


"""
    make_pane_api() -> Vector

What a model needs declared to write the program [`show_layout`](@ref) prints:
this module's verbs, and the borrowed names the program says.

The borrowed ones are listed **by name**. Their modules export far more than a
layout needs, and a declared module puts every one of its exported names in the
model's search — this module's own documentation says what that costs.
"""
make_pane_api() = Any[
    # The verbs and not the module: `make_pane_api` builds this very list, and a model
    # has no use for the function that builds its own surface.
    # `get_document_title` is not declared either: a caller names a pane by
    # passing `title`, and what a document calls itself is `open_pane!`'s
    # business, not something to be asked separately.
    #
    # `describe_document` is here because it is two things at once — the
    # extension point `show_layout` writes its comments with, and the sentence a
    # caller asks about a value it holds: how far a set of runs has got, whether
    # that set is in a pane or in a hand.
    PaneModule => (:show_layout, :get_window_tree, :get_referenced_value,
                          :replace_referenced_value!, :open_pane!, :focus_pane!,
                          :duplicate_pane!, :describe_document),
    PaneModule      => (:PaneTree, :PaneSplit, :PaneGroup, :PaneTab),
    LayoutModule    => (:GridLayout, :HorizontalLayout, :VerticalLayout,
                        :FlowLayout, :StackLayout),
    ReferenceModule => (Symbol("@reference"),),
]

"""
    make_interface_api() -> Vector

What a model needs declared to build what a pane shows: the widgets a person
asks for by name, the policies a layout sizes a child with, and the two geometry
values a widget takes. The layouts are in [`make_pane_api`](@ref), because the
layout program says them.

Every name is listed, as `make_pane_api` lists its borrowed ones. `WidgetModule`
exports about a hundred names, and most of them are projections, operations and
readers a model has no use for; a search for "a card around the plot" must answer
`WidgetCard` and not `WidgetCardToGraphicsCanvas`.
"""
make_interface_api() = Any[
    WidgetModule => (
        # What holds other widgets.
        :WidgetCard, :WidgetTitlePane, :WidgetTabbedPane, :WidgetSplitPane,
        :WidgetScrollPane, :WidgetAccordion, :WidgetComposite,
        # What shows a value.
        :WidgetLabel, :WidgetText, :WidgetTextarea, :WidgetTable, :WidgetBadge,
        :WidgetAlert, :WidgetProgress, :WidgetSeparator,
        # What a person acts on.
        :WidgetButton, :Action, :WidgetCheckbox, :WidgetSwitch, :WidgetToggleGroup,
        :WidgetRadioGroup, :WidgetSelect, :WidgetSlider, :WidgetSpinBox, :WidgetList,
        # A position or a size, and a spacing.
        :Point2D, :Inset),
    # How a layout sizes a child on an axis.
    LayoutModule => (:Fixed, :Content, :Relative, :Fill),
]

# ── The window a verb acts on ───────────────────────────────────────────────

"""
    get_window_tree(editor) -> PaneTree

The pane tree the editor shows.

Use it to read the whole pane tree when no verb answers the part you need, and
to write a reference against it with `@reference`.

# Example

    tree = get_window_tree(editor)
    println(length(get_pane_groups(tree)), " groups")

See also `show_layout`, which prints the tree with its references.

A running editor draws a screen of windows, and a headless caller — a test, a
workload — holds the tree itself. Both arrive at a verb, so both are read. A
window whose content a clipboard wraps holds the tree inside the clipboard.
`document.windows`, not `getfield`: the field holds a cell and the property is
what reads through it.
"""
get_window_tree(tree::PaneTree) = tree

function get_window_tree(editor)
    hasfield(typeof(editor), :document) || return _get_wrapped_window_tree(editor)
    document = getfield(editor, :document)
    document isa PaneTree && return document
    hasproperty(document, :windows) || return _get_wrapped_window_tree(document)
    windows = document.windows
    isempty(windows) && error("The editor shows no window.")
    get_window_tree(first(windows).content)
end

# A content that is wrapped — a history, say — holds the tree inside the wrapper.
# A node that wraps nothing holds no tree at all, and that is what to say.
function _get_wrapped_window_tree(node)
    wrapped = get_wrapped_document(node)
    wrapped === node &&
        error("A " * String(nameof(typeof(node))) * " holds no pane tree.")
    get_window_tree(wrapped)
end

# ── What a pane holds ───────────────────────────────────────────────────────

"""
    describe_document(document) -> String

One short line saying what a document is.

Use it to ask what a value is or how far it has come — how many runs a set holds
and how many are done, what a study holds, what a table shows — in one sentence,
without opening anything.

# Example

    println(describe_document(batch))

See also `show_layout`, which says it for every pane.

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

**The default takes an untyped argument on purpose.** An application writes
`pane_group_to_avoid(tree::PaneTree)`, and a default of that same signature would
be overwritten rather than added to — which Julia refuses outright while it
precompiles.
"""
pane_group_to_avoid(tree) = nothing

"""
    open_pane!(editor, document; title = nothing) -> Reference

Put `document` in a new tab, and answer a reference to the tab it made.

Use it to show, display or place a value on the screen: a table, a plot, a set
of runs, a layout of widgets, any document, in a tab of its own beside what is
open. It answers the reference of the new tab, which the other pane verbs take.

# Example

    reference = open_pane!(editor, make_result_plot(frame); title = "Delay")
    focus_pane!(editor, reference)

See also `focus_pane!`, `replace_referenced_value!` to close or change a pane,
`show_layout`.

**This is the placement verb of a new document.** Everything else a layout can
be asked for — move a pane, resize a split, close a tab, change what a pane
holds — is [`replace_referenced_value!`](@ref) at a reference, and the program
[`show_layout`](@ref) prints is the text to edit. What a replace cannot say
without naming a group by hand is *where a new pane goes*, and that policy is
this verb: the focused group, and never the one
[`pane_group_to_avoid`](@ref) names. [`duplicate_pane!`](@ref) places a
duplicate beside its original, by the same policy when the original is in that
group.

**It answers a reference, not a title.** A reference names any part of any
document and a title names a tab, so the reference is what the next call takes:

```julia
where = open_pane!(editor, chart)
focus_pane!(editor, where)
replace_referenced_value!(editor, where, PaneTab(other, "something else"))
```

`title` is what the tab is called. Left out, the document's own
[`get_document_title`](@ref) answers, and a document that carries no name falls
back to [`describe_document`](@ref). A title already taken gets a number, so two
panes are never one name, and the name is for a person to read rather than for a
caller to address the pane by.

`group` is a group of the window to open the tab in. Left out, the policy above
chooses one. An application uses it when it knows better than the focus, for
example to put a file that a navigator opens beside the other files.
"""
function open_pane!(editor, document; title = nothing, group = nothing)
    tree = get_window_tree(editor)
    group === nothing && (group = _find_placement_group(tree))
    any(g -> g === group, get_pane_groups(tree)) ||
        error("open_pane!: the group is not a group of this window.")

    # What the pane is called: what the caller said, else the name the document
    # carries, else what it is. A description is the last resort, because it
    # names the document's state and a tab must not rename itself.
    wanted = title !== nothing ? String(title) :
             let own = get_document_title(document)
                 own !== nothing && !isempty(strip(String(own))) ? String(own) :
                     describe_document(document)
             end
    name = _unique_pane_title(tree, wanted)
    tab = PaneTab(name, document)
    operation = make_pane_open_tab_operation(tree, group, tab)
    operation === nothing && error("The window has no group to open a pane in.")
    apply_pane_operation!(tree, operation)
    reference = _reference_of_tab(tree, tab)
    reference === nothing &&
        error("The pane was opened and then could not be found again.")
    reference
end

# The group a new pane goes to: the focused group, and never the one
# `pane_group_to_avoid` names while another group exists.
function _find_placement_group(tree::PaneTree)
    groups = get_pane_groups(tree)
    isempty(groups) && error("The window has no group to open a pane in.")
    avoid = pane_group_to_avoid(tree)
    elsewhere = avoid === nothing ? groups : [g for g in groups if g !== avoid]
    isempty(elsewhere) && (elsewhere = groups)
    group = get_pane_focused_group(tree)
    (group === nothing || !(group in elsewhere)) && (group = first(elsewhere))
    group
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

Use it to read what a pane holds — a set of runs, a plot, a table, a card — by
the reference `show_layout` printed or `open_pane!` answered, so that you can
act on it: stop the set, add a series to the plot, ask the table how many rows
it has.

# Example

    plot = get_referenced_value(editor, @reference(window, root.elements[2].tabs[1].content))
    println(describe_document(plot))

See also `show_layout`, `replace_referenced_value!`.

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

Use it to change the layout: move a pane beside another in a split, resize a
split by its weights, close a tab, or replace what a pane holds, by writing a
value at a reference `show_layout` printed. One call, one undo.

# Example

    show_layout(editor)
    replace_referenced_value!(editor, @reference(window, root.elements[1].tabs[2, 2]), [])

See also `open_pane!` to add a pane, `focus_pane!`, `PaneSplit`, `PaneGroup`,
`PaneTab`.

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
    focus = get_pane_focus(tree)
    (focus === nothing || focus[2] == 0) ? nothing : focus[1].tabs[focus[2]]
end

_shown_tabs(tree::PaneTree) =
    Any[group.tabs[get_pane_shown_tab_index(group)]
        for group in get_pane_groups(tree) if length(group.tabs) > 0]

function _restore_shown!(tree::PaneTree, shown)
    for group in get_pane_groups(tree)
        n = length(group.tabs)
        n == 0 && continue
        index = findfirst(i -> any(t -> t === group.tabs[i], shown), 1:n)
        index === nothing && continue
        replace_selection!(group, @reference(group, tabs[index]))
    end
end

function _restore_focus!(tree::PaneTree, focused)
    focused === nothing && return
    for group in get_pane_groups(tree)
        for i in 1:length(group.tabs)
            group.tabs[i] === focused || continue
            apply_pane_operation!(tree, make_pane_focus_operation(tree, group, i))
            return
        end
    end
end

# ── The focus ───────────────────────────────────────────────────────────────
#
# Focus is one of the two acts that are not a value written at a reference; the
# duplicate below is the other. Moving a pane, resizing a split and closing a tab
# all are, and `replace_referenced_value!` says them from the program
# `show_layout` prints — one verb for every level, which is what keeps a new kind
# of change from needing a new word.

"""
    focus_pane!(editor, reference::Reference) -> Text

Show the pane `reference` names and give it the focus, and answer the window's
new program.

Use it to bring a pane to the front, select its tab, or show the person a pane
that is open behind another.

# Example

    focus_pane!(editor, @reference(window, root.elements[1].tabs[2]))

See also `open_pane!`, `show_layout`.

**Focus is a thing a replace cannot say.** A change to a layout is a value
written at a reference — a pane moved, a split resized, a tab closed, what a
pane holds — and [`replace_referenced_value!`](@ref) is that verb. Focus is not
a value in the tree; it is the selection, which is why it keeps a word of its
own. [`duplicate_pane!`](@ref) is the other word.

The reference is what [`open_pane!`](@ref) answered, or one the program
[`show_layout`](@ref) printed.
"""
function focus_pane!(editor, reference::Reference)
    tree = get_window_tree(editor)
    _refuse_stale(reference)
    group, index = _pane_referenced(tree, reference)
    operation = make_pane_focus_operation(tree, group, index)
    operation === nothing &&
        throw(ArgumentError("The window can not focus that pane."))
    apply_pane_operation!(tree, operation)
    show_layout(editor)
end

# Which group holds the tab a reference names, and where in it. By identity: a
# reference resolves to the tab object, and the tab object is in exactly one
# group however the tree was rearranged since.
function _pane_referenced(tree::PaneTree, reference::Reference)
    tab = evaluate_reference(tree, reference)
    tab isa PaneTab ||
        throw(ArgumentError("That reference names " *
                            (tab === nothing ? "nothing" :
                             "a " * String(nameof(typeof(tab)))) *
                            " and not a pane."))
    for group in get_pane_groups(tree), index in 1:length(group.tabs)
        group.tabs[index] === tab && return (group, index)
    end
    throw(ArgumentError("That pane is no longer in the window."))
end

# ── The duplicate ───────────────────────────────────────────────────────────

"""
    duplicate_pane!(editor, reference::Reference) -> Reference

Make a second pane like the one `reference` names, and answer a reference to
the new pane.

Use it to duplicate, copy or clone a pane: another plot like this one, a second
runner, or another assistant that knows this conversation. The duplicate is a
pane the person controls on its own. It owns what they can change in it, and it
reads what the original reads.

# Example

    second = duplicate_pane!(editor, @reference(window, root.elements[2].tabs[1]))
    focus_pane!(editor, second)

See also `open_pane!`, `focus_pane!`, `show_layout`.

**A duplicate is a thing a replace cannot say.** A replace writes a value the
caller made, and a correct duplicate is not a value a caller can make: a copy of
a pane can share an action with the original and act on it. The kind of the
content decides what its duplicate owns.

The duplicate is the next tab of the original's group, with the focus. When that
group is the one [`pane_group_to_avoid`](@ref) names, the duplicate goes where
[`open_pane!`](@ref) puts a pane, so the conversation stays in view. A pane
whose content has no duplicate, such as a set of runs that goes on, raises an
`ArgumentError` that says why.
"""
function duplicate_pane!(editor, reference::Reference)
    tree = get_window_tree(editor)
    _refuse_stale(reference)
    group, index = _pane_referenced(tree, reference)
    source = group.tabs[index]
    duplicate = try
        _make_pane_tab_duplicate(tree, source)
    catch e
        e isa DocumentCopyException || rethrow()
        throw(ArgumentError("A $(nameof(typeof(source.content))) pane has no duplicate: " *
                            _format_duplicate_refusal(source.content, e) * "."))
    end
    target = group === pane_group_to_avoid(tree) ? _find_placement_group(tree) : group
    operation = target === group ?
        make_pane_open_tab_operation(tree, group, duplicate; index = index + 1) :
        make_pane_open_tab_operation(tree, target, duplicate)
    operation === nothing && error("The window has no group to open the duplicate in.")
    apply_pane_operation!(tree, operation)
    found = _reference_of_tab(tree, duplicate)
    found === nothing &&
        error("The duplicate was opened and then could not be found again.")
    found
end


# ── The program ─────────────────────────────────────────────────────────────

"""
    show_layout(editor) -> Text

Which panes are open, where each one sits and what it holds, as the Julia
program that rebuilds the window.

Use it to see the layout of the window — its splits, its groups, the tabs of
each group and what each holds — with the reference of every part, before you
move, close, replace, focus or duplicate a pane. It answers the layout as a program, so a
`replace_referenced_value!` at one of its references edits it.

# Example

    show_layout(editor)

See also `get_referenced_value`, `replace_referenced_value!`, `focus_pane!`.

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
# from the weights alone — `get_pane_rectangles` walks the tree and divides the unit
# square — so it needs no printed window and no measurement. A group that has all
# of both axes says nothing, because "100% × 100%" on every line of a one-pane
# window is noise.
function _pane_shares(tree::PaneTree)
    shares = Dict{PaneGroup,String}()
    for (group, rectangle) in get_pane_rectangles(tree)
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
            title = get_pane_tab_title_string(tab)
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
