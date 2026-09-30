# A view of your own data

> **Kind:** procedure · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

How to put your own Julia values on the screen: a view you design from widgets and domain views, and a view on demand that ProjecturEd makes from the value itself. Every call here runs in a session started with `julia --project=environment/all`.

## A view on demand, in one call

The shortest way to see a value is to ask for a window on it:

```julia
using Projectured, ProjecturedExample, ProjecturedSdl

struct Point; x::Int; y::Int; end
run_value_viewer(Dict("origin" => Point(0, 0), "points" => [Point(1, 2), Point(3, 4)]))
```

The window shows a tree. A node that holds more opens with a click on its chevron, so a large value, a value that refers to itself, and an object that a task still writes all cost what is on the screen and no more.

Two keywords say how much the first frame holds:

```julia
run_value_viewer(my_object; depth = 3, elements = 50)   # three levels, fifty elements
run_value_viewer(my_object; tree = false)               # the flat view of the value
```

`tree = false` draws the value itself instead of a reflected tree. It reads every field it reaches, so use it for a small value. It does not draw a dictionary.

`make_value_viewer(value)` returns the document and the projection, for a caller that puts the view in a window of its own. Give that editor the feeds of `make_value_viewer_feeds(document, value)` too: a chevron only asks for the next level, and the feed fetches it.

## A view of a running program

The same call takes an object that your program is using, for example the editor itself:

```julia
run_value_viewer(editor; depth = 2)
```

The tree is a shadow of the object, not a copy of it: `sync_reflection!` brings the shadow up to date, and the nodes that are already open keep their place. The window runs that sync on each frame, so a change of the object shows at the next input.

## A view you design

A designed view is a projection: a printer that makes the view, and a reader that maps an edit back. The short way to a designed view is a document type of your own and the widget projections.

1. **Write the data as a document.** The `@document` macro makes each field a reactive cell, so a change of a field repaints the view that reads it.

   ```julia
   @document struct Measurement <: Document
       name::String
       value::Float64
   end
   ```

2. **Write the projection.** The [widget guide](../package/platform/widget/widget.md) lists the parts: labels, fields, tables, cards, buttons, tabs and split panes. [new-domain-guide.md](new-domain-guide.md) is the long form, from the document types to the key bindings.

3. **Open it.** `run_example` takes the document and the projection you built:

   ```julia
   run_example(document, projection; name = "measurement")
   ```

   The three steps above are the shape of the work, not a script to paste: step
   2 is where your own projection is written, and [new-domain-guide.md](new-domain-guide.md)
   walks one from the first document type to the key bindings.

A designed view and a view on demand live in the same window: open your model in one tab, and a value of the running program in the next.

## A chart of your numbers

A chart is a document, so it goes on the screen the same way, and a data point can be selected like any other part. [chart.md](../package/domain/chart/chart.md) says which chart kinds exist and how a series is built.

## Where to go next

- [own-project-guide.md](own-project-guide.md) — use ProjecturEd from your own project, and which package to load.
- [new-domain-guide.md](new-domain-guide.md) — a domain of your own: documents, projections, operations and key bindings.
- [examples-tour.md](examples-tour.md) — the examples, and what each one shows.
