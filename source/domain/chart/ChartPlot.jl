# Fragment of `ChartModule`.
#
# The chart's presentation document: a `Chart` plus everything about *looking at*
# it — the zoom window, the pointer position, an in-progress drag. The part under
# the pointer is its mouse target.
#
# None of that is chart content. A saved chart should not remember where someone
# had scrolled to, and the same chart shown in two panes should be able to be
# zoomed differently in each. So the interaction state lives here, on a document
# the projection produces, and is excluded from serialization by construction —
# the same split `GraphLayout` makes against `GraphGraph`, and the reason
# `SyntaxNode.collapsed` sits on the projected syntax tree rather than on the JSON
# being projected.
#
# `ChartToChartPlot` builds one of these and keeps its identity across reprints,
# so the view survives a data change.
"""
    ChartView(x_min, x_max, y_min, y_max)

A zoom window in **data** coordinates.

Zooming a chart is not zooming a picture: at a deeper zoom the ticks, the
gridlines and the decimation all have to be recomputed from the visible data
range, and more detail has to appear. Storing the window rather than a pixel
transform is what makes that fall out. On a category axis the x bounds are
continuous positions in category-index space.

A plain immutable struct, not a document — it is a value a cell holds, and
nothing ever navigates into it.
"""
struct ChartView
    x_min::Float64
    x_max::Float64
    y_min::Float64
    y_max::Float64
end

# @positional: the four of a view rectangle: x, y, width and height.
ChartView(x_min::Real, x_max::Real, y_min::Real, y_max::Real) =
    ChartView(Float64(x_min), Float64(x_max), Float64(y_min), Float64(y_max))

"""
    is_point_in_chart_view(view, x, y) -> Bool

Whether a data point falls inside the window.
"""
is_point_in_chart_view(v::ChartView, x::Real, y::Real) =
    v.x_min <= x <= v.x_max && v.y_min <= y <= v.y_max

"""
A chart together with how it is currently being looked at.

- `chart` — the semantic `Chart`, held by identity so selections round-trip.
- `view` — `nothing` to fit the data, otherwise a `ChartView` window.
- `cursor` — the pointer in data coordinates, or `nothing`; drives the crosshair.
- `drag_anchor` / `drag_rect` — pixel state while a rubber-band zoom or a pan is
  in progress, cleared when it commits or cancels. The anchor holds the point of
  the press, the mode, the window and the two axis scales at the press, and the
  `view` that the plot held at the press, which a cancelled pan puts back.
"""
@document struct ChartPlot <: ChartDocument
    chart::Any
    view::Any = nothing
    cursor::Any = nothing
    drag_anchor::Any = nothing
    drag_rect::Any = nothing
end

"""
    get_chart_view(plot) -> ChartView | nothing

The plot's window, or `nothing` when it is auto-fitting. A convenience so
readers do not reach through the cell by hand.
"""
get_chart_view(plot::ChartPlot) = plot.view
