"""
    SequenceChartPlotModule

The sequence chart's presentation document: a `SequenceChart` plus everything
about *looking at* one — the window onto the timeline, where the pointer is,
what is hovered, a drag in progress.

None of that is chart content. A saved chart should not remember where someone
had scrolled to, and the same trace shown in two panes should be able to be
zoomed differently in each. So the interaction state lives here, on a document
the projection produces, the same split `ChartPlot` makes against `Chart` and
`GraphLayout` makes against `GraphGraph`.

`SequenceChartToSequenceChartPlot` builds one and keeps its identity across
reprints, so the view survives a data change — which is what lets a chart follow
a growing trace without the window jumping.
"""
module SequenceChartPlotModule

import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..SequenceChartModule: SequenceChartDocument

export SequenceChartView, sequence_chart_view_of, view_contains

"""
    SequenceChartView(anchor, offset, span)

The window onto the timeline, in **timeline coordinates anchored to an event**.

Not in pixels, because zooming a sequence chart is not magnifying a picture: at
a deeper zoom the ticks, the decimation and the labels all have to be recomputed.

And not in *time* either, which is the subtler point. Under every mapping but
`:time`, a run of events sharing one instant still occupies real width — that is
what makes a burst readable at all. A window named by two times cannot describe
a position *inside* such a run: both of its ends are the same instant. Since
zooming into a burst is precisely what the non-time mappings exist for, the
window is named by a coordinate `offset` and `span` measured from the coordinate
of event row `anchor`.

Anchoring to an event rather than to the origin also keeps the window still when
data arrives: appending events, or filtering some away, moves every absolute
coordinate, and a window pinned to an occurrence stays where the reader left it.
A plain immutable struct, not a document — a value a cell holds, and nothing
ever navigates into it.
"""
struct SequenceChartView
    anchor::Int
    offset::Float64
    span::Float64
end

SequenceChartView(anchor::Integer, offset::Real, span::Real) =
    SequenceChartView(Int(anchor), Float64(offset), Float64(span))

"""
    view_contains(view, anchor_coordinate, coordinate) -> Bool

Whether a timeline coordinate falls inside the window, given where the window's
anchor event currently sits.
"""
function view_contains(v::SequenceChartView, anchor_coordinate::Real, coordinate::Real)
    lo = Float64(anchor_coordinate) + v.offset
    lo <= Float64(coordinate) <= lo + v.span
end

"""
A sequence chart together with how it is currently being looked at.

- `chart` — the semantic `SequenceChart`, held by identity so selections
  round-trip.
- `view` — `nothing` to fit the whole trace, otherwise a `SequenceChartView`.
- `follow_end` — keep the window's end pinned to the newest event at the current
  zoom. This is what makes a chart usable against a trace that is still being
  written: the view has to move even though only the data changed.
- `cross_offset` — how far the lanes are scrolled, for when there are more of
  them than fit. A pure translation, so it moves the picture without disturbing
  the layout.
- `cursor` — the pointer, driving the gutter's time readout.
- `hovered` — a `Reference` naming the hovered event, arrow or lane.
- `drag_anchor` / `drag_rect` — pixel state while a rubber-band zoom or a pan is
  in progress, cleared when it commits or cancels.
"""
@document struct SequenceChartPlot <: SequenceChartDocument
    chart::Any
    view::Any = nothing
    follow_end::Bool = false
    cross_offset::Int = 0
    cursor::Any = nothing
    hovered::Any = nothing
    drag_anchor::Any = nothing
    drag_rect::Any = nothing
end

"""
    sequence_chart_view_of(plot) -> SequenceChartView | nothing

The plot's window, or `nothing` when it is fitting the whole trace. A
convenience so readers do not reach through the cell by hand.
"""
sequence_chart_view_of(plot::SequenceChartPlot) = plot.view

end # module
