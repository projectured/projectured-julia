"""
    SequenceChartModule

The sequence chart document domain: lanes with occurrences on them, arrows
between those occurrences, and a mapping from time to a readable axis.

A sequence chart answers one question — *what happened where, in what order, and
what caused what* — and it answers it for anything with participants and
messages: a simulation trace, a protocol exchange, a distributed system's logs,
a UML interaction. So this domain knows only the shapes that question needs:

- an **axis** is a lane, something occurrences happen to;
- an **event** is an occurrence on a lane at a time;
- an **arrow** connects two events, one causing the other;
- a **band** is a value a lane holds between two moments;
- a **kind** says how a class of events or arrows looks.

Nothing here is specific to any of those sources. The features that *are*
specific — module hierarchies that fold, filters that hide events, message
taxonomies, the semantics of a "send" — belong to domains **upstream** of this
one, which print a sequence chart the way the json domain prints syntax. An
upstream domain hides a class of arrows by clearing a kind's `visible`; it folds
a subtree of modules by printing a different lane list; it summarises a filtered
chain by printing one arrow whose kind is `elided`. This file never learns what
a module is.

Bulk data — the event and arrow tables — is held as whole column vectors, one
reactive cell per column, exactly as chart series are: a column is bulk leaf
data, not navigable structure, and per-row cells would cost far more than they
buy. Reassigning a column is what repaints, which is also how a live producer
feeds a growing chart.
"""
module SequenceChartModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..OperationModule
using ..SelectionModule
using ..DomainModule

import ..ChartModule: default_color_cycle
import ..ReferenceModule: Reference, ConcreteReference, FieldReferenceStep,
                          ElementReferenceStep, EmptyReference,
                          annotate_reference_types, get_reference_node_type
import ..OperationModule: CompoundOperation, ReplaceReferencedValueOperation,
                          ReplaceSelectionOperation

export SequenceChartAxis, SequenceChartEvents, SequenceChartArrows,
       SequenceChartBandSeries, SequenceChartEventKind, SequenceChartArrowKind,
       SequenceChartTimeline, SequenceChartGutter, SequenceChartStyle, SequenceChart,
       event_count, arrow_count, axis_display_order, event_axis, event_kind,
       arrow_kind, arrow_source_axis, arrow_target_axis,
       event_label, arrow_label, band_state_name,
       insert_events, delete_events, delete_axis, move_axis

@domain SequenceChart

# ── Axes ─────────────────────────────────────────────────────────────────

"""
A lane: one participant, one horizontal (or vertical) line, and everything that
happened to it.

`bands` are the state strips drawn along the lane — usually none or one. A
`nothing` `color` takes the projection's theme default.
"""
@document struct SequenceChartAxis <: SequenceChartDocument
    label::String
    bands::CellVector = CellVector()
    color::Any = nothing
    visible::Bool = true
end

function SequenceChartAxis(label::AbstractString, bands::AbstractVector;
                           color=nothing, visible::Bool=true)
    SequenceChartAxis(String(label), CellVector(bands), color, visible, nothing)
end

SequenceChartAxis(label::AbstractString; color=nothing, visible::Bool=true) =
    SequenceChartAxis(String(label), CellVector(), color, visible, nothing)

# ── Events ───────────────────────────────────────────────────────────────

"""
Every occurrence in the chart, as parallel columns. The row index is an event's
identity: arrows name their endpoints by it, bands anchor to it.

Rows must ascend by `times`. That order is not a convenience — the `:step` and
`:nonlinear` timeline mappings walk it cumulatively, so it *is* the sequence the
chart shows.

`ordinals` earns its place twice. An upstream filter that drops events keeps the
original numbers here, so `:ordinal` mode still shows a gap where something was
hidden rather than closing ranks. And rows sharing an ordinal share one timeline
coordinate, which is how a single occurrence appears on several lanes — an
initialization step that touches every participant at once — without consuming
several slots.
"""
@document struct SequenceChartEvents <: SequenceChartDocument
    times::Any = Float64[]
    axes::Any = Int[]
    kinds::Any = Int[]
    labels::Any = nothing
    ordinals::Any = nothing
end

function SequenceChartEvents(times::AbstractVector, axes::AbstractVector;
                             kinds=Int[], labels=nothing, ordinals=nothing)
    SequenceChartEvents(times, axes, kinds, labels, ordinals, nothing)
end

"""
    event_count(events) -> Int

How many rows the table really has: the shortest of the columns that must be
present, so a half-written table renders what it can instead of throwing.
"""
event_count(e::SequenceChartEvents) = min(length(e.times), length(e.axes))

"""
    event_axis(events, i) -> Int

Which lane row `i` sits on, by lane *identity* (its index in `chart.axes`), not
by display position.
"""
event_axis(e::SequenceChartEvents, i::Integer) = i <= length(e.axes) ? Int(e.axes[i]) : 0

"""
    event_kind(events, i) -> Int

Row `i`'s kind index, or `0` when the table leaves kinds unset — which the
projection draws with the domain's default mark.
"""
event_kind(e::SequenceChartEvents, i::Integer) = i <= length(e.kinds) ? Int(e.kinds[i]) : 0

"""
    event_label(events, i) -> String | nothing

Row `i`'s label, when the table carries any.
"""
event_label(e::SequenceChartEvents, i::Integer) =
    e.labels === nothing || i > length(e.labels) ? nothing : String(e.labels[i])

# ── Arrows ───────────────────────────────────────────────────────────────

"""
Every causal connection, as parallel columns over event row indices.

Arrows connect *events*, not times: outside `:time` mode a bare time names a
range of the axis rather than a point, so only an occurrence pins an end of an
arrow unambiguously.

`source_axes`/`target_axes` override which lane an end attaches to, `0` or
`nothing` meaning "the lane the event is on". That override is what lets an
upstream domain say "this send happened on the caller's lane even though the
event belongs to the callee", and what lets one initialization event fan out to
every lane it touched.
"""
@document struct SequenceChartArrows <: SequenceChartDocument
    sources::Any = Int[]
    targets::Any = Int[]
    kinds::Any = Int[]
    labels::Any = nothing
    source_axes::Any = nothing
    target_axes::Any = nothing
end

function SequenceChartArrows(sources::AbstractVector, targets::AbstractVector;
                             kinds=Int[], labels=nothing,
                             source_axes=nothing, target_axes=nothing)
    SequenceChartArrows(sources, targets, kinds, labels, source_axes, target_axes, nothing)
end

"""
    arrow_count(arrows) -> Int

How many arrows the table really has — the shorter of the two endpoint columns.
"""
arrow_count(a::SequenceChartArrows) = min(length(a.sources), length(a.targets))

"""
    arrow_kind(arrows, k) -> Int

Arrow `k`'s kind index, or `0` for the default.
"""
arrow_kind(a::SequenceChartArrows, k::Integer) = k <= length(a.kinds) ? Int(a.kinds[k]) : 0

"""
    arrow_label(arrows, k) -> String | nothing

Arrow `k`'s label, when the table carries any.
"""
arrow_label(a::SequenceChartArrows, k::Integer) =
    a.labels === nothing || k > length(a.labels) ? nothing : String(a.labels[k])

"""
    arrow_source_axis(arrows, events, k) -> Int
    arrow_target_axis(arrows, events, k) -> Int

Which lane an arrow's end attaches to: its override when the table carries one,
otherwise the lane of the event it starts or finishes at.
"""
function arrow_source_axis(a::SequenceChartArrows, e::SequenceChartEvents, k::Integer)
    override = _axis_override(a.source_axes, k)
    override != 0 && return override
    row = k <= length(a.sources) ? Int(a.sources[k]) : 0
    row == 0 ? 0 : event_axis(e, row)
end

function arrow_target_axis(a::SequenceChartArrows, e::SequenceChartEvents, k::Integer)
    override = _axis_override(a.target_axes, k)
    override != 0 && return override
    row = k <= length(a.targets) ? Int(a.targets[k]) : 0
    row == 0 ? 0 : event_axis(e, row)
end

_axis_override(column, k::Integer) =
    column === nothing || k > length(column) ? 0 : Int(column[k])

# ── Bands ────────────────────────────────────────────────────────────────

"""
A state strip along a lane: sample-and-hold, so `values[i]` holds from its own
moment until the next sample's.

`events` anchors a sample to an event row instead of to a bare time. That
matters wherever several events share a time: the raw time names the whole
zero-time region, while the state changed at one particular point inside it.

`states` names the values for display (`"IDLE"`, `"TRANSMIT"`), and `colors`
overrides the palette. Both are optional; a band with neither shows numbers in
cycled colors.
"""
@document struct SequenceChartBandSeries <: SequenceChartDocument
    times::Any
    values::Any
    events::Any = nothing
    states::Any = nothing
    colors::Any = nothing
end

function SequenceChartBandSeries(times::AbstractVector, values::AbstractVector;
                                 events=nothing, states=nothing, colors=nothing)
    SequenceChartBandSeries(times, values, events, states, colors, nothing)
end

"""
    band_state_name(band, value) -> String

What a band value reads as: its entry in `states` when there is one, else the
number itself.
"""
function band_state_name(b::SequenceChartBandSeries, value::Real)
    names = b.states
    names === nothing && return _number_label(value)
    index = round(Int, value) + 1        # states are listed from value 0 up
    (1 <= index <= length(names)) ? String(names[index]) : _number_label(value)
end

_number_label(v::Real) = begin
    f = Float64(v)
    isfinite(f) && f == round(f) ? string(round(Int, f)) : string(f)
end

# ── Kinds ────────────────────────────────────────────────────────────────

"""
A class of event and how it draws.

This is the seam an upstream domain styles the chart through: it classifies its
own occurrences — a send, a receive, a timer firing — and the chart renders
whatever the kind says, without knowing what any of those words mean.
"""
@document struct SequenceChartEventKind <: SequenceChartDocument
    name::String
    symbol::Symbol = :circle
    color::Any = nothing
    visible::Bool = true
end

function SequenceChartEventKind(name::AbstractString; symbol::Symbol=:circle,
                                color=nothing, visible::Bool=true)
    SequenceChartEventKind(String(name), symbol, color, visible, nothing)
end

"""
A class of arrow and how it draws.

`route` picks the shape: `:auto` arcs an arrow whose ends share a lane (a
straight line there would vanish into the lane) and draws every other one
straight. `elided` marks an arrow that stands for a chain of hidden steps rather
than a single one — the zigzag that tells a reader "something was filtered out
between these two points", which is what keeps a filtered chart honest.

`visible` is the whole of the show-and-hide story: an upstream domain that wants
its reuse arrows off by default ships them as a kind with `visible = false`.
"""
@document struct SequenceChartArrowKind <: SequenceChartDocument
    name::String
    color::Any = nothing
    line_style::Symbol = :solid
    arrowhead::Bool = true
    elided::Bool = false
    route::Symbol = :auto
    visible::Bool = true
end

function SequenceChartArrowKind(name::AbstractString; color=nothing,
                                line_style::Symbol=:solid, arrowhead::Bool=true,
                                elided::Bool=false, route::Symbol=:auto,
                                visible::Bool=true)
    SequenceChartArrowKind(String(name), color, line_style, arrowhead, elided,
                           route, visible, nothing)
end

# ── Timeline, gutter, style ──────────────────────────────────────────────

"""
How time becomes distance.

`:time` is faithful and often useless: real traces mix microseconds with
seconds, and a proportional axis can show one scale or the other, never both.
`:ordinal` spaces events by their number, `:step` gives each one equal room, and
`:nonlinear` compresses every gap through an arctangent so that the smallest
stays visible, the largest stays finite, and the order of their lengths survives.

`nonlinear_focus` is the gap length treated as typical (`nothing` derives it from
the data); `nonlinear_minimum` is the share of a slot even a zero-length gap
keeps, which is what gives same-time events room to be told apart.
"""
@document struct SequenceChartTimeline <: SequenceChartDocument
    mode::Symbol = :time
    nonlinear_focus::Any = nothing
    nonlinear_minimum::Float64 = 0.1
end

"""
The time scale drawn alongside the chart: tick marks and their labels, the
hairlines that carry a tick across the lanes, the readout that follows the
pointer, and the readout of the window's own extent.
"""
@document struct SequenceChartGutter <: SequenceChartDocument
    visible::Bool = true
    hairlines::Bool = true
    cursor_readout::Bool = true
    range_readout::Bool = true
end

"""
Chart-wide visual style. Every field defaults, so `SequenceChartStyle()`
constructs and a chart names only what it overrides. A `nothing` color or font
means "take the projection's theme default", resolved at print time.

The metric fields are the ones that change how the chart *reads* rather than how
it looks: `split_horizon_viewports` decides when an arrow is too long to draw
whole, `arc_height_buckets` how far neighbouring same-lane arcs separate, and
`zero_time_shading` whether the stretches where the clock stands still are
called out.
"""
@document struct SequenceChartStyle <: SequenceChartDocument
    background::Any = nothing
    axis_color::Any = nothing
    axis_label_font::Any = nothing
    label_font::Any = nothing
    gutter_background::Any = nothing
    tick_color::Any = nothing
    color_cycle::Any = default_color_cycle()
    event_radius::Int = 3
    arrow_width::Int = 1
    arrowhead_size::Int = 8
    arc_min_height::Int = 15
    arc_height_buckets::Int = 4
    split_horizon_viewports::Int = 3
    split_stub_px::Int = 80
    axis_spacing::Any = nothing
    zero_time_shading::Bool = true
    event_labels::Bool = false
    arrow_labels::Bool = true
    band_labels::Bool = true
end

# ── The chart ────────────────────────────────────────────────────────────

"""
A sequence chart: lanes, the occurrences on them, the arrows between those, the
kind tables that style them, and how time maps to distance.

`axes` is identity order — an event's `axes` column indexes into it — while
`axis_order` is the display permutation. Keeping the two apart means reordering
lanes never touches the event table.

`orientation` is `:horizontal` (time runs right, lanes stack down) or
`:vertical` (time runs down, lanes side by side — how a UML sequence diagram
reads). It costs the renderer nothing: everything is computed in flow-and-cross
terms and placed by one frame.
"""
@document struct SequenceChart <: SequenceChartDocument
    title::String = ""
    axes::CellVector = CellVector()
    events::Any = SequenceChartEvents()
    arrows::Any = SequenceChartArrows()
    event_kinds::CellVector = CellVector()
    arrow_kinds::CellVector = CellVector()
    axis_order::Any = nothing
    orientation::Symbol = :horizontal
    timeline::Any = SequenceChartTimeline()
    gutter::Any = SequenceChartGutter()
    style::Any = SequenceChartStyle()
end

function SequenceChart(title::AbstractString, axes::AbstractVector;
                       events=SequenceChartEvents(), arrows=SequenceChartArrows(),
                       event_kinds=Any[], arrow_kinds=Any[],
                       axis_order=nothing, orientation::Symbol=:horizontal,
                       timeline=SequenceChartTimeline(), gutter=SequenceChartGutter(),
                       style=SequenceChartStyle())
    SequenceChart(String(title), CellVector(axes), events, arrows,
                  CellVector(event_kinds), CellVector(arrow_kinds),
                  axis_order, orientation, timeline, gutter, style, nothing)
end

"""
    axis_display_order(chart) -> Vector{Int}

The lanes in the order they are drawn: the permutation when the chart carries a
valid one, otherwise the order they are listed in.

A permutation that has gone stale — the wrong length, or naming a lane twice —
is ignored rather than obeyed, so a half-finished edit degrades to the listed
order instead of dropping lanes off the picture.
"""
function axis_display_order(chart::SequenceChart)
    n = length(chart.axes)
    order = chart.axis_order
    order === nothing && return collect(1:n)
    length(order) == n || return collect(1:n)
    seen = falses(n)
    for value in order
        i = Int(value)
        (1 <= i <= n && !seen[i]) || return collect(1:n)
        seen[i] = true
    end
    Int[Int(value) for value in order]
end

# ── Editing ──────────────────────────────────────────────────────────────
#
# The tables are columns, so an edit is a column rewrite rather than an element
# insert — and because rows are addressed by index, a rewrite that shifts rows
# has to carry every index that pointed at them. These helpers own that
# bookkeeping so no caller has to reproduce it.

_field_reference(document, field::AbstractString) =
    annotate_reference_types(document,
        ConcreteReference(FieldReferenceStep(field), EmptyReference()))

# Rewrite a column through the row map `f`, keeping `nothing` columns absent.
_remap(column, f) = column === nothing ? nothing : [f(Int(v)) for v in column]

"""
    insert_events(chart, at, times, axes; kinds, labels, ordinals) -> Operation

Insert rows into the event table before row `at`, shifting everything after it
along — and with it every arrow endpoint and band anchor that named a shifted
row, so the chart stays consistent.
"""
function insert_events(chart::SequenceChart, at::Integer, times, axes;
                       kinds=nothing, labels=nothing, ordinals=nothing)
    events = chart.events
    n = event_count(events)
    at = clamp(Int(at), 1, n + 1)
    count = min(length(times), length(axes))
    count == 0 && return nothing

    shift(row) = row >= at ? row + count : row
    operations = Any[
        ReplaceReferencedValueOperation(events, "times",
            _splice(events.times, at, times, 0.0)),
        ReplaceReferencedValueOperation(events, "axes",
            _splice(events.axes, at, axes, 0)),
        ReplaceReferencedValueOperation(events, "kinds",
            _splice(events.kinds, at, kinds === nothing ? zeros(Int, count) : kinds, 0))]
    events.labels === nothing || push!(operations,
        ReplaceReferencedValueOperation(events, "labels",
            _splice(events.labels, at, labels === nothing ? fill("", count) : labels, "")))
    events.ordinals === nothing || push!(operations,
        ReplaceReferencedValueOperation(events, "ordinals",
            _splice(events.ordinals, at, ordinals === nothing ? collect(at:(at+count-1)) : ordinals, 0)))
    _push_row_remaps!(operations, chart, shift)
    CompoundOperation(operations)
end

"""
    delete_events(chart, rows) -> Operation

Delete event rows, and with them every arrow that ended at one — an arrow whose
cause or consequence is gone has nothing left to mean. Surviving indices are
renumbered.
"""
function delete_events(chart::SequenceChart, rows)
    events = chart.events
    n = event_count(events)
    doomed = Set{Int}(Int(r) for r in rows if 1 <= Int(r) <= n)
    isempty(doomed) && return nothing
    keep = [i for i in 1:n if !(i in doomed)]

    # New index of a surviving row; 0 for a deleted one.
    renumber = zeros(Int, n)
    for (new_index, old_index) in enumerate(keep)
        renumber[old_index] = new_index
    end
    map_row(row) = (1 <= row <= n) ? renumber[row] : 0

    operations = Any[
        ReplaceReferencedValueOperation(events, "times", _select(events.times, keep)),
        ReplaceReferencedValueOperation(events, "axes", _select(events.axes, keep)),
        ReplaceReferencedValueOperation(events, "kinds", _select(events.kinds, keep))]
    events.labels === nothing || push!(operations,
        ReplaceReferencedValueOperation(events, "labels", _select(events.labels, keep)))
    events.ordinals === nothing || push!(operations,
        ReplaceReferencedValueOperation(events, "ordinals", _select(events.ordinals, keep)))
    _push_arrow_deletions!(operations, chart, map_row)
    _push_band_remaps!(operations, chart, map_row)
    CompoundOperation(operations)
end

"""
    delete_axis(chart, index) -> Operation

Remove a lane, everything that happened on it, and the arrows that reached it.

Three index spaces have to survive this: the events' lane column, the arrows'
lane overrides, and the display permutation. Each is renumbered past the hole
rather than left pointing at the wrong lane.
"""
function delete_axis(chart::SequenceChart, index::Integer)
    n = length(chart.axes)
    index = Int(index)
    (1 <= index <= n) || return nothing
    events = chart.events

    doomed = [i for i in 1:event_count(events) if event_axis(events, i) == index]
    renumber_axis(lane) = lane > index ? lane - 1 : (lane == index ? 0 : lane)

    operations = Any[]
    deletion = delete_events(chart, doomed)
    deletion === nothing || append!(operations, deletion.operations)
    push!(operations, ReplaceReferencedValueOperation(events, "axes",
        [renumber_axis(Int(v)) for v in events.axes]))
    arrows = chart.arrows
    for field in ("source_axes", "target_axes")
        column = getproperty(arrows, Symbol(field))
        column === nothing && continue
        push!(operations, ReplaceReferencedValueOperation(arrows, field,
            _remap(column, lane -> lane == 0 ? 0 : renumber_axis(lane))))
    end
    order = chart.axis_order
    order === nothing || push!(operations,
        ReplaceReferencedValueOperation(chart, "axis_order",
            Int[renumber_axis(Int(v)) for v in order if Int(v) != index]))
    push!(operations, _delete_axis_element(chart, index))
    CompoundOperation(operations)
end

# The lane list is a CellVector of documents, so removing one is an element
# delete rather than a column rewrite.
function _delete_axis_element(chart::SequenceChart, index::Integer)
    remaining = Any[chart.axes[i] for i in 1:length(chart.axes) if i != index]
    ReplaceReferencedValueOperation(chart, "axes", CellVector(remaining))
end

"""
    move_axis(chart, from, to) -> Operation | Nothing

Move a lane to another position in the display order.

Only the permutation changes: an event still names its lane by identity, so
nothing about the data moves and no index needs repairing. Reordering lanes is
how a reader pulls two participants next to each other to see the traffic
between them, which is why it is cheap by design.
"""
function move_axis(chart::SequenceChart, from::Integer, to::Integer)
    order = axis_display_order(chart)
    n = length(order)
    from = Int(from); to = Int(to)
    (1 <= from <= n && 1 <= to <= n && from != to) || return nothing
    moved = order[from]
    deleteat!(order, from)
    insert!(order, to, moved)
    ReplaceReferencedValueOperation(chart, "axis_order", order)
end

# Arrows and bands both index event rows; an edit that renumbers rows renumbers
# them too.
function _push_row_remaps!(operations, chart::SequenceChart, f)
    arrows = chart.arrows
    push!(operations, ReplaceReferencedValueOperation(arrows, "sources", _remap(arrows.sources, f)))
    push!(operations, ReplaceReferencedValueOperation(arrows, "targets", _remap(arrows.targets, f)))
    _push_band_remaps!(operations, chart, f)
end

function _push_band_remaps!(operations, chart::SequenceChart, f)
    for i in 1:length(chart.axes)
        axis = chart.axes[i]
        for j in 1:length(axis.bands)
            band = axis.bands[j]
            band.events === nothing && continue
            push!(operations, ReplaceReferencedValueOperation(band, "events",
                _remap(band.events, f)))
        end
    end
end

# An arrow whose endpoint was deleted goes with it.
function _push_arrow_deletions!(operations, chart::SequenceChart, map_row)
    arrows = chart.arrows
    n = arrow_count(arrows)
    keep = [k for k in 1:n
            if map_row(Int(arrows.sources[k])) != 0 && map_row(Int(arrows.targets[k])) != 0]
    push!(operations, ReplaceReferencedValueOperation(arrows, "sources",
        [map_row(Int(arrows.sources[k])) for k in keep]))
    push!(operations, ReplaceReferencedValueOperation(arrows, "targets",
        [map_row(Int(arrows.targets[k])) for k in keep]))
    push!(operations, ReplaceReferencedValueOperation(arrows, "kinds",
        _select(arrows.kinds, keep)))
    for field in ("labels", "source_axes", "target_axes")
        column = getproperty(arrows, Symbol(field))
        column === nothing && continue
        push!(operations, ReplaceReferencedValueOperation(arrows, field, _select(column, keep)))
    end
end

# Column surgery. A column shorter than the table (`kinds` left empty, say) is
# padded on the way so the rewrite leaves every column the same length.
function _splice(column, at::Integer, inserted, pad)
    out = collect(Any, column)
    while length(out) < at - 1
        push!(out, pad)
    end
    for (offset, value) in enumerate(inserted)
        insert!(out, min(at + offset - 1, length(out) + 1), value)
    end
    _narrow(out)
end

_select(column, keep) = column === nothing ? nothing :
    _narrow(Any[column[i] for i in keep if i <= length(column)])

# Keep columns concretely typed: they are read a row at a time in the renderer's
# inner loops, and an Any column would box every value.
function _narrow(values)
    isempty(values) && return values
    all(v -> v isa Integer, values) && return Int[Int(v) for v in values]
    all(v -> v isa Real, values) && return Float64[Float64(v) for v in values]
    all(v -> v isa AbstractString, values) && return String[String(v) for v in values]
    values
end

end # module
