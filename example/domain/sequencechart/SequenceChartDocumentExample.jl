# A request travelling through a three-tier service, and the same trace drawn
# the other way round.
#
# The data is written out rather than generated, because the point of the
# example is the *shapes* a sequence chart has to draw: a burst of events
# sharing one instant, a long quiet gap after it, a message that comes back to
# the lane it left, a chain that was summarised because something in between was
# filtered away, and a lane whose state changes underneath the traffic.
#
# Times are seconds and deliberately span four orders of magnitude — from the
# 200 microseconds of a cache lookup to the five seconds of a client timeout.
# That spread is exactly what the nonlinear timeline exists for, and a linear
# axis would collapse the whole first half of this chart onto one pixel.

# The kinds a service trace distinguishes, and how each reads.
function _service_arrow_kinds()
    Any[
        SequenceChartArrowKind("call"; color=color_solarized_blue),
        SequenceChartArrowKind("return"; color=color_solarized_green, line_style=:dashed),
        # A timer is a message a participant sends to itself, so it arcs off its
        # own lane and comes back.
        SequenceChartArrowKind("timer"; color=color_solarized_orange,
                               line_style=:dotted, route=:arc),
        # An elided arrow stands for a chain of steps that were filtered out —
        # the zigzag keeps the picture from claiming a directness it lacks.
        SequenceChartArrowKind("elided"; color=color_solarized_violet,
                               line_style=:dashed, elided=true),
    ]
end

function _service_event_kinds()
    Any[
        SequenceChartEventKind("receive"; symbol=:circle, color=color_solarized_blue),
        SequenceChartEventKind("send"; symbol=:diamond, color=color_solarized_green),
        SequenceChartEventKind("timeout"; symbol=:triangle_up, color=color_solarized_red),
    ]
end

# The server's own state, as a strip along its lane: the value holds until the
# next sample, and each sample is pinned to the event that caused the change so
# the edge lands exactly even inside the burst.
_service_band() = SequenceChartBandSeries(
    [0.0, 0.0012, 0.0016, 0.2, 5.0], [0, 1, 2, 0, 3];
    events=[1, 3, 5, 8, 11],
    states=["idle", "parsing", "waiting", "sending"])

"""
    make_sequencechart_document_example() -> SequenceChart

A request through client → gateway → service → cache, with a retry timer, a
summarised chain and the service's state along its lane. The registered
`sequencechart` example, and what the domain guide's screenshot shows.
"""
function make_sequencechart_document_example(; orientation::Symbol=:horizontal)
    axes = Any[
        SequenceChartAxis("client"),
        SequenceChartAxis("gateway"),
        SequenceChartAxis("service", Any[_service_band()]),
        SequenceChartAxis("cache"),
    ]

    #                 1       2       3       4       5       6       7       8      9      10     11     12
    times      = [ 0.0,    0.0008, 0.0012, 0.0014, 0.0016, 0.0016, 0.0021, 0.2,   0.2,   1.0,   5.0,   5.0]
    lanes      = [ 1,      2,      3,      4,      4,      3,      2,      3,     2,     1,     1,     2  ]
    kinds      = [ 2,      1,      1,      1,      2,      1,      1,      2,     1,     1,     3,     1  ]
    labels     = ["GET",  "route","parse","look", "miss", "fill", "relay","body","fwd", "recv","retry","re-route"]

    events = SequenceChartEvents(times, lanes; kinds=kinds, labels=labels)

    arrows = SequenceChartArrows(
        #  the request travelling in, the answer coming back, a retry, a summary
        [1, 2, 3, 4, 6, 8,  10, 11],
        [2, 3, 4, 5, 7, 9,  11, 12];
        kinds=[1, 1, 1, 2, 2, 2, 3, 4],
        labels=["GET /order", "route", "lookup", "miss", "assemble",
                "200 OK", "retry after 4s", "…via gateway"])

    SequenceChart("order request", axes;
        events=events, arrows=arrows,
        event_kinds=_service_event_kinds(), arrow_kinds=_service_arrow_kinds(),
        orientation=orientation,
        timeline=SequenceChartTimeline(; mode=:nonlinear))
end

"""
    make_sequencechart_vertical_document_example() -> SequenceChart

The same trace with time running downward and the lanes side by side — the way a
UML sequence diagram reads. Nothing about the document changes but one symbol;
the renderer computes in flow-and-cross terms and the frame places them.
"""
make_sequencechart_vertical_document_example() =
    make_sequencechart_document_example(; orientation=:vertical)

"""
    make_sequencechart_linear_document_example() -> SequenceChart

The same trace on a proportional time axis, which is worth looking at precisely
because it is hard to read: the five-second timeout pushes everything that
happened in the first two milliseconds into a single column. This is the
comparison that makes the nonlinear mapping's case.
"""
function make_sequencechart_linear_document_example()
    chart = make_sequencechart_document_example()
    chart.timeline = SequenceChartTimeline(; mode=:time)
    chart
end

"""
    make_sequencechart_large_document_example() -> SequenceChart

Twenty thousand events across eight lanes: the example the scale tests measure
against, and a check that a chart stays legible when the trace stops being
something a person could have written out.
"""
function make_sequencechart_large_document_example()
    lane_count = 8
    n = 20_000
    times = Vector{Float64}(undef, n)
    lanes = Vector{Int}(undef, n)
    t = 0.0
    for i in 1:n
        # A deterministic walk with occasional bursts, so the trace has both
        # crowded and empty stretches without reaching for a random seed.
        t += (i % 97 == 0) ? 0.05 : (i % 7 == 0 ? 0.0 : 1.0e-4)
        times[i] = t
        lanes[i] = 1 + (i * 3 + i ÷ 11) % lane_count
    end
    sources = collect(1:(n-1))
    targets = collect(2:n)
    SequenceChart("busy trace",
        Any[SequenceChartAxis("node $i") for i in 1:lane_count];
        events=SequenceChartEvents(times, lanes),
        arrows=SequenceChartArrows(sources, targets),
        timeline=SequenceChartTimeline(; mode=:nonlinear))
end

"""
    make_sequencechart_inspector_document_example() -> WidgetSplitPane

A sequence chart beside a property form over one of its own lanes — the same
document shown two ways. Editing the lane's label in the form writes the cell
the chart draws from, so the chart repaints.

This is also what composability looks like from the outside: the chart is not
embedded by a bespoke pane, it is a document among documents, and the split pane
neither knows nor cares which of its children is which.
"""
function make_sequencechart_inspector_document_example()
    chart = make_sequencechart_document_example()
    WidgetSplitPane(:horizontal, Any[chart, chart.axes[3]]; sizes=[620, 300])
end

"Atomic document for the catalog: a sequence chart plot viewing the service trace."
make_sequence_chart_plot_document_example() = SequenceChartPlot(make_sequencechart_document_example())

"""
    make_sequencechart_pair_document_example() -> WidgetTable

The same trace drawn twice — once along a nonlinear timeline and once
proportionally — so the two mappings can be read side by side.

The proportional one is the argument for the other: a five-second timeout pushes
everything that happened in the first two milliseconds into a single column.
"""
function make_sequencechart_pair_document_example()
    WidgetTable(; column_headers = Any[], row_headers = Any[],
        cells = Any[Any[make_sequencechart_document_example()],
                   Any[make_sequencechart_linear_document_example()]],
        column_count = 1)
end
