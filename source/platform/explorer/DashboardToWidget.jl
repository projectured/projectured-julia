# Fragment of `ExplorerModule` — the page of a dashboard: its title, and its cards
# in rows of columns that follow the width of the page, each card filling the
# columns that it spans.
#
#     title<rest>               children[1].content<rest>
#     cards[k].content.<rest>   children[2].child.content.children[r][1].children[i].child.content
#                                   .children[1].child.content.<rest>
#
# The rows of the grid are a list of one column, so the page draws the rows that it
# shows. Each row is a grid of its own, with as many columns as the page has, and
# its cells are the cards of the row, each as wide as the columns that it spans.
# Card `k` is the card `i` of row `r`, both counted from 1 in the order of the
# cards (`_get_card_place`). A card draws its content, or the view that it keeps of
# its content, in a scroll pane that the height of the card bounds, and the path
# of the content goes through the field of the view that holds it.

"""
    DashboardToWidget(; gap, card_width, card_chrome, title_style)

Draw a [`Dashboard`](@ref) as its page: a field with its title, and its cards in
a grid that scrolls. The grid has as many columns as cards of at least
`card_width` fit in the width of the page; with no width, one column. A card
fills the columns that its `columns` names, and the cards flow row by row in
their order: a card that does not fit in what a row has left starts the next row.
A card is as high as its `height` says (`DashboardCard`), and a content that is
higher scrolls inside the card. The rows of the grid are a list, so the page
draws the rows that it shows, and a dashboard of many cards computes the cards on
the screen, also in a scroll area that grows. The count follows the width while
the page shows, so a drag of a splitter or a resize of the window lays the cards
out again. The content of each card draws by the view of its own type, so a press,
a caret and a key in it reach that document; a card that keeps a view of its
content draws the view. A key in the field edits the title. A dashboard with no
card says how to add one.

`card_chrome` is the height that a card draws around its content: its title and
its insets. A card is as high as its `height` says, so its body is that height less
`card_chrome`. `title_style` is the text of the title of a card, or `nothing`.

A card that the dashboard has maximized (`Dashboard`) is the only card of the page: one
column wide, and as high as the visible height of the page. The title of each card holds
a button that shows while the pointer is on the card, which maximizes it or gives the page
back, and a double click on the text of the title does the same.

A page that is held holds the content of its cards ([`Dashboard`](@ref)), and its
reader adds the change of what it holds to an edit of `cards`.
"""
@projection UntrackedCell struct DashboardToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    card_width::Int = 280
    card_chrome::Int = 0
    title_style::Any = nothing
end

const _DASHBOARD_SCROLL_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("child"))
const _DASHBOARD_GRID_STEPS = (_DASHBOARD_SCROLL_STEPS..., FieldReferenceStep("content"))

function print_document(p::DashboardToWidget, recursion, dashboard::Dashboard, context)
    width = _get_page_width(context)
    # The count reads the cell of the width of the slot, and a width that keeps the
    # count leaves the grid as it is.
    columns = Cell(@computation _count_card_columns(p, unwrap_cell(width)))
    title = WidgetText(""; width = _TITLE_FIELD_WIDTH)
    set_cell_computation!(getfield(title, :content), () -> String(dashboard.title))
    set_output_path_computations!(title, dashboard, path -> _map_title_field_path(path))
    scroll = WidgetScrollPane(nothing; grows = (width = false, height = true))
    # The pane takes what the page offers, and no more than the part of the page that
    # shows, so in a scroll area that grows on its height the pane scrolls by itself,
    # and its list of rows builds the rows that the view shows.
    visible = get_visible_height(context)
    constraint = LayoutConstraint(scroll; width = Fill, height = Fill)
    visible === nothing ||
        set_cell_computation!(getfield(constraint, :max_height), () -> Int(visible[]))
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
    set_cell_computation!(getfield(scroll, :content),
                          () -> _build_card_grid(p, dashboard, columns[], root, width !== nothing, visible))
    iomap
end

# The width that the page fills: the exact width that its parent gives, or else the
# edge of a bounded range, as a stack divides its edge whether it is exact or bounded
# (`layout-rules.md` §3). A scroll pane whose content fits its width, such as the pane
# of a file view, gives its content the view as a minimum and an edge in two cells,
# and the page lays its cards out in that edge. `nothing` with a free range or with
# no context: the page is one column of `card_width` then.
_get_page_width(context) =
    context === nothing ? nothing : something(get_exact_width(context), Some(context.maximum_width))

# How many cards of at least `card_width` fit in `width`, with the gaps between
# them; one with no width.
_count_card_columns(p::DashboardToWidget, width) =
    width === nothing ? 1 : max(1, (Int(width) + p.gap) ÷ (p.card_width + p.gap))

# The grid of the cards of `dashboard`: a list of rows, one column wide, each row a
# grid of `columns` columns whose cells are the cards of the row, each with the
# selection of the page below it; a line that says how to add a card, for a
# dashboard with none. A card takes the columns that it spans, and a card that does
# not fit in what a row has left starts the next row (`compute_grid_places`). The
# rows are a list, and a grid of a list divides only a width that its parent
# offers, so with no width it has one column of `card_width`.
function _build_card_grid(p::DashboardToWidget, dashboard::Dashboard, columns::Int, root, has_width::Bool, visible)
    isempty(dashboard.cards) && return WidgetLabel("This dashboard has no card. Insert or Ctrl+V on this page adds one.")
    # No more columns than the cards fill, so a page of few cards gives each its share. A card
    # that fills the page is one column of the whole width.
    maximized = _is_maximized_shown(dashboard)
    cards = _get_shown_cards(dashboard)
    count = has_width && !maximized ? min(columns, sum(card -> _get_card_span(card, columns), cards)) : 1
    places = compute_grid_places(Int[_get_card_span(card, count) for card in cards], count)
    rows = Any[]
    for k in 1:length(cards)
        (r, c, span) = places[k]
        r > length(rows) && push!(rows, Any[])
        i = length(rows[r]) + 1
        row_steps = (_DASHBOARD_GRID_STEPS..., _make_row_steps(r)...)
        steps = (row_steps..., _make_card_steps(i)...)
        widget = _make_card_widget(p, dashboard, cards[k], root, steps, visible, maximized)
        cell = LayoutConstraint(widget; column_span = span)
        set_output_path_computations!(cell, root, path -> _find_path_below(path, steps[1:(end - 1)]))
        push!(rows[r], cell)
    end
    grids = Any[]
    for (r, row) in enumerate(rows)
        grid = GridLayout(row, count; horizontal_gap = p.gap, vertical_gap = p.gap, column_policy = Fill)
        row_steps = (_DASHBOARD_GRID_STEPS..., _make_row_steps(r)...)
        set_output_path_computations!(grid, root, path -> _find_path_below(path, row_steps))
        push!(grids, Any[grid])
    end
    head = ListNode(grids[1])
    foreach(row -> push!(head, row), grids[2:end])
    grid = GridLayout(head, 1; horizontal_gap = p.gap, vertical_gap = p.gap,
                      column_policy = has_width ? Fill : Fixed(p.card_width))
    set_output_path_computations!(grid, root, path -> _find_path_below(path, _DASHBOARD_GRID_STEPS))
    grid
end

# How many columns of a page of `columns` columns `card` takes: what its `columns`
# says, `:all` for the whole row, and no more than the page has.
_get_card_span(card::DashboardCard, columns::Int) =
    card.columns === :all ? columns : clamp(Int(card.columns), 1, columns)

# The scroll pane of the body of a card, and the part of the card that the body
# of a card draws in: a pane in a layout, bounded by the height of the card.
const _CARD_BODY_STEPS = (FieldReferenceStep("content"), FieldReferenceStep("children"), RangeReferenceStep(0, 1),
                          FieldReferenceStep("child"), FieldReferenceStep("content"))

# The widget of `card`, which `steps` name below the page, with the body that its
# height bounds: the content, or its view, in a scroll pane. A card of `:content`
# is as high as its content, and at most the visible height of the page; a card of
# `:page` or of a number of pixels is that high, and its content scrolls.
function _make_card_widget(p::DashboardToWidget, dashboard::Dashboard, card::DashboardCard, root, steps, visible,
                          maximized::Bool)
    pane = WidgetScrollPane(_get_card_view(card))
    place = LayoutConstraint(pane; width = Fill)
    _set_card_body_height!(p.card_chrome, place, maximized ? :page : card.height, visible)
    body = VerticalLayout(Any[place]; child_width = Fill)
    widget = WidgetCard(; content = body,
                        gestures = GestureBinding[make_context_menu_binding(_ -> compute_context_menu(card);
                                                                            description = "Show the size menu of the card")])
    set_cell_value!(getfield(widget, :title), _make_card_title(p, dashboard, card, widget))
    for (part, below) in ((widget, ()), (body, _CARD_BODY_STEPS[1:1]), (place, _CARD_BODY_STEPS[1:3]),
                          (pane, _CARD_BODY_STEPS[1:4]))
        part_steps = (steps..., below...)
        set_output_path_computations!(part, root, path -> _find_path_below(path, part_steps))
    end
    widget
end

# The title of a card: its text, which a double click makes the card fill the page, and
# the button that does the same, which shows while the pointer is on the card.
function _make_card_title(p::DashboardToWidget, dashboard::Dashboard, card::DashboardCard, widget::WidgetCard)
    toggle = () -> _make_toggle_maximize_operation(dashboard, card)
    fills = _is_card_maximized(dashboard, card)
    double_click = GestureBinding(MouseClickPattern(:left),
                                  (_, gesture, _) -> gesture.count == 2 ? toggle() : nothing;
                                  description = "Fill the page with the card, or give the page back",
                                  domain = "dashboard")
    label = WidgetLabel(card.title; gestures = GestureBinding[double_click], text_style = p.title_style)
    name = fills ? "Give the page back" : "Fill the page with the card"
    button = WidgetToolbarItem(name; icon = WidgetIcon(fills ? :minimize : :maximize), focusable = false,
                               gestures = GestureBinding[GestureBinding(MouseClickPattern(:left), (_, _, _) -> toggle();
                                                                        description = name, domain = "dashboard")],
                               margin = inset_default, border = inset_default, padding = inset_default,
                               style = p.title_style === nothing ? nothing :
                                       WidgetStyle(; label_text_color = p.title_style.color),
                               tooltip = TooltipNote(; title = name))
    # The colour is read in its own computation. A read of it here would make the grid a reader of
    # the colour, and the colour reads the part under the pointer, which reads the grid.
    if p.title_style !== nothing
        set_cell_computation!(getfield(button.style, :label_text_color), () ->
            get_selection(widget) !== nothing || get_mouse_target(widget) !== nothing ?
                p.title_style.color : color_transparent)
    end
    HorizontalLayout(Any[LayoutConstraint(label; width = Fill), LayoutConstraint(button)]; vertical_align = :center)
end

# The cards that the page shows: the card that fills it, or all of them.
_get_shown_cards(dashboard::Dashboard) = _is_maximized_shown(dashboard) ? Any[dashboard.maximized] : dashboard.cards

# Whether a card of `dashboard` fills its page.
_is_maximized_shown(dashboard::Dashboard) =
    dashboard.maximized !== nothing && any(card -> card === dashboard.maximized, dashboard.cards)

# The index among the shown cards of card `k` of `dashboard`, or `nothing` for a card that is hidden.
_get_shown_index(dashboard::Dashboard, k::Int) =
    !_is_maximized_shown(dashboard) ? k : (dashboard.cards[k] === dashboard.maximized ? 1 : nothing)

# The index in `dashboard.cards` of the card `j` of the shown cards.
_get_card_index(dashboard::Dashboard, j::Int) =
    !_is_maximized_shown(dashboard) ? j : findfirst(card -> card === dashboard.maximized, dashboard.cards)

# The height of the body of a card in the constraint `place`, less `card_chrome`, the
# height that the card draws around its body. With no visible
# height of the page, a card of `:content` and of `:page` is as high as its content.
function _set_card_body_height!(card_chrome::Int, place::LayoutConstraint, height, visible)
    page() = max(0, Int(visible[]) - card_chrome)
    if height === :content
        visible === nothing || set_cell_computation!(getfield(place, :max_height), page)
    elseif height === :page
        visible === nothing && return
        for field in (:min_height, :preferred_height, :max_height)
            set_cell_computation!(getfield(place, field), page)
        end
    else
        body = max(0, Int(height) - card_chrome)
        for field in (:min_height, :preferred_height, :max_height)
            set_cell_value!(getfield(place, field), body)
        end
    end
end

# The place of card `k` of `cards` in a page of `columns` columns: the row, and the
# index in the row, both counted from 1.
function _get_card_place(cards, k::Int, columns::Int)
    places = compute_grid_places(Int[_get_card_span(card, columns) for card in cards], columns)
    r = places[k][1]
    (r, k - findfirst(place -> place[1] == r, places) + 1)
end

# The card at row `r` and index `i` of a page of `columns` columns, or `nothing`.
function _find_card_at(cards, r::Int, i::Int, columns::Int)
    places = compute_grid_places(Int[_get_card_span(card, columns) for card in cards], columns)
    first = findfirst(place -> place[1] == r, places)
    first === nothing && return nothing
    k = first + i - 1
    (k <= length(places) && places[k][1] == r) ? k : nothing
end

# The steps from the grid to row `r`: `children[r][1]`.
_make_row_steps(r::Int) = (FieldReferenceStep("children"), RangeReferenceStep(r - 1, r), RangeReferenceStep(0, 1))

# The steps from a row to the widget of its card `i`: `children[i].child`.
_make_card_steps(i::Int) = (FieldReferenceStep("children"), RangeReferenceStep(i - 1, i), FieldReferenceStep("child"))

# The card that `steps` below the grid name, as `(r, i, the steps after its widget)`, or
# `nothing` when they name no card.
function _find_card_below(steps)
    (length(steps) >= 6 && steps[1] == FieldReferenceStep("children") && steps[2] isa RangeReferenceStep &&
     steps[3] == RangeReferenceStep(0, 1) && steps[4] == FieldReferenceStep("children") &&
     steps[5] isa RangeReferenceStep && steps[6] == FieldReferenceStep("child")) || return nothing
    (steps[2].stop, steps[5].stop, steps[7:end])
end

# The count of the columns of the grid that the page `root` shows now. A page with
# no grid has one column.
function _get_grid_columns(root)
    grid = root.children[2].child.content
    grid isa GridLayout || return 1
    Int(grid.children.value[1].columns)
end

# The steps below the content of `card`, as the steps below what its card widget
# draws: the card draws the view of its content in the pane of its body, so they go
# through the pane and the path of the view for the place, except a part that the
# view introduced, which keeps its path after the content.
_make_card_view_steps(card::DashboardCard, rest) = (_CARD_BODY_STEPS[2:end]..., _make_view_content_steps(card, rest)...)

# The steps from what `card` draws, its content or the view of its content, to the
# part that `rest` names below the content: the path of the view for that place
# (`get_view_path`), except a part that the view introduced.
function _make_view_content_steps(card::DashboardCard, rest)
    view = _get_card_view(card)
    (view === card.content || isempty(rest) || first(rest) isa ProjectionReferenceStep) && return Tuple(rest)
    shown = get_view_path(view, Reference(rest...))
    shown isa ConcreteReference ? Tuple(get_reference_steps(strip_reference_types(shown))) : ()
end

# The steps below the content of `card` that `rest`, steps below what its card
# widget draws, name; `nothing` for a part that only the view keeps.
function _find_card_content_steps(card::DashboardCard, rest)
    body = _CARD_BODY_STEPS[2:end]
    rest = Tuple(rest)
    length(rest) < length(body) && return rest == body[1:length(rest)] ? () : nothing
    rest[1:length(body)] == body || return nothing
    _find_view_content_steps(card, rest[(length(body) + 1):end])
end

# The steps below the content of `card` that `rest`, steps below what the card draws,
# name: past the field of the view that holds the content; `nothing` for a part that
# only the view keeps.
function _find_view_content_steps(card::DashboardCard, rest)
    view = _get_card_view(card)
    (view === card.content || isempty(rest) || first(rest) isa ProjectionReferenceStep) && return rest
    content = get_content_path(view, Reference(rest...))
    content === nothing && return nothing
    content isa ConcreteReference ? Tuple(get_reference_steps(strip_reference_types(content))) : ()
end

function map_reference_forward(p::DashboardToWidget, iomap, reference)
    iomap === nothing && return invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
    field = _map_title_field_path(reference)
    field === nothing ||
        return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), FieldReferenceStep("children"),
                                                                       RangeReferenceStep(0, 1), get_reference_steps(field)...))
    if reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        if length(steps) >= 2 && steps[1] == FieldReferenceStep("cards") && steps[2] isa RangeReferenceStep
            k = steps[2].stop
            k <= length(iomap.input.cards) || return nothing
            j = _get_shown_index(iomap.input, k)
            j === nothing && return nothing
            (r, i) = _get_card_place(_get_shown_cards(iomap.input), j, _get_grid_columns(iomap.output))
            card_steps = (_DASHBOARD_GRID_STEPS..., _make_row_steps(r)..., _make_card_steps(i)...)
            # The card itself, and its title, are the widget of the card.
            (length(steps) == 2 || steps[3] == FieldReferenceStep("title")) &&
                return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), card_steps...))
            steps[3] == FieldReferenceStep("content") &&
                return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), card_steps...,
                    FieldReferenceStep("content"), _make_card_view_steps(iomap.input.cards[k], steps[4:end])...))
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
            found = _find_card_below(get_reference_steps(rest))
            j = found === nothing ? nothing :
                _find_card_at(_get_shown_cards(iomap.input), found[1], found[2], _get_grid_columns(iomap.output))
            k = j === nothing ? nothing : _get_card_index(iomap.input, j)
            if k !== nothing
                card_steps = (FieldReferenceStep("cards"), ElementReferenceStep(k))
                inside = found[3]
                isempty(inside) && return extend_reference(EmptyReference(), card_steps...)
                first(inside) == FieldReferenceStep("title") &&
                    return extend_reference(EmptyReference(), card_steps..., FieldReferenceStep("title"))
                if first(inside) == FieldReferenceStep("content")
                    below = _find_card_content_steps(iomap.input.cards[k], inside[2:end])
                    below === nothing && return nothing
                    return extend_reference(EmptyReference(), card_steps..., FieldReferenceStep("content"), below...)
                end
            end
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# An edit that a verb routes to `cards`, such as `insert_elements!` and
# `delete_elements!`, goes up with the change of what the dashboard holds. The
# generic bridge does not follow such a route into a field that no part of the page
# draws, so the reader takes the edit here. A gesture builds its edit with the
# change already (`_add_card_holds`).
const _CARDS_STEP = FieldReferenceStep("cards")

function read_intent(p::DashboardToWidget, recursion, change::Intent, iomap)
    route = change.route isa ConcreteReference ? Tuple(get_reference_steps(strip_reference_types(change.route))) : ()
    (change.operation !== nothing && route == (_CARDS_STEP,)) ||
        return invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    operation = _add_card_holds(iomap.input, reroot_operation(change.operation, route))
    Intent(change.gesture, operation, change.description, change.domain)
end

function make_graphics_projection(::Type{<:Dashboard}; measure, appearance)
    theme = get_scaled_theme!(appearance, WidgetTheme)
    ChainingProjection(
        DashboardToWidget(; gap = get_widget_style(theme, :section_gap),
                          card_chrome = _measure_card_chrome(theme, measure),
                          title_style = make_theme_cell(StyleText, theme,
                                                        values -> StyleText(values.title_font, values.foreground))[]),
        VerticalLayoutToGraphicsCanvas())
end

# The height that a card draws around its content: the height of a card with a
# title and no content.
_measure_card_chrome(theme, measure) =
    Int(print_document(WidgetCardToGraphicsCanvas(theme; measure), nothing, WidgetCard(; title = "Card"),
                       PrinterContext()).output.h[])
