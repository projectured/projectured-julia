# The sequence chart domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

<img width="900" alt="Sequencechart example" src="../../../asset/image/example/sequencechart.png">

A sequence chart answers one question — *what happened where, in what order, and
what caused what* — and it answers it for anything with participants and
messages: a simulation trace, a protocol exchange, a distributed system's logs,
a UML interaction.

The `sequencechart` slice knows only the shapes that question needs:

| Concept | Document | What it is |
| --- | --- | --- |
| lane | `SequenceChartAxis` | a participant: something occurrences happen to |
| occurrence | `SequenceChartEvents` (a row) | something that happened on a lane at a time |
| arrow | `SequenceChartArrows` (a row) | one occurrence causing another |
| state | `SequenceChartBandSeries` | a value a lane holds between two moments |
| kind | `SequenceChartEventKind`, `SequenceChartArrowKind` | how a class of occurrence or arrow looks |
| mapping | `SequenceChartTimeline` | how time becomes distance |
| scale | `SequenceChartGutter` | ticks, hairlines, readouts |

Nothing here is specific to any one source of traces. The features that *are* —
module hierarchies that fold, filters that hide events, the semantics of a
"send" — belong to domains **upstream** of this one, which print a sequence
chart the way the json domain prints syntax.

## The pipeline

```
SequenceChart ──SequenceChartToSequenceChartPlot──▶ SequenceChartPlot ──SequenceChartPlotToGraphics──▶ GraphicsCanvas
```

The first stage is thin: it wraps the chart in the document that carries what
*looking at* it means. The `SequenceChart` is pure content and serializes; the
`SequenceChartPlot` holds the window, the pointer, the hover and any drag, and
none of that belongs in a saved trace — a chart shown in two panes should be
able to be zoomed differently in each. The same split `ChartPlot` makes against
`Chart` and `GraphLayout` against `GraphGraph`.

## Time becomes distance before it becomes pixels

The middle stage of the coordinate pipeline is what separates a sequence chart
from a plot:

```
time ──(timeline mapping)──▶ timeline coordinate ──(scale over the window)──▶ flow pixel
```

Event times in a real trace span orders of magnitude — microseconds between two
protocol steps, seconds until the next timeout. A proportional axis can show one
or the other, never both. So the mapping is pluggable, through
`SequenceChartTimeline.mode`:

| Mode | What it does | When it helps |
| --- | --- | --- |
| `:time` | the coordinate *is* the elapsed time | when the interesting gaps are all of one size |
| `:ordinal` | spaces by an event's number | when a filter has hidden events and the holes matter |
| `:step` | one unit per event | when only the order matters |
| `:nonlinear` | compresses each gap through an arctangent | almost always, on a real trace |

`:nonlinear` gives each gap `c + (1 − c)·atan(Δt / focus)/(π/2)` units: never
less than `c`, never more than one, and strictly increasing in `Δt`. A
microsecond gap and a ten-second gap both stay visible, and which of two gaps is
longer is still readable off the picture even though their ratio is not.

Two consequences follow, and both are visible in the chart:

- **Zero-time regions.** Under any mapping but `:time`, events sharing an
  instant still occupy width — which is what makes a burst readable. Width
  normally reads as duration, so those stretches are shaded; without the shading
  the picture would lie about how long things took.
- **Honest tick labels.** A tick stands for a pixel, and a pixel stands for a
  span of time. Labels are rounded to the fewest digits that stay inside that
  span, and the leading digits every label shares are factored out into one
  prefix. Zooming in lengthens the labels on its own, exactly as far as the
  extra resolution earns.

## The window is anchored to an occurrence

`SequenceChartView` names the visible window as an offset and a span in
*timeline coordinates*, measured from the coordinate of an event row — not as a
pair of times, and not in pixels.

Times will not do. Inside a burst of events sharing one instant, both ends of
any sub-window are that same instant, so a pair of times cannot name a position
inside it — and zooming into a burst is exactly what the non-time mappings
exist for. Anchoring to an occurrence also keeps the window still when data
arrives behind it, which is what lets `follow_end` track a trace that is still
being written.

## Horizontal and vertical

`orientation` is `:horizontal` (time runs right, lanes stack down) or
`:vertical` (time runs down, lanes side by side — how a UML sequence diagram
reads). It costs the renderer nothing: everything is computed in **flow** and
**cross** terms, and `FlowFrame` maps that pair to pixels. Orientation is one
coordinate swap, not a branch in every drawing routine.

## Styling is data, not callbacks

A chart classifies its occurrences and arrows with small integer *kinds*, and
the kind documents carry the visual treatment. An upstream domain styles the
chart by the data it prints — it never implements a callback. One `visible`
flag per kind is also the whole of the show-and-hide story: hiding a class of
arrow is clearing one boolean.

## Cost

The amount of output is bounded by the size of the chart, not by the length of
what it shows:

- occurrences are decimated to one per lane, per kind, per mark-radius — a mark
  is a disc, and where events pack tighter than the disc is wide they paint
  ground already covered;
- arrows landing on one pixel column are kept only while they add cross-axis
  pixels the column does not already have;
- an arrow whose ends are further apart than the window is drawn as two stubs:
  at that length the line's angle carries no information and its middle is off
  screen anyway.

A twenty-thousand-event, twenty-thousand-arrow trace draws in under five
thousand graphics elements at 900 pixels wide, and hit testing walks what was
drawn rather than what exists.

The work is split across three cells by what invalidates it: the cumulative
timeline pass, the frame layout, and the drawable list. Hover, selection and the
cursor are read only by the last, so following the pointer across a long trace
rebuilds an overlay rather than a frame.

## Selection and navigation

Rows of a columnar table have no document of their own, so an occurrence or an
arrow is addressed with a `SequenceChartRowReferenceStep` — `.row(k)`, a
structural step naming a position inside the table, the same shape a chart
sample uses. The step evaluates to the row gathered back out of the columns.

The keyboard treats the chart as a graph rather than a picture:

| Gesture | What it does |
| --- | --- |
| `←` `→` | walk the chart's parts; once an occurrence is selected, walk the trace |
| `Shift+←` `Shift+→` | the previous or next occurrence **on the same lane** |
| `Ctrl+←` | follow an arrow back to what caused this |
| `Ctrl+→` | follow an arrow on to what this caused |
| `Ctrl+Shift+↑` `↓` | move the selected lane in the display order |
| wheel | zoom about the pointer; `Shift`, pan; over the lane labels, scroll the lanes |
| double click | back to the whole trace |

That `Ctrl` pair is the reason to have a sequence chart at all.

## Examples

- `sequencechart` — a request through client → gateway → service → cache, with a
  retry timer arcing off its own lane, a summarised chain marked as elided, and
  the service's state along its lane.
- `sequencechart_vertical` — the same trace read as a UML sequence diagram.
- `sequencechart_linear` — the same trace on a proportional axis, which is worth
  looking at precisely because it is hard to read: the five-second timeout
  pushes everything that happened in the first two milliseconds into a single
  column. This is the comparison that makes the nonlinear mapping's case.

## What is not here, and where it goes

Anything needing to know what a trace *means* belongs upstream:

| Feature | Where |
| --- | --- |
| module hierarchies, folding lanes, "open axes" | upstream — folding is a reprint that yields a different flat lane list |
| filtering, summarising a hidden chain | upstream — it prints an arrow whose kind is `elided`, and keeps the original numbers in `ordinals` so `:ordinal` spacing still shows the holes |
| message/send/reuse taxonomies | upstream — mapped onto kind tables and labels |
| gigabyte traces, lazy loading | upstream — it prints a bounded chart; a live source reassigns column cells |

Deferred inside this slice: call/return brackets with activation regions and
transmission-duration parallelograms (both need extra anchor columns on the
arrow table, not merely a new route), a kind legend, arrow-label collision
avoidance, and rubber-band drag zoom.
