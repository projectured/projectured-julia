# Fragment of `ExplorerModule` — a dashboard card by itself, as a page: the card with
# its title, and below the title what the card draws of its content, which fills the
# rest of the page.
#
#     the card, title   children[1]
#     content.<rest>    children[1].content.children[1].child.<rest>
#
# The card draws its content, or the view that it keeps of its content, as a card of
# its dashboard does, and the path of the content goes through the field of the view
# that holds it.

"""
    DashboardCardToWidget(; card_chrome, title_style)

Draw a [`DashboardCard`](@ref) by itself, as the page of an explorer shows the card
that a person presses: the card with its title, and below the title what the card
draws in its dashboard ([`DashboardToWidget`](@ref)), its content or the view that
it keeps of its content, which fills the rest of the page. The content draws by the
view of its own type, so a press, a caret and a key in it reach that document. The
card has no button that fills the page, which it fills already, and no menu of its
size, which only a dashboard reads.

`card_chrome` is the height that the card draws around its content, and
`title_style` the text of its title, or `nothing`, as for `DashboardToWidget`.

A page that holds the card holds what the card draws ([`DashboardCard`](@ref)).
"""
@projection UntrackedCell struct DashboardCardToWidget <: Projection
    card_chrome::Int = 0
    title_style::Any = nothing
end

# The steps from the page to the widget of the card, and from that widget to what
# the card draws of its content.
const _LONE_CARD_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _LONE_CARD_BODY_STEPS = _CARD_BODY_STEPS[1:4]

function print_document(p::DashboardCardToWidget, recursion, card::DashboardCard, context)
    place = LayoutConstraint(_get_card_view(card); width = Fill)
    # A view of the content that the page makes after this print takes the place.
    set_cell_computation!(getfield(place, :child), () -> _get_card_view(card))
    _set_card_body_height!(p.card_chrome, place, :page, get_visible_height(context))
    body = VerticalLayout(Any[place]; child_width = Fill)
    title = WidgetLabel(card.title; text_style = p.title_style)
    set_cell_computation!(getfield(title, :content), () -> String(card.title))
    widget = WidgetCard(; title, content = body)
    root = VerticalLayout(Any[widget]; child_width = Fill)
    iomap = ChildrenIoMap(p, card, root, Cell(Any[]))
    set_output_path_computations!(root, card, path -> map_reference_forward(p, iomap, path); dormant = false)
    # A layout passes a key by its own selection, so each part carries the part of the
    # path of the page below it.
    for (part, below) in ((widget, ()), (body, _LONE_CARD_BODY_STEPS[1:1]), (place, _LONE_CARD_BODY_STEPS[1:3]))
        steps = (_LONE_CARD_STEPS..., below...)
        set_output_path_computations!(part, root, path -> _find_path_below(path, steps))
    end
    iomap
end

function map_reference_forward(p::DashboardCardToWidget, iomap, reference)
    (iomap === nothing || !(reference isa ConcreteReference)) &&
        return invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    # The title is the widget of the card, as in a dashboard.
    steps[1] == FieldReferenceStep("title") &&
        return annotate_reference_types(iomap.output, extend_reference(EmptyReference(), _LONE_CARD_STEPS...))
    steps[1] == FieldReferenceStep("content") ||
        return invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
    annotate_reference_types(iomap.output,
                             extend_reference(EmptyReference(), _LONE_CARD_STEPS..., _LONE_CARD_BODY_STEPS...,
                                              _make_view_content_steps(iomap.input, steps[2:end])...))
end

# A path in the title names the title, a path in what the card draws names the
# content, and the widget of the card names the card.
function map_reference_backward(p::DashboardCardToWidget, iomap, reference)
    if reference isa ConcreteReference
        rest = _find_path_below(strip_reference_types(reference), _LONE_CARD_STEPS)
        rest isa EmptyReference && return EmptyReference()
        if rest isa ConcreteReference
            inside = Tuple(get_reference_steps(rest))
            body = _LONE_CARD_BODY_STEPS
            first(inside) == FieldReferenceStep("title") &&
                return extend_reference(EmptyReference(), FieldReferenceStep("title"))
            if length(inside) < length(body)
                inside == body[1:length(inside)] &&
                    return extend_reference(EmptyReference(), FieldReferenceStep("content"))
            elseif inside[1:length(body)] == body
                below = _find_view_content_steps(iomap.input, inside[(length(body) + 1):end])
                below === nothing && return nothing
                return extend_reference(EmptyReference(), FieldReferenceStep("content"), below...)
            end
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function make_graphics_projection(::Type{<:DashboardCard}; measure, appearance)
    theme = get_scaled_theme!(appearance, WidgetTheme)
    ChainingProjection(
        DashboardCardToWidget(; card_chrome = _measure_card_chrome(theme, measure),
                              title_style = make_theme_cell(StyleText, theme,
                                                            values -> StyleText(values.title_font, values.foreground))[]),
        VerticalLayoutToGraphicsCanvas())
end
