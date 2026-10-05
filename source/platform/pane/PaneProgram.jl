# Fragment of `PaneModule`.
#
# **The window's layout, as something a language model can read and change.**
#
# [`show_layout`](@ref) prints the layout as a tree of reference steps: one line
# for each window, pane tree, split, group and tab, with the type of the node it
# reaches and a note on what it is. The path of a part is the steps of the lines
# on its branch, from the root of the editor's document.
#
# **A verb for each common change.** [`focus_pane!`](@ref), [`open_pane!`](@ref),
# [`duplicate_pane!`](@ref), [`close_pane!`](@ref) and [`move_pane!`](@ref) each
# do what a person does with a pane, and [`find_pane_reference`](@ref) names the
# pane by its title, so a model writes no path for them. A change that has no
# verb — the weights of a split, what a pane holds, a new arrangement of the
# whole window — is [`replace_referenced_value!`](@ref) at a path read off the
# tree, and [`get_referenced_value`](@ref) reads the node at one.
#
# **Every reference is complete.** It starts at the root of the editor's
# document. A verb finds its pane tree from the reference it gets, so no verb
# assumes one window or one tree. A verb reads its edit through the readers of the
# editor (`read_rooted_operation`) and evaluates it at once, so every document on
# the path of the selection holds its part of one path. Each verb has a
# `make_…_operation` that reads the edit and evaluates nothing, for a caller that
# posts it with [`post_pane_operation!`](@ref).
#
# **A pane has two names.** Its reference names any part of any document; its
# title is what a person says. `find_pane_reference` turns a title into a
# reference, and when two tabs have one title it says so rather than choose.
#
# # The numbering
#
# `[…]` counts elements, from 1: `root.elements[1].tabs[2]` is the second tab of
# the first group, and `tabs[2, 3]` is the second and third tabs together. That is
# the whole of what a caller needs to know.
#
# # What else the model may write
#
# A layout is written with `PaneSplit`, `PaneGroup`, `GridLayout` and `@reference`.
# `PaneSplit` and `PaneGroup` are this module's own types; `GridLayout` and
# `@reference` belong to `LayoutModule` and `ReferenceModule` — and
# [`make_pane_api`](@ref) declares all four **by name** to the model rather than
# declaring any of their modules whole. A declaration is not an export, so each
# of those names still has exactly one owning module.
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
# [`describe_document`](@ref) is the note that a line of the layout carries for
# what a pane holds. Write a method for each document this window can show,
# beside the ones below.
# The pane package binds it, so a layout costs this package no dependency of its
# own and the window's closure is what it was.


"""
    make_pane_api() -> Vector

What a model needs declared to read the layout that [`show_layout`](@ref) prints
and to change it: this module's verbs, and the borrowed names a write at a path
of the layout uses.

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
    # extension point `show_layout` writes its notes with, and the sentence a
    # caller asks about a value it holds: how far a set of runs has got, whether
    # that set is in a pane or in a hand.
    #
    # `get_window_tree` is not declared: it answers the first window's tree, and
    # a model names a part by a complete reference from the root.
    PaneModule => (:show_layout, :get_referenced_value, :replace_referenced_value!,
                          :open_pane!, :focus_pane!, :close_pane!, :move_pane!,
                          :duplicate_pane!, :find_pane, :find_pane_reference,
                          :find_pane_tree_reference, :describe_document),
    PaneModule      => (:PaneTree, :PaneSplit, :PaneGroup, :PaneTab),
    LayoutModule    => (:GridLayout, :HorizontalLayout, :VerticalLayout,
                        :FlowLayout, :StackLayout),
    # `find_pane` answers a referenced document, and `get_edited_document` reaches
    # the document a tab shows through it.
    ReferenceModule => (Symbol("@reference"), :ReferencedDocument, :get_document,
                        :get_reference, :DocumentLocator, :find_referenced_document,
                        :get_edited_document, :get_parent),
]

"""
    make_interface_api() -> Vector

What a model needs declared to build what a pane shows: the widgets a person
asks for by name, the policies a layout sizes a child with, and the two geometry
values a widget takes. The layouts are in [`make_pane_api`](@ref), because a
write at a path of the layout uses them.

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

The pane tree of the editor's first window.

Use it where code holds one window and needs its tree object. A reference that a
verb takes starts at the root of the editor's document, not at this tree:
[`find_pane_tree_reference`](@ref) answers the reference of the tree that holds
the focus, and [`show_layout`](@ref) prints the path of every part.

# Example

    tree = get_window_tree(editor)
    println(length(get_pane_groups(tree)), " groups")

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
    # The screen can be inside wrappers, such as the state of a tracker.
    screen = get_wrapped_document(document)
    hasproperty(screen, :windows) || return _get_wrapped_window_tree(document)
    windows = screen.windows
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
describe_document(x::ReferencedDocument) = describe_document(get_document(x))
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
    open_pane!(editor, document; title = nothing, target = nothing, side = nothing,
               group = nothing) -> ReferencedDocument

Put `document` in a new tab, and answer the tab it made, as a `ReferencedDocument`.

Use it to show, display or place a value on the screen: a table, a plot, a set
of runs, a layout of widgets, any document, in a tab of its own: in the group of
another tab, in a new pane beside or under one group, or in the group that has the
focus. It answers the new tab with its reference, which the other pane verbs take.

# Example

    delay_tab_1 = open_pane!(editor, make_result_plot(frame); title = "Delay")
    runs_tab_1 = open_pane!(editor, runs; title = "Runs", target = delay_tab_1, side = :below)
    focus_pane!(editor, delay_tab_1)

See also `focus_pane!`, `replace_referenced_value!` to close or change a pane,
`show_layout`.

**This is the placement verb of a new document.** The other verbs change a
layout that exists: [`focus_pane!`](@ref), [`move_pane!`](@ref) and
[`close_pane!`](@ref), and [`replace_referenced_value!`](@ref) at a reference for
what no verb says, such as the weights of a split. What they cannot say without
naming a group by hand is *where a new pane goes*, and that policy is this verb:
the focused group, never the one [`pane_group_to_avoid`](@ref) names, and never
a group with a tab that declines [`accepts_opened_file`](@ref), such as an
explorer, while another group exists. [`duplicate_pane!`](@ref) places a
duplicate beside its original, by the same policy when the original is in that
group.

**It answers the tab and its reference, not a title.** A reference names any part
of any document and a title names a tab, so the referenced tab is what the next
call takes, and `get_reference` gives its reference:

```julia
chart_tab_1 = open_pane!(editor, chart)
focus_pane!(editor, chart_tab_1)
replace_referenced_value!(editor, chart_tab_1, PaneTab(other, "something else"))
```

`title` is what the tab is called: a string, or a [`PaneTabTitle`](@ref) whose
icon, badges and tooltip the tab shows beside the name. Left out, or a title with
an empty name, the document's own [`get_document_title`](@ref) answers, and a
document that carries no name falls back to [`describe_document`](@ref). A name
already taken gets a number, so two panes are never one name, and the name is for
a person to read rather than for a caller to address the pane by.

`target` is where the tab goes, as [`move_pane!`](@ref) places a pane: a group,
and the tab goes to its end; or a tab, and the new tab goes before it, in the same
group. It is a `Reference` or a `ReferencedDocument`, such as a tab that
`find_pane` found or the group that `get_parent` answers for it. Left out, the
policy above chooses a group in the pane tree that holds the focus.

`side` — `:left`, `:right`, `:above` or `:below` — puts the tab in a new group next
to the one group that `target` is or holds. A new split takes the place of that
group and holds the two groups, each with half of its place; when the split that
holds the group already runs in that direction, the new group joins that split
next to the group instead, and takes half of the group's place. The new group is
always next to one group: a pane beside or under several groups at once is not a
placement `open_pane!` makes.

`group` is a group of the window to open the tab in, as a value and not as a
reference. An application uses it when it knows better than the focus, for
example to put a file that a navigator opens beside the other files. `group` and
`target` together are refused.

The answer holds the new tab and its complete reference, from the root of the
editor's document.
"""
function open_pane!(editor, document; title = nothing, group = nothing, target = nothing,
                    side = nothing)
    operation, route, tree, tab = _make_open_pane(editor, document; title, group, target, side)
    _evaluate_pane_operation!(editor, operation)
    reference = _reference_of_tab(tree, tab)
    reference === nothing &&
        error("The pane was opened and then could not be found again.")
    ReferencedDocument(tab, concat_references(route, reference))
end

open_pane!(editor, document::ReferencedDocument; keywords...) =
    open_pane!(editor, get_document(document); keywords...)

"""
    make_open_pane_operation(editor, document; title = nothing, group = nothing,
                             target = nothing, side = nothing) -> Operation

The operation that puts `document` in a new tab, as [`open_pane!`](@ref) places
it, from the root of the editor's document. It evaluates nothing: a caller that
runs inside another evaluation posts it with `post_operation!`.
"""
make_open_pane_operation(editor, document; title = nothing, group = nothing, target = nothing,
                         side = nothing) =
    first(_make_open_pane(editor, document; title, group, target, side))

# A title like `title` with the name `name`: the same cells for its other parts,
# so the tab follows what they follow.
_make_named_title(title::PaneTabTitle, name::AbstractString) =
    PaneTabTitle(name; icon = getfield(title, :icon), icon_role = getfield(title, :icon_role),
                 badges = getfield(title, :badges), tooltip = getfield(title, :tooltip))

function _make_open_pane(editor, document; title, group, target, side)
    (group === nothing || target === nothing) ||
        throw(ArgumentError("open_pane!: give `group` or `target`, not both."))
    (side === nothing || side in (:left, :right, :above, :below)) ||
        throw(ArgumentError("open_pane!: `side` is :left, :right, :above or :below."))
    root = _get_root_document(editor)
    index = nothing
    if target !== nothing
        route, tree, group, index = _find_open_target(root, convert(Reference, target))
    else
        found = group === nothing ? _find_focused_tree_route(editor) :
                                    _find_group_tree_route(root, group)
        found === nothing &&
            error("open_pane!: no pane tree has the focus, so name the group to open in.")
        route, tree = found
        group === nothing && (group = _find_placement_group(tree))
    end
    any(g -> g === group, get_pane_groups(tree)) ||
        error("open_pane!: the group is not a group of this window.")

    # What the pane is called: what the caller said, else the name the document
    # carries, else what it is. A description is the last resort, because it
    # names the document's state and a tab must not rename itself.
    given = title isa PaneTabTitle ? something(title.name.value, "") : title
    (title isa PaneTabTitle && isempty(given)) && (given = nothing)
    wanted = given !== nothing ? String(given) :
             let own = get_document_title(document)
                 own !== nothing && !isempty(strip(String(own))) ? String(own) :
                     describe_document(document)
             end
    name = _unique_pane_title(tree, wanted)
    tab = PaneTab(title isa PaneTabTitle ? _make_named_title(title, name) : PaneTabTitle(name), document)
    placement = side === nothing ? make_pane_open_tab_operation(tree, group, tab; index) :
                make_pane_split_operation(tree, group; tab, side,
                                          orientation = side in (:left, :right) ? :vertical : :horizontal)
    operation = _make_rooted_pane_operation(editor, route, tree, placement,
                                            "Open the pane " * name)
    operation === nothing && error("The window has no group to open a pane in.")
    (operation, route, tree, tab)
end

# The pane tree, the group and the index in it that `target` names: a group, at
# its end, or a tab, at its place.
function _find_open_target(root, target::Reference)
    found = _find_pane_tree_route(root, target)
    found === nothing &&
        throw(ArgumentError("open_pane!: the target names nothing inside a pane tree."))
    route, tree = found
    destination = try_evaluate_reference(root, target, nothing)
    destination isa PaneTab && return (route, tree, _find_pane_position(tree, destination)...)
    (destination isa PaneGroup && any(g -> g === destination, get_pane_groups(tree))) ||
        throw(ArgumentError("open_pane!: the target names no group or tab of the pane's tree."))
    (route, tree, destination, nothing)
end

# The group a new pane goes to: the focused group, and never the one
# `pane_group_to_avoid` names while another group exists. Of the rest, only a
# group every tab of which `accepts_opened_file` while one exists, so a pane
# opened with the focus in an explorer goes beside the files, as a file does.
function _find_placement_group(tree::PaneTree)
    groups = get_pane_groups(tree)
    isempty(groups) && error("The window has no group to open a pane in.")
    avoid = pane_group_to_avoid(tree)
    elsewhere = avoid === nothing ? groups : [g for g in groups if g !== avoid]
    isempty(elsewhere) && (elsewhere = groups)
    free = [g for g in elsewhere if _is_free_group(g)]
    isempty(free) || (elsewhere = free)
    group = get_pane_focused_group(tree)
    (group === nothing || !(group in elsewhere)) && (group = first(elsewhere))
    group
end

"""
    _reference_of_tab(tree, tab) -> Reference or nothing

Where `tab` sits in `tree`, as a typed path from the tree; a verb puts the
route to the tree in front of it to answer a complete reference.

Built by identity and then annotated against the tree, which is what
`@reference(tree, path)` does at its call site: every node records the type of
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

The node `reference` names, resolved from the root of the editor's document.

Use it to read what a pane holds — a set of runs, a plot, a table, a card — by
the reference `show_layout` printed, `open_pane!` answered or
`find_pane_reference` found, so that you can act on it: stop the set, add a
series to the plot, ask the table how many rows it has.

`reference` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers.

# Example

    plot = get_referenced_value(editor, find_pane_reference(editor, "Delay"))
    println(describe_document(plot.content))

See also `show_layout`, `find_pane_reference`, `replace_referenced_value!`.

The reference is complete: it starts at the root of the editor's document. A
caller that holds a tree and no editor passes the tree, and a reference from
the tree.

Throws when the path reaches nothing, naming the path, because a path that no
longer resolves is a layout that moved under the caller.
"""
function get_referenced_value(editor, reference::Reference)
    root = _get_root_document(editor)
    _refuse_stale(reference)
    path = strip_reference_types(reference)
    node = try
        evaluate_reference(root, path)
    catch error
        throw(ArgumentError("No node at " * _path_text(path) * ": " * sprint(showerror, error)))
    end
    node === nothing && throw(ArgumentError("No node at " * _path_text(path) * "."))
    node
end

get_referenced_value(editor, reference::ReferencedDocument) =
    get_referenced_value(editor, get_reference(reference))

# ── Writing ─────────────────────────────────────────────────────────────────

"""
    replace_referenced_value!(editor, reference, value) -> Text

Put `value` where `reference` points, and answer the new layout, as
[`show_layout`](@ref) prints it.

Use it to change the layout: move a pane beside another in a split, resize a
split by its weights, or replace what a pane holds, by writing a value at a
reference `show_layout` printed. One call, one undo. To close a pane, use
[`close_pane!`](@ref).

`reference` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers, and `value` can be one too: its document is written.

# Example

    tree_reference = find_pane_tree_reference(editor)
    tree = evaluate_reference(editor.document, tree_reference)
    replace_referenced_value!(editor, concat_references(tree_reference, @reference(tree, root.weights)),
                              [0.3, 0.7])

See also `open_pane!` to add a pane, `focus_pane!`, `PaneSplit`, `PaneGroup`,
`PaneTab`.

The reference is complete: it starts at the root of the editor's document. A
path written by hand is typed against the tree with `@reference(tree, …)`, and
put after the path to the tree with `concat_references`.

This is one `ReplaceReferencedValueOperation`, so the person undoes it with one
press. A reference whose last step is a range **splices**: replacing
`root.elements[1].tabs[2, 3]` with a vector of tabs writes those two tabs, and
with `[]` removes them.

```julia
replace_referenced_value!(editor, concat_references(tree_reference, @reference(tree, root)),
                          PaneSplit(:vertical, [a, b], weights = [0.3, 0.7]))
replace_referenced_value!(editor, concat_references(tree_reference,
                                                    @reference(tree, root.elements[1].tabs[1].content)),
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
    _refuse_stale(reference)
    root = _get_root_document(editor)
    found = _find_pane_tree_route(root, reference; below = true)
    found === nothing &&
        throw(ArgumentError("The path " * _path_text(strip_reference_types(reference)) *
                            " names nothing inside a pane tree."))
    route, tree = found
    path = _get_path_in_tree(reference, route)
    _refuse_bad_write(tree, path, value)

    focused = _focused_tab(tree)
    shown = _shown_tabs(tree)
    operation = _make_deepest_pane_write(editor, reference, route, tree, path, value,
                                         "Replace " * describe_reference(reference, root))
    operation === nothing && throw(ArgumentError("The window did not take the write."))
    _evaluate_pane_operation!(editor, operation)
    _restore_shown!(tree, shown)
    _restore_focus!(editor, route, tree, focused)
    show_layout(editor)
end

replace_referenced_value!(editor, reference::ReferencedDocument, value) =
    replace_referenced_value!(editor, get_reference(reference), value)
replace_referenced_value!(editor, reference::Reference, value::ReferencedDocument) =
    replace_referenced_value!(editor, reference, get_document(value))

# The steps of `reference` after the route to its tree, as a path from the tree.
# The write rooted at the deepest place the readers carry it from, so a history
# inside a tab records an edit of the tab's content as it records an edit of the
# person; at the tree, when no place below it takes the write, as for a write into
# the layout, and for a root that has no readers.
function _make_deepest_pane_write(editor, reference, route, tree, path, value, description)
    if editor isa Editor && editor.iomap !== nothing
        deep = find_rooted_operation(editor, reference,
                                     relative -> ReplaceReferencedValueOperation(nothing, relative, value);
                                     description)
        deep === nothing || return deep
    end
    _make_rooted_pane_operation(editor, route, tree, ReplaceReferencedValueOperation(nothing, path, value),
                                description)
end

function _get_path_in_tree(reference::Reference, route::Reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    skip = length(get_reference_steps(strip_reference_types(route)))
    foldr(ConcreteReference, steps[(skip + 1):end]; init = EmptyReference())
end

# What the tree can not accept, said before anything is written. The three cases
# are the ones a caller reaches by editing a path by hand: a reference that names
# no slot, a range past the end of its collection, and a node put where its kind
# does not belong.
# A reference typed against the tree — `@reference(tree, …)` — takes the type
# of every node from the tree it is written against. A node the tree does not
# have takes none, so a path that is not fully typed is a path that named
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

function _restore_focus!(editor, route, tree::PaneTree, focused)
    focused === nothing && return
    for group in get_pane_groups(tree)
        for i in 1:length(group.tabs)
            group.tabs[i] === focused || continue
            operation = _make_rooted_pane_operation(editor, route, tree,
                                                    make_pane_focus_operation(tree, group, i),
                                                    "Keep the focus on " * get_pane_tab_title_string(focused))
            operation === nothing || _evaluate_pane_operation!(editor, operation)
            return
        end
    end
end

# ── The focus ───────────────────────────────────────────────────────────────
#
# Focus is the selection and not a value in the tree, so it is a verb of its
# own and not a write at a reference.

"""
    focus_pane!(editor, reference::Reference) -> Text

Show the pane `reference` names and give it the focus, and answer the new
layout, as [`show_layout`](@ref) prints it.

Use it to bring a pane to the front, select its tab, or show the person a pane
that is open behind another.

`reference` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers.

# Example

    focus_pane!(editor, find_pane_reference(editor, "Files"))

See also `find_pane_reference`, `open_pane!`, `show_layout`.

**Focus is a thing a replace cannot say.** A change to a layout is a value
written at a reference — a pane moved, a split resized, a tab closed, what a
pane holds — and [`replace_referenced_value!`](@ref) is that verb. Focus is not
a value in the tree; it is the selection, which is why it keeps a word of its
own. [`duplicate_pane!`](@ref) is the other word.

The reference is complete: it starts at the root of the editor's document, and
[`find_pane_reference`](@ref) answers one. The focus is made through the readers
of the editor and evaluated at once, so every document from the root down holds
its part of the new selection. A caller that holds a tree and no editor passes
the tree, and a reference from the tree.
"""
function focus_pane!(editor, reference::Reference)
    _refuse_stale(reference)
    operation = make_focus_pane_operation(editor, reference)
    operation === nothing &&
        throw(ArgumentError("The window can not focus that pane."))
    _evaluate_pane_operation!(editor, operation)
    show_layout(editor)
end

focus_pane!(editor, pane::ReferencedDocument) = focus_pane!(editor, get_reference(pane))

focus_pane!(_, ::Nothing) =
    throw(ArgumentError("No pane has that name, so there is no pane to focus."))

"""
    make_focus_pane_operation(editor, reference::Reference) -> Operation | Nothing

The operation that gives the focus to the pane `reference` names, from the root
of the editor's document: made at the pane tree, and carried to the root by the
readers of the editor ([`read_rooted_operation`](@ref)). It evaluates nothing.
`nothing` when the window can not focus that pane.

See also `focus_pane!`, which makes it and evaluates it at once.
"""
function make_focus_pane_operation(editor, reference::Reference)
    root = _get_root_document(editor)
    found = _find_pane_tree_route(root, reference)
    found === nothing &&
        throw(ArgumentError("That reference names nothing inside a pane tree."))
    route, tree = found
    group, index = _find_pane_position(tree, try_evaluate_reference(root, reference, nothing))
    _make_rooted_pane_operation(editor, route, tree, make_pane_focus_operation(tree, group, index),
                                "Focus the pane " * get_pane_tab_title_string(group.tabs[index]))
end

"""
    find_pane_tree_reference(editor) -> Reference | Nothing

The complete reference, from the root of the editor's document, of the pane
tree that holds the focus: the nearest tree on the path of the root's
selection. When the focus is in no tree, the one tree of the window; `nothing`
when the window holds none, or more than one and the focus is in none.

Use it to write a path by hand: evaluate it for the tree, type the path against
the tree, and put the two together.

# Example

    tree_reference = find_pane_tree_reference(editor)
    tree = evaluate_reference(editor.document, tree_reference)
    groups = concat_references(tree_reference, @reference(tree, root.elements))
"""
function find_pane_tree_reference(editor)
    found = _find_focused_tree_route(editor)
    found === nothing ? nothing : first(found)
end

# The document that a complete reference starts at: the editor's document, or
# the tree itself for a caller that holds a tree.
_get_root_document(tree::PaneTree) = tree
_get_root_document(editor) = getfield(editor, :document)

# The route to the pane tree that holds what `reference` names, and that tree:
# the longest prefix of `reference` that ends at a `PaneTree`, so the nearest
# tree when one tree holds another in a tab. With `below`, the reference itself
# is not a candidate, so a write at a tree goes to the tree that holds it.
# `nothing` when no tree is on the path. It follows only the path it is given.
function _find_pane_tree_route(root, reference::Reference; below::Bool = false)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    for n in (length(steps) - (below ? 1 : 0)):-1:0
        prefix = foldr(ConcreteReference, steps[1:n]; init = EmptyReference())
        node = try_evaluate_reference(root, prefix, nothing)
        node isa PaneTree && return (annotate_reference_types(root, prefix), node)
    end
    nothing
end

# The route to the pane tree that holds the focus, and that tree; see
# `find_pane_tree_reference`.
function _find_focused_tree_route(editor)
    root = _get_root_document(editor)
    selection = get_selection(root)
    if selection !== nothing
        found = _find_pane_tree_route(root, selection)
        found === nothing || return found
    end
    trees = search_references(root, node -> node isa PaneTree; descend = is_pane_search_step)
    length(trees) == 1 || return nothing
    _find_pane_tree_route(root, only(trees))
end

# The route to the pane tree that holds `group`, and that tree.
function _find_group_tree_route(root, group::PaneGroup)
    found = search_references(root, node -> node === group; descend = is_pane_search_step)
    isempty(found) && error("The group is not a group of this window.")
    _find_pane_tree_route(root, first(found))
end

# A pane edit made at `tree`, as an operation from the root: carried there by the
# readers of the editor, or as it is when the tree is the root.
function _make_rooted_pane_operation(editor, route, tree, operation, description)
    (operation === nothing || tree === _get_root_document(editor)) && return operation
    read_rooted_operation(editor, route, operation; description)
end

# A pane edit, evaluated where its path starts: on the tree for a caller that
# holds the tree, else by the editor at the root.
_evaluate_pane_operation!(tree::PaneTree, operation) = apply_pane_operation!(tree, operation)
_evaluate_pane_operation!(editor, operation) = evaluate_operation(editor, operation)

"""
    post_pane_operation!(editor, operation) -> Nothing

Hand a pane edit from the root to the loop of `editor`, which evaluates it at
the top of its next frame. Code that runs while the editor evaluates another
operation, such as a menu command or the open of a file, uses it, so that one
evaluation does not run inside another. A caller that has no loop, such as a
test that holds the tree, gets the edit applied at once.
"""
post_pane_operation!(editor::Editor, operation) = (post_operation!(editor, operation); nothing)
post_pane_operation!(editor, operation) = (_evaluate_pane_operation!(editor, operation); nothing)

# Which group holds `tab`, and where in it. By identity: a reference resolves to
# the tab object, and the tab object is in exactly one group however the tree was
# rearranged since.
function _find_pane_position(tree::PaneTree, tab)
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

# ── Closing a pane ──────────────────────────────────────────────────────────

"""
    close_pane!(editor, reference::Reference) -> Text

Close the pane `reference` names, and answer the new layout, as
[`show_layout`](@ref) prints it.

Use it to close, remove or dismiss a pane, a tab or a document that is open.

`reference` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers.

# Example

    close_pane!(editor, find_pane_reference(editor, "Files"))

See also `find_pane_reference`, `open_pane!`, `show_layout`.

The reference is complete: it starts at the root of the editor's document. The
close is made through the readers of the editor and evaluated at once, as the
close button of the tab does it, so the person undoes it with one press.
"""
function close_pane!(editor, reference::Reference)
    _refuse_stale(reference)
    operation = make_close_pane_operation(editor, reference)
    operation === nothing && throw(ArgumentError("The window can not close that pane."))
    _evaluate_pane_operation!(editor, operation)
    show_layout(editor)
end

close_pane!(editor, pane::ReferencedDocument) = close_pane!(editor, get_reference(pane))

close_pane!(_, ::Nothing) =
    throw(ArgumentError("No pane has that name, so there is no pane to close."))

"""
    make_close_pane_operation(editor, reference::Reference) -> Operation | Nothing

The operation that closes the pane `reference` names, from the root of the
editor's document: made at the pane tree, and carried to the root by the
readers of the editor. It evaluates nothing. `nothing` when the window can not
close that pane.

See also `close_pane!`, which makes it and evaluates it at once.
"""
function make_close_pane_operation(editor, reference::Reference)
    root = _get_root_document(editor)
    found = _find_pane_tree_route(root, reference)
    found === nothing &&
        throw(ArgumentError("That reference names nothing inside a pane tree."))
    route, tree = found
    group, index = _find_pane_position(tree, try_evaluate_reference(root, reference, nothing))
    _make_rooted_pane_operation(editor, route, tree, make_pane_close_tab_operation(tree, group, index),
                                "Close the pane " * get_pane_tab_title_string(group.tabs[index]))
end

# ── Finding a pane ──────────────────────────────────────────────────────────

"""
    find_pane_reference(editor, title; descend = is_pane_search_step) -> Reference | Nothing

The complete reference, from the root of the editor's document, of the pane
whose title is `title`, in any window. `nothing` when no pane has that title.
When two panes have it, an `ArgumentError` names both, so the caller can choose.

Use it to name a pane for a verb.

# Example

    files = find_pane_reference(editor, "Files")
    focus_pane!(editor, files)

The search goes down only into the documents that can hold a pane
([`is_pane_search_step`](@ref)); `descend` names another rule.
"""
function find_pane_reference(editor, title::AbstractString; descend = is_pane_search_step)
    found = search_references(_get_root_document(editor),
                              node -> node isa PaneTab && get_pane_tab_title_string(node) == title;
                              descend)
    isempty(found) && return nothing
    length(found) == 1 && return only(found)
    throw(ArgumentError(string(length(found), " panes are called \"", title, "\": ",
                               join(string.(found), ", "), ". Name one of them by its reference.")))
end

"""
    find_pane(editor, title) -> ReferencedDocument or nothing

The tab whose title is `title`, in any window, together with its complete reference
from the root of the editor's document: a `ReferencedDocument` that acts like the
tab. `nothing` when no tab has that title; when two tabs have it, an
`ArgumentError` names both.

Use it to find a tab by its title: to read the data it shows with
[`get_edited_document`](@ref), to reach the group that holds it with
[`get_parent`](@ref), to open a new tab beside it with [`open_pane!`](@ref) and its
`target`, or to hand it to a verb that moves, focuses or closes it.

# Example

    items_tab_1 = find_pane(editor, "items.json")
    items_1 = get_edited_document(items_tab_1)       # the data the tab shows
    items_group_1 = get_parent(editor, items_tab_1)  # the group that holds the tab
"""
function find_pane(editor, title::AbstractString)
    reference = find_pane_reference(editor, title)
    reference === nothing && return nothing
    ReferencedDocument(get_referenced_value(editor, reference), reference)
end

"""
    is_pane_search_step(parent, child) -> Bool

Whether a search for a pane goes from `parent` into `child`. It goes into a
document that can hold a pane, and into nothing else:

- from a wrapper (a history, a clipboard, a shell), only towards the document it
  wraps, and never into its history, its stored copy or its bars;
- from a pane tab or a widget, only into a pane, a widget, a collection or a
  wrapper, and never into the title of a tab, which holds no pane;
- from any other document, into a document.

So it does not walk the content of a file, or the actions and the types that a
widget holds.
"""
function is_pane_search_step(parent, child)
    child isa Document || return false
    child isa PaneTabTitle && return false
    wrapped = get_wrapped_document(parent)
    if wrapped !== parent
        get_wrapped_document(child) === wrapped || return false
        return child !== wrapped || _can_hold_pane(child)
    end
    parent isa Union{PaneTab,WidgetDocument} && return _can_hold_pane(child)
    true
end

# A screen holds its panes in its windows, as `get_window_tree` reads it.
_can_hold_pane(document) =
    document isa Union{PaneDocument,WidgetDocument,CellVector} ||
    hasproperty(document, :windows) ||
    get_wrapped_document(document) !== document

# ── The duplicate ───────────────────────────────────────────────────────────

"""
    duplicate_pane!(editor, reference::Reference) -> ReferencedDocument

Make a second pane like the one `reference` names, and answer the new pane, as a
`ReferencedDocument`.

Use it to duplicate, copy or clone a pane: another plot like this one, a second
runner, or another assistant that knows this conversation. The duplicate is a
pane the person controls on its own. It owns what they can change in it, and it
reads what the original reads.

`reference` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers.

# Example

    delay_tab_2 = duplicate_pane!(editor, find_pane(editor, "Delay"))
    focus_pane!(editor, delay_tab_2)

See also `open_pane!`, `focus_pane!`, `find_pane_reference`, `show_layout`.

The reference it takes and the reference of the pane it answers are complete:
they start at the root of the editor's document.

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
    _refuse_stale(reference)
    operation, route, tree, duplicate = _make_duplicate_pane(editor, reference)
    _evaluate_pane_operation!(editor, operation)
    found = _reference_of_tab(tree, duplicate)
    found === nothing &&
        error("The duplicate was opened and then could not be found again.")
    ReferencedDocument(duplicate, concat_references(route, found))
end

duplicate_pane!(editor, pane::ReferencedDocument) = duplicate_pane!(editor, get_reference(pane))

"""
    make_duplicate_pane_operation(editor, reference::Reference) -> Operation

The operation that opens a duplicate of the pane `reference` names, as
[`duplicate_pane!`](@ref) places it, from the root of the editor's document. It
evaluates nothing.
"""
make_duplicate_pane_operation(editor, reference::Reference) =
    first(_make_duplicate_pane(editor, reference))

function _make_duplicate_pane(editor, reference::Reference)
    root = _get_root_document(editor)
    found = _find_pane_tree_route(root, reference)
    found === nothing &&
        throw(ArgumentError("That reference names nothing inside a pane tree."))
    route, tree = found
    group, index = _find_pane_position(tree, try_evaluate_reference(root, reference, nothing))
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
    operation = _make_rooted_pane_operation(editor, route, tree, operation,
                                            "Duplicate the pane " * get_pane_tab_title_string(source))
    operation === nothing && error("The window has no group to open the duplicate in.")
    (operation, route, tree, duplicate)
end


# ── Moving a pane ───────────────────────────────────────────────────────────

"""
    move_pane!(editor, reference::Reference, target::Reference; side = nothing) -> Text

Move the pane `reference` names to `target`, and answer the window's new layout.

Use it to move a tab to another group, to put it before another tab, or to put
it beside a group in a split of its own.

`reference` and `target` can also be a `ReferencedDocument`, such as the tab that
[`find_pane`](@ref) answers.

# Example

    move_pane!(editor, find_pane_reference(editor, "notes.txt"),
               find_pane_reference(editor, "Files"))

See also `show_layout`, `find_pane_reference`, `close_pane!`.

`target` names a group, and the pane goes to its end; or it names a tab, and the
pane goes before that tab. With `side` — `:left`, `:right`, `:above` or `:below`
— the pane goes beside the target's group, in a new split. Both references are
complete, and both name parts of one pane tree. The move is made through the
readers of the editor and evaluated at once, so the person undoes it with one
press.
"""
function move_pane!(editor, reference::Reference, target::Reference; side = nothing)
    _refuse_stale(reference)
    _refuse_stale(target)
    operation = make_move_pane_operation(editor, reference, target; side)
    operation === nothing && throw(ArgumentError("The window can not move that pane there."))
    _evaluate_pane_operation!(editor, operation)
    show_layout(editor)
end

move_pane!(editor, pane::Union{Reference, ReferencedDocument},
           target::Union{Reference, ReferencedDocument}; side = nothing) =
    move_pane!(editor, convert(Reference, pane), convert(Reference, target); side)

"""
    make_move_pane_operation(editor, reference, target; side = nothing) -> Operation | Nothing

The operation that moves the pane `reference` names, as [`move_pane!`](@ref)
moves it, from the root of the editor's document. It evaluates nothing.
`nothing` when the window can not make that move.
"""
function make_move_pane_operation(editor, reference::Reference, target::Reference; side = nothing)
    root = _get_root_document(editor)
    found = _find_pane_tree_route(root, reference)
    found === nothing &&
        throw(ArgumentError("That reference names nothing inside a pane tree."))
    route, tree = found
    source, source_index = _find_pane_position(tree, try_evaluate_reference(root, reference, nothing))
    destination = try_evaluate_reference(root, target, nothing)
    if destination isa PaneTab
        group, index = _find_pane_position(tree, destination)
    elseif destination isa PaneGroup && any(g -> g === destination, get_pane_groups(tree))
        group, index = destination, length(destination.tabs) + 1
    else
        throw(ArgumentError("The target names no group or tab of the pane's tree."))
    end
    operation = if side === nothing
        make_pane_move_tab_operation(tree, source; source_index, target = group, target_index = index)
    else
        side in (:left, :right, :above, :below) ||
            throw(ArgumentError("`side` is :left, :right, :above or :below."))
        make_pane_drop_split_operation(tree, source; source_index, target = group,
                                       orientation = side in (:left, :right) ? :vertical : :horizontal,
                                       side)
    end
    _make_rooted_pane_operation(editor, route, tree, operation,
                                "Move the pane " * get_pane_tab_title_string(source.tabs[source_index]))
end

# ── The layout ──────────────────────────────────────────────────────────────

"""
    show_layout(editor; include = is_layout_line, descend = is_pane_search_step) -> Text

What is where in the windows of the editor: a tree of reference steps, one line
for each window, pane tree, split, group and tab, with the type of the node it
reaches and a note on what it is.

Use it to see the layout — which panes are open, where each one sits, what it
holds and which one has the focus — and to read the path of a part before you
change it.

# Example

    show_layout(editor)

```
(root)                                  ::GestureTrackingState  # the editor's document
  .content                              ::ScreenDocument
    .windows[1]                         ::WindowDocument        # title "ProjecturEd"
      .content.content.content.content  ::PaneTree              # inside ClipboardSlice › WidgetShell › UndoBuffer
        .root                           ::PaneSplit             # side by side: 20% | 80%
          .elements[1]                  ::PaneGroup             # 1 tab
            .tabs[1]                    ::PaneTab               # title "Files", shows Workspace (focused)
          .elements[2]                  ::PaneGroup             # 1 tab
            .tabs[1]                    ::PaneTab               # title "a.json", shows JsonFile
```

See also `find_pane_reference`, `focus_pane!`, `close_pane!`, `move_pane!`,
`replace_referenced_value!`.

**A line is the steps from its parent line.** The path of a part is the steps of
the lines on its branch, joined in order. Write it as
`@reference(editor.document, content.windows[1].content.content.content.content.root.elements[2].tabs[1])`:
the first argument is the root, and the path starts after it. To name a pane
there is a shorter way: [`find_pane_reference`](@ref) answers the reference of
a pane by its title.

The type is the type of the node the line reaches. The note says the node's
title after `title`, quoted as `find_pane` takes it (`get_document_title`), what
it shows after `shows` (`describe_document`), and which tab has the focus. A line
whose steps go through wrappers, such as a history, names them.

`include(node)` says which nodes get a line, and `descend(parent, child)` where
the walk goes. The defaults show the windows, the pane trees, the splits, the
groups and the tabs, and a pane tree inside a tab below that tab.

It answers a `Text`, not a `String`, so the tree arrives as the lines it is. A
`String` would reach a model through `repr`, as one line of `\\n` escapes.
"""
function show_layout(editor; include = is_layout_line, descend = is_pane_search_step)
    root = _get_root_document(editor)
    paths = search_references(root, node -> node === root || include(node); descend)
    focused = _find_focused_pane_tab(root)
    lines = Tuple{String,String,String}[]
    printed = Tuple{Vector{Any},Int}[]           # the steps of each line, and its depth
    for path in paths
        steps = collect(get_reference_steps(strip_reference_types(path)))
        node = try_evaluate_reference(root, path, nothing)
        node === nothing && continue
        parent = findlast(entry -> _is_proper_prefix(entry[1], steps), printed)
        from, depth = parent === nothing ? (0, 0) : (length(printed[parent][1]), printed[parent][2] + 1)
        push!(printed, (steps, depth))
        text = isempty(steps) ? "(root)" :
               repr(foldr(ConcreteReference, steps[(from + 1):end]; init = EmptyReference()))
        push!(lines, ("  " ^ depth * text, "::" * String(nameof(typeof(node))),
                      _format_layout_note(root, node, steps, from, focused)))
    end
    width = maximum(line -> length(line[1]), lines; init = 0)
    kind = maximum(line -> length(line[2]), lines; init = 0)
    Text(join((rpad(step, width + 2) * rpad(type, kind + 2) *
               (isempty(note) ? "" : "# " * note) for (step, type, note) in lines), "\n") * "\n")
end

"""
    is_layout_line(node) -> Bool

Whether [`show_layout`](@ref) gives `node` a line by default: a document that is
not a collection, not a widget and not a wrapper — so the screen, a window, a
pane tree, a split, a group and a tab.
"""
is_layout_line(node) =
    node isa Document && !(node isa CellVector) && !(node isa WidgetDocument) &&
    get_wrapped_document(node) === node

_is_proper_prefix(prefix, steps) =
    length(prefix) < length(steps) && all(i -> prefix[i] == steps[i], eachindex(prefix))

# The tab that has the focus: the deepest tab on the path of the root's selection.
function _find_focused_pane_tab(root)
    selection = get_selection(root)
    selection === nothing && return nothing
    steps = collect(get_reference_steps(strip_reference_types(selection)))
    focused = nothing
    for n in eachindex(steps)
        node = try_evaluate_reference(root, foldr(ConcreteReference, steps[1:n]; init = EmptyReference()), nothing)
        node isa PaneTab && (focused = node)
    end
    focused
end

# The note of a line: the root says what it is; any other node says its title,
# quoted after `title` so that a reader does not take the rest of the note for
# a part of it, what it shows when that says more than its type, the wrappers its
# steps go through, and whether it is the tab with the focus. A node with no
# title, such as a group or a split, says only what it is.
function _format_layout_note(root, node, steps, from, focused)
    node === root && return "the editor's document"
    name = get_document_title(node)
    what = describe_document(node)
    what == String(nameof(typeof(node))) && (what = "")
    has_title = !(name === nothing || isempty(String(name)))
    note = has_title && !isempty(what) ? "title " * repr(String(name)) * ", shows " * what :
           has_title                   ? "title " * repr(String(name)) : what
    wrappers = String[]
    for n in (from + 1):(length(steps) - 1)
        passed = try_evaluate_reference(root, foldr(ConcreteReference, steps[1:n]; init = EmptyReference()), nothing)
        (passed isa Document && get_wrapped_document(passed) !== passed) &&
            push!(wrappers, String(nameof(typeof(passed))))
    end
    isempty(wrappers) || (note = strip(note * " inside " * join(wrappers, " › ")))
    node === focused && (note = strip(note * " (focused)"))
    String(note)
end

# What a tab, a group and a split are, for the note of a line.
get_document_title(tab::PaneTab) = get_pane_tab_title_string(tab)
describe_document(tab::PaneTab) = describe_document(tab.content)
describe_document(group::PaneGroup) =
    length(group.tabs) == 1 ? "1 tab" : string(length(group.tabs), " tabs")
describe_document(split::PaneSplit) =
    (split.orientation === :vertical ? "side by side: " : "stacked: ") *
    join((string(round(Int, 100 * weight), "%") for weight in get_pane_normalized_weights(get_pane_weights(split))), " | ")

# ── Saying a path back ──────────────────────────────────────────────────────

_path_text(path::Reference) = _path_text(get_reference_steps(path))
_path_text(steps::AbstractVector) =
    isempty(steps) ? "the whole tree" : rstrip(join(map(_step_text, steps), ""), '.')

_step_text(step::FieldReferenceStep) = "." * step.name
_step_text(step::RangeReferenceStep) =
    step.stop == step.start + 1 ? "[" * string(step.stop) * "]" :
    "[" * string(step.start + 1) * ", " * string(step.stop) * "]"
_step_text(step) = "." * string(step)
