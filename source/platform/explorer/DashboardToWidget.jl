# Fragment of `ExplorerModule` — the page of a dashboard: its title, and its cards
# in rows of columns that follow the width of the page, each card filling its cell.
#
#     title<rest>               children[1].content<rest>
#     cards[k].content.<rest>   children[2].child.content.children[r][c].content.<rest>
#                               children[2].child.content.children[k].content.<rest>
#
# A page with a height shows a part of its cards, so the rows of its grid are a
# list, and card `k` is in row `r` and column `c`, both counted from 1 in the order
# of the cards (`_get_card_place`). A page with no height has no screen to cut, so
# its grid holds the cards as a vector, and card `k` is child `k`.

"""
    DashboardToWidget(; gap, card_width)

Draw a [`Dashboard`](@ref) as its page: a field with its title, and its cards in
a grid that scrolls. The grid has as many columns as cards of at least
`card_width` fit in the width of the page, and each card fills its cell; with no
width, one column. On a page with a height the rows of the grid are a list, so
the page draws the rows that it shows, and a dashboard of many cards computes the
cards on the screen. The count follows the width while the page shows, so a drag of
a splitter or a resize of the window lays the cards out again. The content of each card draws by the view of its own type,
so a press, a caret and a key in it reach that document. A key in the field edits
the title. A dashboard with no card says how to add one.
"""
@projection UntrackedCell struct DashboardToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    card_width::Int = 280
end

const _DASHBOARD_SCROLL_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("child"))
const _DASHBOARD_GRID_STEPS = (_DASHBOARD_SCROLL_STEPS..., FieldReferenceStep("content"))

function print_document(p::DashboardToWidget, recursion, dashboard::Dashboard, context)
    width = context === nothing ? nothing : get_exact_width(context)
    # The count reads the cell of the width of the slot, and a width that keeps the
    # count leaves the grid as it is.
    columns = Cell(@computation _count_card_columns(p, unwrap_cell(width)))
    title = WidgetText(""; width = _TITLE_FIELD_WIDTH)
    set_cell_computation!(getfield(title, :content), () -> String(dashboard.title))
    set_output_path_computations!(title, dashboard, path -> _map_title_field_path(path))
    scroll = WidgetScrollPane(nothing)
    constraint = LayoutConstraint(scroll; width = Fill, height = Fill)
    root = VerticalLayout(Any[title, constraint]; horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, dashboard, root, Cell(Any[]))
    set_output_path_computations!(root, dashboard, path -> map_reference_forward(p, iomap, path); dormant = false)
    # A layout passes a key by its own selection, so each one carries the part of
    # the path of the page below it.
    for (widget, steps) in ((constraint, _DASHBOARD_SCROLL_STEPS[1:2]), (scroll, _DASHBOARD_SCROLL_STEPS))
        set_output_path_computations!(widget, root, path -> _find_path_below(path, steps))
    end
    # The grid is the content of the pane itself, because a pane scrolls a list of
    # rows only in its content. It is made again when a card comes or goes, or the
    # count of columns changes, and the pane prints the new one.
    height = context === nothing ? nothing : get_exact_height(context)
    set_cell_computation!(getfield(scroll, :content),
                          () -> _build_card_grid(p, dashboard, columns[], root, width !== nothing, height !== nothing))
    iomap
end

# How many cards of at least `card_width` fit in `width`, with the gaps between
# them; one with no width.
_count_card_columns(p::DashboardToWidget, width) =
    width === nothing ? 1 : max(1, (Int(width) + p.gap) ÷ (p.card_width + p.gap))

# The grid of the cards of `dashboard` in `columns` columns of one weight, each card
# with the selection of the page below it; a line that says how to add a card, for
# a dashboard with none. On a page with a height the rows are a list, and a grid of
# a list divides only a width that its parent offers, so with no width it has one
# column of `card_width`.
function _build_card_grid(p::DashboardToWidget, dashboard::Dashboard, columns::Int, root,
                          has_width::Bool, has_height::Bool)
    cards = dashboard.cards
    isempty(cards) && return WidgetLabel("This dashboard has no card. Insert on this page adds one.")
    count = min(columns, length(cards))
    widgets = Any[]
    for k in 1:length(cards)
        card = cards[k]
        widget = WidgetCard(; title = card.title, content = card.content)
        steps = (_DASHBOARD_GRID_STEPS..., _make_card_steps(k, count, has_height)...)
        set_output_path_computations!(widget, root, path -> _find_path_below(path, steps))
        push!(widgets, widget)
    end
    grid = if has_height
        head = ListNode(widgets[1:count])
        foreach(first -> push!(head, widgets[first:min(first + count - 1, end)]), (count + 1):count:length(widgets))
        GridLayout(head, count; horizontal_gap = p.gap, vertical_gap = p.gap,
                   column_policy = has_width ? Relative(1) : Fixed(p.card_width))
    else
        GridLayout(widgets, count; horizontal_gap = p.gap, vertical_gap = p.gap, column_policy = Relative(1))
    end
    set_output_path_computations!(grid, root, path -> _find_path_below(path, _DASHBOARD_GRID_STEPS))
    grid
end

# The row and the column of card `k` in a grid of `columns` columns.
_get_card_place(k::Int, columns::Int) = (div(k - 1, columns) + 1, rem(k - 1, columns) + 1)

# The steps from the grid to card `k`: `children[r][c]` when the rows are a list,
# and `children[k]` when the cards are a vector.
function _make_card_steps(k::Int, columns::Int, rows_are_list::Bool)
    rows_are_list || return (FieldReferenceStep("children"), RangeReferenceStep(k - 1, k))
    (r, c) = _get_card_place(k, columns)
    (FieldReferenceStep("children"), RangeReferenceStep(r - 1, r), RangeReferenceStep(c - 1, c))
end

# The card that `steps` below the grid name, and the steps after its content, or
# `nothing` when they name no card.
function _find_card_below(steps, columns::Int, rows_are_list::Bool)
    (length(steps) >= 1 && steps[1] == FieldReferenceStep("children")) || return nothing
    if rows_are_list
        (length(steps) >= 4 && steps[2] isa RangeReferenceStep && steps[3] isa RangeReferenceStep &&
         steps[4] == FieldReferenceStep("content")) || return nothing
        return ((steps[2].stop - 1) * columns + steps[3].stop, steps[5:end])
    end
    (length(steps) >= 3 && steps[2] isa RangeReferenceStep && steps[3] == FieldReferenceStep("content")) ||
        return nothing
    (steps[2].stop, steps[4:end])
end

# The shape of the grid that the page `root` shows now: the count of its columns,
# and whether its rows are a list. A page with no grid has one column.
function _get_grid_shape(root)
    grid = root.children[2].child.content
    grid isa GridLayout || return (1, false)
    (Int(grid.columns), grid.children isa ListNode)
end

function map_reference_forward(p::DashboardToWidget, iomap, reference)
    iomap === nothing && return invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
    field = _map_title_field_path(reference)
    field === nothing ||
        return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), FieldReferenceStep("children"),
                                                                       RangeReferenceStep(0, 1), get_reference_steps(field)...))
    if reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        if length(steps) >= 3 && steps[1] == FieldReferenceStep("cards") && steps[2] isa RangeReferenceStep &&
           steps[3] == FieldReferenceStep("content")
            (columns, rows_are_list) = _get_grid_shape(iomap.output)
            return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), _DASHBOARD_GRID_STEPS...,
                _make_card_steps(steps[2].stop, columns, rows_are_list)..., FieldReferenceStep("content"),
                steps[4:end]...))
        end
    end
    invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function map_reference_backward(p::DashboardToWidget, iomap, reference)
    if reference isa ConcreteReference
        path = strip_reference_types(reference)
        steps = get_reference_steps(path)
        length(steps) >= 3 && steps[1] == FieldReferenceStep("children") && steps[2] == RangeReferenceStep(0, 1) &&
            steps[3] == FieldReferenceStep("content") &&
            return extend_reference(EmptyReference(), FieldReferenceStep("title"), steps[4:end]...)
        rest = _find_path_below(path, _DASHBOARD_GRID_STEPS)
        if rest isa ConcreteReference
            found = _find_card_below(get_reference_steps(rest), _get_grid_shape(iomap.output)...)
            found === nothing ||
                return extend_reference(EmptyReference(), FieldReferenceStep("cards"),
                                        ElementReferenceStep(found[1]), FieldReferenceStep("content"), found[2]...)
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

make_graphics_projection(::Type{<:Dashboard}; measure, appearance) =
    ChainingProjection(
        DashboardToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
