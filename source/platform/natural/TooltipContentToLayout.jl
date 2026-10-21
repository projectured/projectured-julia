# Fragment of `NaturalModule` — the natural drawing of a tooltip window.

"""
    TooltipContentToVerticalLayout(; theme = nothing)

A `TooltipContent` as a column of one block, a frame around the layers, which the
natural projection draws: the content of each shown layer, and each re-enters the
natural projection in its own domain, so a tooltip can be prose, markdown, a table
or a widget. When more than one layer shows, each layer starts with a label that
names the part it comes from, and a separator stands between two layers. When the
window can show more or fewer layers, the last line names the keys that do it. A
tooltip is read, never edited, so the column maps no reference of its own.

The frame is the surface, the line and the padding of `theme`, a `TooltipTheme`
scaled or not, or of the default theme, and the column takes its gap. The frame
fits what it holds, so the window, which takes the extent of what it printed,
fits it too.
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
end

TooltipContentToVerticalLayout(; theme = nothing) =
    TooltipContentToVerticalLayout(get_tooltip_style(theme, :gap), get_tooltip_style(theme, :surface),
                                   get_tooltip_style(theme, :line), get_tooltip_style(theme, :line_width),
                                   get_tooltip_style(theme, :padding), get_tooltip_style(theme, :layer_text))

function print_document(p::TooltipContentToVerticalLayout, recursion, content::TooltipContent, ctx)
    layers = content.layers
    count = length(layers)
    shown = clamp(content.shown, 1, max(1, count))
    layer_text = unwrap_cell(p.layer_text)
    children = Any[]
    for (index, (title, document)) in enumerate(layers[1:min(shown, count)])
        index > 1 && push!(children, WidgetSeparator())
        shown > 1 && push!(children, WidgetLabel(title; text_style = layer_text))
        push!(children, document)
    end
    keys = _describe_layer_keys(shown, count)
    keys === nothing || push!(children, WidgetLabel(keys; text_style = layer_text))
    column = VerticalLayout(children; gap = unwrap_cell(p.gap))
    SimpleIoMap(p, content, VerticalLayout(Any[_make_tooltip_frame(p, column)]))
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

# The line that names the keys of the layers, `nothing` when one layer is all
# there is: the key of one more while the parts around have more to say, and the
# key of one fewer while more than one shows.
function _describe_layer_keys(shown::Int, count::Int)
    more = shown < count ? string(describe_gesture_pattern(WINDOW_LAYER_MORE_KEY), " shows ",
                                  count - shown, " more") : nothing
    fewer = shown > 1 ? string(describe_gesture_pattern(WINDOW_LAYER_FEWER_KEY), " shows one fewer") : nothing
    more === nothing ? fewer : fewer === nothing ? more : string(more, ", ", fewer)
end

"""
    make_natural_tooltip_row(; measure, appearance = Appearance()) -> Pair

The row that draws a tooltip window with the natural projection, for the
`opened_window_projections` of a host that keeps a tooltip window.
"""
make_natural_tooltip_row(; measure::TextMeasure, appearance::Appearance = Appearance()) =
    TooltipContent => NaturalToGraphics(measure = measure, appearance = appearance)
