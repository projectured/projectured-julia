# Fragment of `ExplorerModule` — the page of a dashboard: its title, and its cards
# in columns that follow the width of the page, each card filling its cell.
#
#     title<rest>               children[1].content<rest>
#     cards[k].content.<rest>   children[2].child.content.children[1].children[k].content.<rest>

"""
    DashboardToWidget(; gap, card_width)

Draw a [`Dashboard`](@ref) as its page: a field with its title, and its cards in
a grid that scrolls. The grid has as many columns as cards of at least
`card_width` fit in the width of the page, and each card fills its cell; with no
width, one column. The count follows the width while the page shows, so a drag of
a splitter or a resize of the window lays the cards out again. The content of each card draws by the view of its own type,
so a press, a caret and a key in it reach that document. A key in the field edits
the title. A dashboard with no card says how to add one.
"""
@projection UntrackedCell struct DashboardToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    card_width::Int = 280
end

const _DASHBOARD_HOLDER_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("child"),
                                 FieldReferenceStep("content"))
const _DASHBOARD_GRID_STEPS = (_DASHBOARD_HOLDER_STEPS..., FieldReferenceStep("children"), RangeReferenceStep(0, 1))

function print_document(p::DashboardToWidget, recursion, dashboard::Dashboard, context)
    width = context === nothing ? nothing : get_exact_width(context)
    # The count reads the cell of the width of the slot, and a width that keeps the
    # count leaves the grid as it is.
    columns = Cell(@computation _count_card_columns(p, unwrap_cell(width)))
    title = WidgetText(""; width = _TITLE_FIELD_WIDTH)
    set_cell_computation!(getfield(title, :content), () -> String(dashboard.title))
    set_output_path_computations!(title, dashboard, path -> _map_title_field_path(path))
    holder = VerticalLayout(CellVector(Any[]), Cell(:left), Cell(0), Cell(Fill), Cell(Content), Cell(nothing))
    scroll = WidgetScrollPane(holder)
    constraint = LayoutConstraint(scroll; width = Fill, height = Fill)
    root = VerticalLayout(Any[title, constraint]; horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, dashboard, root, Cell(Any[]))
    set_output_path_computations!(root, dashboard, path -> map_reference_forward(p, iomap, path); dormant = false)
    # A layout passes a key by its own selection, so each one carries the part of
    # the path of the page below it.
    for (widget, steps) in ((constraint, _DASHBOARD_HOLDER_STEPS[1:2]), (scroll, _DASHBOARD_HOLDER_STEPS[1:3]),
                            (holder, _DASHBOARD_HOLDER_STEPS))
        set_output_path_computations!(widget, root, path -> _find_path_below(path, steps))
    end
    # The grid is made again when a card comes or goes, or the count of columns
    # changes, so the new one prints.
    set_cell_computation!(getfield(holder.children, :elements),
                          () -> Cell[Cell(_build_card_grid(p, dashboard, columns[], root))])
    iomap
end

# How many cards of at least `card_width` fit in `width`, with the gaps between
# them; one with no width.
_count_card_columns(p::DashboardToWidget, width) =
    width === nothing ? 1 : max(1, (Int(width) + p.gap) ÷ (p.card_width + p.gap))

# The grid of the cards of `dashboard` in `columns` columns of one weight, each card
# with the selection of the page below it; a line that says how to add a card, for
# a dashboard with none.
function _build_card_grid(p::DashboardToWidget, dashboard::Dashboard, columns::Int, root)
    cards = dashboard.cards
    isempty(cards) && return WidgetLabel("This dashboard has no card. Insert on this page adds one.")
    widgets = Any[]
    for k in 1:length(cards)
        card = cards[k]
        widget = WidgetCard(; title = card.title, content = card.content)
        steps = (_DASHBOARD_GRID_STEPS..., FieldReferenceStep("children"), RangeReferenceStep(k - 1, k))
        set_output_path_computations!(widget, root, path -> _find_path_below(path, steps))
        push!(widgets, widget)
    end
    grid = GridLayout(widgets, min(columns, length(cards)); horizontal_gap = p.gap, vertical_gap = p.gap,
                      column_policy = Relative(1))
    set_output_path_computations!(grid, root, path -> _find_path_below(path, _DASHBOARD_GRID_STEPS))
    grid
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
            k = steps[2].stop
            return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), _DASHBOARD_GRID_STEPS...,
                FieldReferenceStep("children"), RangeReferenceStep(k - 1, k), FieldReferenceStep("content"),
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
            card = get_reference_steps(rest)
            length(card) >= 3 && card[1] == FieldReferenceStep("children") && card[2] isa RangeReferenceStep &&
                card[3] == FieldReferenceStep("content") &&
                return extend_reference(EmptyReference(), FieldReferenceStep("cards"),
                                        ElementReferenceStep(card[2].stop), FieldReferenceStep("content"), card[4:end]...)
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

make_graphics_projection(::Type{<:Dashboard}; measure, appearance) =
    ChainingProjection(
        DashboardToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
