# A graph lights the part under the pointer

> **Status (2026-10-02): pending, deferred.** Step 3 of
> [a-document-that-a-second-view-draws-gets-the-part-under-the-pointer.md](../done/a-document-that-a-second-view-draws-gets-the-part-under-the-pointer.md)
> (Q15) found this case. The owner deferred it to a plan of its own ("defer this
> to another plan"), so that the pointer work could finish. No source changed.

## The fault

A vertex of the topology card of an omnet simulation does not light under the
pointer. Found by reading the code; no test shows it yet.

## The facts (2026-10-02)

1. `SimulationTopologyToWidget` (omnet,
   `source/presentation/module/SimulationTopologyToWidget.jl`) makes a graph
   itself, `build_topology_graph(members, edges)`: a `GraphGraph` of
   `GraphVertex` items, each a `ModuleAppearance` or a `WidgetBadge`. It puts the
   graph into a `WidgetTransformPane` of its card. The graph is no part of the
   input of the view.
2. The view gives the widgets that it makes the part under the pointer with
   `follow_output_mouse_target!`, but its `is_followed` admits only widgets and
   layouts, so the walk leaves the graph out. The chain write does not reach the
   graph either, because no document of the input holds it. So the graph never
   holds the part under the pointer.
3. The graph domain of projectured (`source/domain/graph/`) handles no part under
   the pointer at all: `GraphToGraphLayout` and `GraphLayoutToGraphics` map no
   mouse target forward and draw no light. They draw only the explicit highlight,
   a ring around `highlight_vertex` and a line over `highlight_edge`
   (`GraphLayoutToGraphics.jl`, the colours in `GraphTheme.jl`).
4. A point on a vertex maps back to the content of the vertex
   (`GraphLayoutToGraphics.jl`, the backward map of a point).

So two pieces are missing, and each alone shows nothing: the topology view must
give the graph the part under the pointer, and the graph must draw it.

## The ways to do it

- **(a)** The walk of the topology view follows into the graph: `is_followed`
  leaves out only documents of the input, so the graph gets the rest of the path.
  One line in omnet, and a test that the graph holds the path.
- **(a′)** (a), and the graph domain draws a light: the graph view maps the part
  under the pointer from the graph to its layout and to its drawing, and draws a
  light ring around the vertex under the pointer, as it draws the highlight ring,
  in a colour of the theme apart from the highlight. Every graph in the editor
  then lights under the pointer, not only the topology. Tests in the graph domain
  and in omnet.
- **(b)** A documented limit only.

The owner chose (a) at first ("Agreed", 2026-10-02) on Claude's recommendation,
which assumed that the graph view lights a vertex; fact 3 showed that it does
not, and the owner then deferred the case here.

## Steps

- [ ] 1. The owner chooses (a), (a′) or (b).
- [ ] 2. A test that shows the fault: a sweep of moves over the topology card,
  as `test_view_lights` of omnet sweeps the other views.
- [ ] 3. The fix and its tests, in the order that the choice gives: projectured
  first, then omnet.
- [ ] 4. The documents: the limit in `mouse-target.md`, and the graph guide.
