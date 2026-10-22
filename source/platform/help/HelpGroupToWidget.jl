# Fragment of `HelpModule` — the page of a tree of the help and of a group: a line
# that says what the node holds, and under it the table of its children, which the
# grid prints through the recursion, so a path in it is a path of the node.
#
#     table.<rest>    children[2].<rest>

const _HelpPage = Union{DocumentTypeList, ProjectionList, HelpGroup}

"""
    HelpGroupToWidget(; gap, line)

Draw a [`DocumentTypeList`](@ref), a [`ProjectionList`](@ref) or a
[`HelpGroup`](@ref) as its page: a line that says what it holds, and under it the
table of its children, which fills the rest of the height. A row shows a group
with its count of types and its description, or a type with its description, and
for a document type the names that a person types into an empty tab. A double
click on a row opens the page of its node in the navigator around the page, at
the place of the node in the tree.

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

const _HELP_LINE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _HELP_TABLE_PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))
const _HELP_TABLE_STEP = FieldReferenceStep("table")

function print_document(p::HelpGroupToWidget, recursion, holder::_HelpPage, context)
    line = WidgetLabel(""; text_style = p.line)
    set_cell_computation!(getfield(line, :content), () -> _format_help_line(holder))
    table = getfield(holder, :table)[]
    output = table === nothing ?
        GridLayout(Any[line], 1; column_policy = Fill, row_policies = Any[Content]) :
        GridLayout(Any[line, table], 1; vertical_gap = p.gap, column_policy = Fill,
                   row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, holder, output)
    # The grid passes a key by its own selection, so it carries the path of the node
    # below it. The table is a document of the node, which holds its own.
    set_output_path_computations!(output, holder, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# "268 document types in 24 packages. …", the description of a group, or a note
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

# The rest of `path` after `steps`, or `nothing` when it does not start with them.
function _find_help_path_below(path, steps)
    for step in steps
        (path isa ConcreteReference && get_reference_head(path) == step) || return nothing
        path = get_reference_tail(path)
    end
    path
end

# `table.<rest>` ↔ the table in the grid.
function map_reference_forward(::HelpGroupToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    rest = _find_help_path_below(reference, (_HELP_TABLE_STEP,))
    table = getfield(iomap.input, :table)[]
    (rest === nothing || table === nothing) && return nothing
    is_fully_typed_reference(rest) || (rest = annotate_reference_types(table, strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), _HELP_TABLE_PLACE_STEPS...)),
                      rest)
end

# A path into the line names nothing, so a press on it leaves the selection where
# it is; a path into the grid itself names the whole node.
function map_reference_backward(::HelpGroupToWidget, iomap::SimpleIoMap, reference)
    _find_help_path_below(reference, _HELP_LINE_STEPS) === nothing || return nothing
    rest = _find_help_path_below(reference, _HELP_TABLE_PLACE_STEPS)
    rest === nothing ? EmptyReference() : ConcreteReference(_HELP_TABLE_STEP, rest)
end

# The generic bridge maps the answer of the grid back. The open of a row, which
# the table answers with the path of the row, opens the node of the row at its
# place in the tree, so the address names the node and Parent comes back here.
function read_intent(p::HelpGroupToWidget, recursion, change::Intent, iomap::SimpleIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    operation = _open_help_node(iomap.input, answer.operation)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end

function _open_help_node(holder, operation::CompoundOperation)
    parts = Any[_open_help_node(holder, part) for part in operation.operations]
    all(k -> parts[k] === operation.operations[k], eachindex(parts)) ? operation : CompoundOperation(parts)
end

function _open_help_node(holder, operation::WrappingOperation)
    inner = get_wrapped_operation(operation)
    opened = _open_help_node(holder, inner)
    opened === inner ? operation : rewrap_operation(operation, opened)
end

function _open_help_node(holder, operation::OpenPageOperation)
    (operation.document === nothing && operation.target === nothing) || return operation
    place = _find_help_node_path(holder, operation.reference)
    place === nothing ? operation : OpenPageOperation(nothing, place, operation.place)
end

_open_help_node(holder, operation) = operation

# The place in the tree of the node that a path through the table of `holder`
# reaches: from `table.rows[r].item<rest>`, `children[k]<rest>`, where `k` is the
# place of that item among the children of `holder`; `nothing` for a path that
# reaches no item of a row. The path can pass an arrangement around the roster.
function _find_help_node_path(holder::_HelpPage, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    (isempty(steps) || steps[1] != _HELP_TABLE_STEP) && return nothing
    for last in 2:length(steps)
        steps[last] == FieldReferenceStep("item") || continue
        item = try_evaluate_reference(holder, extend_reference(EmptyReference(), steps[1:last]...), nothing)
        item === nothing && return nothing
        k = findfirst(child -> child === item, collect(holder.children))
        k === nothing && return nothing
        return extend_reference(EmptyReference(), FieldReferenceStep("children"), ElementReferenceStep(k),
                                steps[(last + 1):end]...)
    end
    nothing
end

# A tree and a group draw as their page inside any document that a renderer
# draws; the table comes back through the recursion of the renderer.
make_graphics_projection(::Type{<:_HelpPage}; measure, appearance) =
    ChainingProjection(
        make_help_group_projection(; theme = get_scaled_theme!(appearance, HelpTheme),
                                   gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        GridLayoutToGraphicsCanvas())
