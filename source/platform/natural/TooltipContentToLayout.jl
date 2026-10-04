# Fragment of `NaturalModule` — the natural drawing of a tooltip window.

"""
    TooltipContentToVerticalLayout(; theme = nothing)

A `TooltipContent` as a column that the natural projection draws: the content of
each shown layer, and each re-enters the natural projection in its own domain, so a
tooltip can be prose, markdown, a table or a widget. When more than one layer
shows, each layer starts with a label that names the part it comes from, and a
separator stands between two layers. A tooltip is read, never edited, so the
column maps no reference of its own. The gap between the layers is the
`item_gap` of `theme`, a `WidgetTheme` scaled or not, or of the default theme.
"""
# `gap`, between the layers, is the `item_gap` of a `WidgetTheme`: a number, or a
# cell that reads the theme.
struct TooltipContentToVerticalLayout <: Projection
    gap::Any
end

TooltipContentToVerticalLayout(; theme = nothing) =
    TooltipContentToVerticalLayout(get_widget_style(theme, :item_gap))

function print_document(p::TooltipContentToVerticalLayout, recursion, content::TooltipContent, ctx)
    layers = content.layers
    shown = clamp(content.shown, 1, max(1, length(layers)))
    children = Any[]
    for (index, (title, document)) in enumerate(layers[1:min(shown, length(layers))])
        index > 1 && push!(children, WidgetSeparator())
        shown > 1 && push!(children, WidgetLabel(title))
        push!(children, document)
    end
    SimpleIoMap(p, content, VerticalLayout(children; gap = unwrap_cell(p.gap)))
end

"""
    make_natural_tooltip_row(; measure, appearance = Appearance()) -> Pair

The row that draws a tooltip window with the natural projection, for the
`opened_window_projections` of a host that keeps a tooltip window.
"""
make_natural_tooltip_row(; measure::TextMeasure, appearance::Appearance = Appearance()) =
    TooltipContent => NaturalToGraphics(measure = measure, appearance = appearance)
