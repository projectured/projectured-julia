# Sequence chart domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [chart.md](../chart/chart.md), [plot.md](../../platform/plot/plot.md)

`ProjecturedSequenceChart` draws what happened where, in which order, and what caused what: lanes of occurrences with arrows between them, for any source with participants and messages. This document says how time becomes distance before it becomes pixels, why the window is anchored to an occurrence, how the cost stays bounded, and what the domain leaves to the domains that print into it.

<img width="396" alt="Sequence chart example" src="../../../asset/image/example/sequencechart.png">

## How it works

### The documents

| Concept | Document | What it is |
| --- | --- | --- |
| lane | `SequenceChartAxis` | a participant, with its `bands` |
| occurrence | a row of `SequenceChartEvents` | something that happened on a lane at a time |
| arrow | a row of `SequenceChartArrows` | one occurrence that causes another |
| state | `SequenceChartBandSeries` | a value that a lane holds from one occurrence to the next |
| kind | `SequenceChartEventKind`, `SequenceChartArrowKind` | how a class of occurrence or arrow looks, and whether it shows |
| mapping | `SequenceChartTimeline` | how time becomes distance |
| scale | `SequenceChartGutter` | the ticks, the hairlines and the readouts |

`SequenceChart` holds these with a `title`, an `axis_order`, an `orientation` and a `style`. The event and arrow tables are columnar, one cell for each column, as the columns of a chart series are. The row index of an event is its identity: an arrow names its two ends by event row, and a band sample names the event that caused the change. The rows must ascend by time, because the `:step` and `:nonlinear` mappings walk them in order. An arrow joins two events and never two bare times, because outside the `:time` mode one time can cover a range of positions.

`axes` is the identity order, which the `axes` column of the event table indexes, and `axis_order` is the display order. So a reorder of the lanes does not touch the event table. `ordinals` keeps the original numbers of the events when a filter upstream drops some. Several rows can share one ordinal, so one occurrence can span several lanes.

**Styling is data.** An event or an arrow has a small integer kind, and the kind documents hold the colour, the symbol, the line style and the route. A domain that prints a sequence chart styles it with the data it prints, not with a callback. One `visible` flag on a kind hides that class of occurrence or arrow.

### The chain

```
SequenceChart ──SequenceChartToSequenceChartPlot──▶ SequenceChartPlot ──SequenceChartPlotToGraphicsCanvas──▶ GraphicsCanvas
```

The first stage wraps the chart in a `SequenceChartPlot`: the `view`, `follow_end`, the lane scroll `cross_offset`, and the `cursor`. These are the state of the view, and the reader marks each write of them as view state, so a history records no zoom, lane scroll or readout. The event or the arrow that the mouse target of the plot names lights. It keeps its identity across prints and maps a reference by one step, as `ChartToChartPlot` does; see [chart.md](../chart/chart.md#the-chain). The second stage does the layout, the gutter, the lanes, the arrow routes, the decimation and the reader.

The renderer splits its work into three cells by what makes each one stale: the cumulative timeline pass, the frame layout, and the element list. The hover, the selection and the cursor are read only by the last cell. So a pointer move over a long trace builds an overlay again, not the frame.

### Time becomes distance before it becomes pixels

```
time ──(timeline mapping)──▶ timeline coordinate ──(AxisScale over the window)──▶ flow pixel
```

The times of a real trace span orders of magnitude: microseconds between two protocol steps, seconds until the next timeout. A proportional axis shows one scale or the other. So `get_timeline_coordinates` makes the mapping a choice, through `SequenceChartTimeline.mode`:

| Mode | The coordinate | Use it when |
| --- | --- | --- |
| `:time` | the elapsed time | the gaps of interest are of one size |
| `:ordinal` | the number of the event | a filter hid events and the holes matter |
| `:step` | one unit for each event | only the order matters |
| `:nonlinear` | each gap compressed through an arctangent | the trace is real; this is the usual case |

`:nonlinear` gives each gap `c + (1 − c)·atan(Δt / focus)/(π/2)` units, where `c` is `nonlinear_minimum`. A gap is never less than `c` and never more than one, and a longer gap is always wider. So a microsecond gap and a ten-second gap both show, and their order stays readable.

Two visible results follow:

- **Zero-time regions.** Outside `:time`, events at one instant still take width. Width reads as duration, so the renderer shades those regions.
- **Honest tick labels.** A tick label has the fewest digits that the time span of one pixel needs, and the leading digits that all labels share go into one prefix. A zoom makes the labels longer by exactly the resolution it adds.

### The window is anchored to an occurrence

`SequenceChartView(anchor, offset, span)` names the window as an offset and a span in timeline coordinates, from the coordinate of the event row `anchor`. It is not a pair of times: inside a burst of events at one instant, both ends of a smaller window are the same time, so two times can not name a position there. The anchor also keeps the window still when events arrive behind it, and `follow_end` pins the end of the window to the newest event for a trace that is still being written.

### Horizontal and vertical

`orientation` is `:horizontal`, time to the right and lanes down, or `:vertical`, time down and lanes side by side as in a UML sequence diagram. The renderer computes in **flow** and **cross** coordinates, and `FlowFrame` is the one place that maps them to x and y. So the orientation is one swap of coordinates, not a branch in each drawing function.

### Selection and navigation

A row of a table has no document of its own. `SequenceChartRowReferenceStep`, written `.row(k)`, names a row inside the event table, the arrow table or a band. It is the same idiom as the sample step of the chart; [chart.md](../chart/chart.md#a-reference-step-into-a-column) describes it. `evaluate_reference_step` gathers the row back out of the columns. `get_event_reference`, `get_arrow_reference` and `get_band_reference` build the typed paths.

A click selects the most specific thing under the pointer: an event before an arrow, an arrow before a band, a band before a lane. The keyboard treats the chart as a graph, not as a picture:

| Gesture | What it does |
| --- | --- |
| `←` `→` | move between the parts; with an event selected, move along the trace |
| `Shift+←` `Shift+→` | the previous or next event on the same lane |
| `Ctrl+←` | follow the arrow back to the cause |
| `Ctrl+→` | follow the arrow on to the consequence |
| `Ctrl+Shift+↑` `Ctrl+Shift+↓` | move the selected lane in the display order |
| `Alt+Delete` | remove the selected lane |
| wheel; `Shift`+wheel; wheel over the lane labels | zoom about the pointer; pan; scroll the lanes |
| double click | show the whole trace again |

### Cost

The amount of output depends on the size of the chart, not on the length of the trace. `SequenceChartGeometry.jl` holds the arithmetic, with `AxisScale` and the ticks of [plot.md](../../platform/plot/plot.md):

- `decimate_events` keeps one mark for each lane, kind and mark radius, because events closer than the width of a mark paint pixels that are already painted.
- `deduplicate_arrow_coverage` keeps an arrow on a pixel column only while it adds cross-axis pixels that the column does not have.
- `split_arrow` draws an arrow whose ends are farther apart than the window as two stubs. At that length the angle of the line carries no information.

`test_sequencechart_scale()` draws a trace of 20,000 events on eight lanes at 900 pixels wide in fewer than 6,000 graphics elements, and 20,000 spread arrows in fewer than 8,000. A zoom to ten events draws every one of them. A click tests what was drawn, not what exists.

### The theme

`SequenceChartTheme` holds what `SequenceChartPlotToGraphicsCanvas` draws when the
document says nothing: the colors of the backgrounds, the axis, the text, the
gutter and its border, the hairlines, the shading of time zero, an arrow, an
event, a selection and the hover, the title, axis and label fonts, and the
padding, the padding of the gutter, the gap of a label, the spacing of the ticks
and of the lanes, the offset of a lane and the height of a band. A value that
`SequenceChartStyle`, a kind or an axis sets keeps its priority; the labels of the
events, the arrows and the bands draw with `label_font`. The printer takes
`theme`, holds all its values as one style field, reads it once at each print,
and gives the tuple to its layout. The sequence chart has no natural
registration, so a builder passes the theme.

## How it fits

`ProjecturedSequenceChart` depends on the kernel and the platform. No package of this repository depends on it. It is a target language: a domain upstream, such as a trace of a simulation or a protocol log, prints a sequence chart as the JSON domain prints syntax.

It has no `__init__` and registers nothing. A caller builds the chain, or adds `SequenceChart => make_sequencechart_pipeline_example()` to the `extra` table of `NaturalToGraphics`.

## Design decisions

- **A strict boundary with the domains upstream.** The chart holds lanes, events, arrows, bands, kinds and a timeline. A feature that needs to know what a trace means goes upstream and must be expressible without a change to this domain. See [plan/done/sequence-chart-domain.md](../../../../plan/done/sequence-chart-domain.md).
- **The timeline mapping is a choice.** A proportional axis can not show a microsecond and ten seconds on one screen. See [plan/done/sequence-chart-domain.md](../../../../plan/done/sequence-chart-domain.md).
- **The window names an occurrence, not a time.** Inside a zero-time burst, a pair of times can not name a sub-window.
- **Columnar tables.** A hundred thousand occurrences do not become a hundred thousand cells. A row is a reference step, not a child.
- **Identity order and display order are separate.** A reorder of the lanes writes `axis_order` and leaves the event table alone.

The features that go upstream:

| Feature | Where it goes |
| --- | --- |
| module hierarchies, lanes that fold | upstream: a fold is a new print with a different flat list of lanes |
| filters, a summary of a hidden chain | upstream: it prints an arrow of an `elided` kind and keeps the original numbers in `ordinals` |
| message, send and reuse taxonomies | upstream: kind tables and labels |
| very large traces, lazy loading | upstream: it prints a bounded chart, and a live source writes new columns |

## Usage

```julia
axes = Any[SequenceChartAxis("client"), SequenceChartAxis("server")]
events = SequenceChartEvents([0.0, 0.0008, 0.2, 5.0], [1, 2, 2, 1]; labels = ["GET", "parse", "reply", "done"])
arrows = SequenceChartArrows([1, 3], [2, 4]; labels = ["request", "200 OK"])
chart = SequenceChart("request", axes; events = events, arrows = arrows,
                      timeline = SequenceChartTimeline(; mode = :nonlinear))
projection = ChainingProjection(SequenceChartToSequenceChartPlot(),
                                SequenceChartPlotToGraphicsCanvas(measure = FontFileMeasure()))
```

- Examples: `sequencechart`, a request through four tiers with a retry timer, an elided chain and a state band; `sequencechart_vertical`, the same trace as a UML diagram; `sequencechart_linear`, the same trace on a proportional axis, which shows why `:nonlinear` exists; `sequencechart_pair` and `sequencechart_inspector`. All are in `example/domain/sequencechart/`. The atomic catalog has `sequencechart/plot`.
- Test: `test_sequencechart()` runs the layering guard, `test_sequencechart_geometry()`, `test_sequencechart_projection()`, `test_sequencechart_scale()` and `test_sequencechart_selection()`.

## Limits

- Not built: call and return brackets with activation regions, transmission-duration parallelograms, a legend of the kinds, labels that avoid each other, and a rubber-band zoom. The brackets and the parallelograms need more anchor columns on the arrow table. [plan/done/sequence-chart-domain.md](../../../../plan/done/sequence-chart-domain.md) lists them as deferred.
- `SequenceChartPlot.drag_anchor` and `drag_rect` are fields that no reader writes.
- An arrow drawn as two stubs shows no angle, and a long arrow label can cover another one.
