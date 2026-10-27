# Fragment of `NaturalModule` — the natural drawing of a tooltip window.

"""
    TooltipContentToVerticalLayout(; theme = nothing)

A `TooltipContent` as a column of one block, a frame around the layers, which the
natural projection draws: the content of each shown layer, and each re-enters the
natural projection in its own domain, so a tooltip can be prose, markdown, a table
or a widget. When more than one layer shows, each layer starts with a label that
names the part it comes from, in the quiet text of a layer. When the
window can show more or fewer layers, the last line names the keys that do it. A
tooltip is read, never edited, so the column maps no reference of its own.

The frame is the surface, the line and the padding of `theme`, a `TooltipTheme`
scaled or not, or of the default theme, and the column takes its gap. The frame
fits what it holds, and it is at least as wide as the least width of the window,
`minimum_size` of the theme. So the window, which takes the extent of what it
printed and at least that width, is as wide as the frame.
"""
# Each field is a value of a `TooltipTheme`: a value, or a cell that reads the
# theme. The drawing reads them when it prints, so a change of the appearance
# shows at the next tooltip.
struct TooltipContentToVerticalLayout <: Projection
    gap::Any
    surface::Any
    line::Any
    line_width::Any
    padding::Any
    layer_text::Any
    minimum_size::Any
end

TooltipContentToVerticalLayout(; theme = nothing) =
    TooltipContentToVerticalLayout(get_tooltip_style(theme, :gap), get_tooltip_style(theme, :surface),
                                   get_tooltip_style(theme, :line), get_tooltip_style(theme, :line_width),
                                   get_tooltip_style(theme, :padding), get_tooltip_style(theme, :layer_text),
                                   get_tooltip_style(theme, :minimum_size))

function print_document(p::TooltipContentToVerticalLayout, recursion, content::TooltipContent, ctx)
    layers = content.layers
    count = length(layers)
    shown = clamp(content.shown, 1, max(1, count))
    layer_text = unwrap_cell(p.layer_text)
    children = Any[]
    for (title, document) in layers[1:min(shown, count)]
        shown > 1 && push!(children, WidgetLabel(title; text_style = layer_text))
        push!(children, document)
    end
    keys = describe_layer_keys(shown, count)
    keys === nothing || push!(children, WidgetLabel(keys; text_style = layer_text))
    column = VerticalLayout(children; gap = unwrap_cell(p.gap))
    # The least width of the window is the least width of the frame. A frame of
    # one line is higher than the least height of the window, so the height needs
    # no least.
    least_width = Int(unwrap_cell(p.minimum_size).x[])
    SimpleIoMap(p, content, VerticalLayout(Any[_make_tooltip_frame(p, column)];
                                           child_width = SizePolicy(least_width, nothing, nothing, 0.0)))
end

# The frame around what a tooltip says: the line, then the padding, both on the
# surface of the window.
function _make_tooltip_frame(p::TooltipContentToVerticalLayout, column)
    width = unwrap_cell(p.line_width)
    surface = unwrap_cell(p.surface)
    WidgetComposite(Any[column]; border = Inset(width, width, width, width),
                    padding = unwrap_cell(p.padding),
                    style = WidgetStyle(border_color = unwrap_cell(p.line),
                                        padding_color = surface, content_color = surface))
end

"""
    make_natural_tooltip_row(; measure, appearance = Appearance()) -> Pair

The row that draws a tooltip window with the natural projection, for the
`opened_window_projections` of a host that keeps a tooltip window.
"""
make_natural_tooltip_row(; measure::TextMeasure, appearance::Appearance = Appearance()) =
    TooltipContent => NaturalToGraphics(measure = measure, appearance = appearance)
