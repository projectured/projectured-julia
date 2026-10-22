# Fragment of `HelpModule` — the page of a tree of the help and of a group: a line
# that says what the node holds, and under it a table with one row for each
# child, which the page builds with every row at once, because a page holds at
# most a few dozen children.
#
#     children[k]<rest>    children[2].rows[k]

const _HelpPage = Union{DocumentTypeList, ProjectionList, HelpGroup}

"""
    HelpGroupToWidget(; gap, line)

Draw a [`DocumentTypeList`](@ref), a [`ProjectionList`](@ref) or a
[`HelpGroup`](@ref) as its page: a line that says what it holds, and under it a
table with one row for each child, which fills the rest of the height and
scrolls there. A row shows a group with its count of types, or a type with the
names that a person types into an empty tab for a document type, and then the
description. The name and the middle column are as wide as their widest cell,
and the description fills the rest, cut at its edge.

A press on a row selects its node, a double press opens the page of the node in
the navigator around the page, and Ctrl+press opens it in a new tab.

The projection holds its styles and no theme; `make_help_group_projection` fills
them from a theme.
"""
@projection UntrackedCell struct HelpGroupToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    line::StyleText = get_help_style(nothing, :heading_text)
end

"""
    make_help_group_projection(; theme = nothing, gap) -> HelpGroupToWidget

The projection of the page of a tree of the help or of a group, with the styles
of `theme`: a `HelpTheme`, scaled or not, or the default styles for `nothing`.
`gap` is the space between the line and the table.
"""
make_help_group_projection(; theme = nothing, gap = get_widget_style(nothing, :section_gap)) =
    HelpGroupToWidget(; gap, line = get_help_style(theme, :heading_text))

# The place of the table in the grid of the page, and the field of its rows.
const _HELP_TABLE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))
const _HELP_LINE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _HELP_ROWS_STEP = FieldReferenceStep("rows")
const _HELP_CHILDREN_STEP = FieldReferenceStep("children")

const _HELP_TABLE_TOOLTIP = "A double press opens the page of a row, and a Ctrl+press opens it in a new tab."

function print_document(p::HelpGroupToWidget, recursion, holder::_HelpPage, context)
    line = WidgetLabel(""; text_style = p.line)
    set_cell_computation!(getfield(line, :content), () -> _format_help_line(holder))
    children = collect(holder.children)
    output = isempty(children) ?
        GridLayout(Any[line], 1; column_policy = Fill, row_policies = Any[Content]) :
        GridLayout(Any[line, _make_help_table(children)], 1; vertical_gap = p.gap, column_policy = Fill,
                   row_policies = Any[Content, Fill])
    iomap = ChildrenIoMap(p, holder, output, Cell(Any[]))
    # The selection of the node follows into the row that shows it.
    set_output_path_computations!(output, holder, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The columns of the table: a name, then the count of the types of a group or
# the names to type of a document type, each as wide as its widest cell, then the
# description, which takes the rest of the width. A projection has no names to
# type, so its table has no middle column.
function _get_help_columns(children)
    first(children) isa HelpGroup && return ["name" => Content, "types" => Content, "description" => Fill]
    _is_projection_entry(first(children)) && return ["name" => Content, "description" => Fill]
    ["name" => Content, "names to type" => Content, "description" => Fill]
end

_is_projection_entry(entry::HelpEntry) = entry.type isa Type && entry.type <: Projection

_get_help_cells(group::HelpGroup) = Any[group.name, string(group.count), group.description]
_get_help_cells(entry::HelpEntry) =
    _is_projection_entry(entry) ? Any[entry.name, entry.description] : Any[entry.name, entry.typed, entry.description]

function _make_help_table(children)
    columns = _get_help_columns(children)
    WidgetTable(; column_headers = Any[name for (name, _) in columns],
                cells = Any[Any[WidgetLabel(text) for text in _get_help_cells(child)] for child in children],
                columns = Any[WidgetTableColumn(; policy, align = name == "types" ? :right : nothing)
                              for (name, policy) in columns],
                tooltip = _HELP_TABLE_TOOLTIP)
end

# "268 document types in 21 packages. …", the description of a group, or a note
# for a group whose package or module has no docstring.
function _format_help_line(list::Union{DocumentTypeList, ProjectionList})
    groups = list.children
    isempty(groups) && return ""
    count = sum(group -> group.count, groups)
    packages = _format_help_count_words(length(groups), "package", "packages")
    list isa DocumentTypeList ?
        string(_format_help_count_words(count, "document type", "document types"), " in ", packages,
               ". Type one of the names in an empty tab to make a document of that type.") :
        string(_format_help_count_words(count, "projection", "projections"), " in ", packages,
               ". A projection draws a document, and one that takes other projections combines them.")
end

_format_help_line(group::HelpGroup) = isempty(group.description) ? "No description." : group.description

_format_help_count_words(count, one, many) = string(count, " ", count == 1 ? one : many)

# The index of the row that `steps` name below the table, `rows[k]`, with the
# steps after it; `nothing` for any other steps.
function _find_help_row(steps)
    length(steps) >= length(_HELP_TABLE_STEPS) + 2 || return nothing
    all(k -> steps[k] == _HELP_TABLE_STEPS[k], eachindex(_HELP_TABLE_STEPS)) || return nothing
    at = length(_HELP_TABLE_STEPS) + 1
    (steps[at] == _HELP_ROWS_STEP && steps[at + 1] isa RangeReferenceStep &&
     steps[at + 1].stop == steps[at + 1].start + 1) || return nothing
    steps[at + 1].stop
end

# `children[k]` and any path inside the node ↔ the row `k` of the table: the row
# shows the node, and a path inside it has no part of its own on the page.
function map_reference_forward(p::HelpGroupToWidget, iomap, reference)
    if reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        if length(steps) >= 2 && steps[1] == _HELP_CHILDREN_STEP && steps[2] isa RangeReferenceStep &&
           steps[2].stop == steps[2].start + 1
            k = steps[2].stop
            (iomap.output isa GridLayout && length(iomap.output.children) == 2 &&
             1 <= k <= length(iomap.input.children)) || return nothing
            return annotate_reference_types(iomap.output,
                extend_reference(EmptyReference(), _HELP_TABLE_STEPS..., _HELP_ROWS_STEP, RangeReferenceStep(k - 1, k)))
        end
    end
    invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# A row is its node, a press on the line leaves the selection where it is, and
# any other part of the table, such as a header or a scroll bar, is a part that
# the view drew.
function map_reference_backward(p::HelpGroupToWidget, iomap, reference)
    if reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        k = _find_help_row(steps)
        k === nothing ||
            return extend_reference(EmptyReference(), _HELP_CHILDREN_STEP, ElementReferenceStep(k))
        (length(steps) >= 2 && steps[1] == _HELP_LINE_STEPS[1] && steps[2] == _HELP_LINE_STEPS[2]) &&
            return nothing
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# The generic bridge maps the answer of the table back, so a press on a row
# selects its node, `children[k]`. A double press also opens the page of the
# node, and Ctrl+press opens it in a new tab.
function read_intent(p::HelpGroupToWidget, recursion, change::Intent, iomap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    place = _find_pressed_help_node(change.gesture, answer.operation)
    place === nothing && return answer
    page_place = change.gesture.modifiers.ctrl ? :new_tab : :here
    (page_place === :here && change.gesture.count < 2) && return answer
    Intent(answer.gesture, CompoundOperation(Any[answer.operation, OpenPageOperation(nothing, place, page_place)]),
           answer.description, answer.domain)
end

# The node that a left press selects, `children[k]`, or `nothing`.
function _find_pressed_help_node(gesture, operation)
    (gesture isa MouseClick && gesture.button === :left && operation isa ReplaceSelectionOperation) ||
        return nothing
    steps = get_reference_steps(strip_reference_types(operation.path))
    (length(steps) == 2 && steps[1] == _HELP_CHILDREN_STEP && steps[2] isa RangeReferenceStep) || return nothing
    operation.path
end

# A tree and a group draw as their page inside any document that a renderer
# draws.
make_graphics_projection(::Type{<:_HelpPage}; measure, appearance) =
    ChainingProjection(
        make_help_group_projection(; theme = get_scaled_theme!(appearance, HelpTheme),
                                   gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        GridLayoutToGraphicsCanvas())
