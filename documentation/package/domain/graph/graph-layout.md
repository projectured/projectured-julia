# Graph layout

> **Kind:** reference · **Status:** current · **Stands on:** [graph.md](graph.md), [domain-inventory.md](../../design/domain-inventory.md)

How a graph gets from a list of vertices and edges to a picture: which engines
exist, what each one is, what a caller can ask of them, and which one runs when
the caller does not say.

## The seam

```julia
layout_graph(engine, graph, sizes, constraints; extent = nothing, border = 0)
    -> (positions, routes)
```

`sizes` maps a vertex to `(w, h)`; `positions` maps it to `(x, y, w, h)` with
`(x, y)` the top-left corner; `routes` maps an edge to a polyline. Every key is
an `objectid`, which keeps the call free of any reactive cell so
`GraphGraphToGraphLayout` can memoize it on topology, sizes and constraints.

`extent` is the box the caller has room for and `border` is the inset kept
inside it. They are arguments rather than engine fields because the same graph,
shown in two panes, needs two different layouts. The layouters of a C++ network
simulator take the same pair, as `setSize(width, height, border)`.

This package has no notion of what a domain is. An engine is told **what to satisfy**,
never **why**: that a module pinned by a display string must not move is the
caller's business, and what `:pin` means to an algorithm is this package's.

## The engines

| engine | what it is | node sizes | cost |
| --- | --- | --- | --- |
| `GridEmbedding` | rows and columns, or a ring inside an extent. No simulation. | honoured, never changed | instant |
| `FruchtermanReingoldLayout` | the force-directed placement of Fruchterman and Reingold (1991), written from the paper | carried: `k` and the distances come from the boxes | 0.13 s at 300 vertices |
| `AdaptagramsLayout` | libcola placement and libavoid routing, through a C shim | carried | native |
| `DeferredLayout` | becomes one of the above, or a registered engine, when the layout runs | — | — |

`AdaptagramsLayout` has a native dependency, so it lives in its own package and
reaches this one through `register_layout_engine!`. When its shim is not built
it says so once and hands each layout to the engine of this package. A package
can register any engine the same way, for example one that reproduces the
pictures of another program.

## The force-directed engine

`FruchtermanReingoldLayout` follows the paper: an edge pulls its two ends
together with `d²/k`, every pair of bodies pushes apart with `k²/d`, and a
temperature that falls each round caps how far a body moves. Four things are
added for the boxes that this package draws:

- **Sizes.** `k`, the ideal distance, is the mean size of a box plus `spacing`,
  and the forces read the distance between the rims of two bodies, so a large
  card gets the room it needs.
- **Constraints.** A pinned vertex is a body that does not move. A cluster is
  one body that carries its members at their offsets.
- **Parts that are not connected** feel a weak pull to the centre of the
  drawing, so no part drifts away from the others.
- **No overlap.** After the simulation, a pass pushes each two boxes that still
  overlap apart, along the axis where they overlap less.

With an extent and no pin, the centres are scaled into it, as every engine
here does. With a pin, the pin is a place in the extent, so the drawing keeps
its scale and every other body is moved just far enough to lie inside it.

## Which engine runs

`DeferredLayout` is what a caller names when it has no reason to name a specific
engine, and it determines **when the layout runs** rather than when the projection
is built. A projection is usually constructed at module load, long before an
optional engine package can be loaded.

With nothing registered it is `FruchtermanReingoldLayout`, for a graph of any
size. A registered engine takes over; `resolve_layout_engine(engine,
vertex_count)` passes the size of the graph, so a registered engine can draw a
small graph and a large one differently.

The layout says which one ran. `GraphLayout.engine` is `:grid`,
`:fruchterman_reingold`, or the name of a registered engine such as
`:adaptagrams`, so a view can tell a reader what it is looking at and a test can
assert the choice went the way it should have.

## Constraints

A `GraphConstraint` wraps a vertex with a `kind` and a `payload`.

| kind | payload | what the layout must do |
| --- | --- | --- |
| `:pin` | `(x, y)` | place this vertex at this corner and never move it |
| `:fixed_size` | `(w, h)` or `nothing` | use this size, and do not resize it |
| `:cluster` | `group` or `(group, offx, offy)` | this vertex belongs to a family that moves as one body, with its centre at this offset from the family |
| `:align` | — | not implemented by anything |
| `:same_rank` | — | not implemented by anything |
| `:min_separation` | — | not implemented by anything |

`:cluster` is how a vector of modules is laid out: 57 vertices and one anchor
point, so the row or the ring keeps its shape while the whole family finds its
place. Those C++ layouters have the same pair, as `addAnchoredNode` and
`addFixedNode`.

**An engine that does not implement a kind raises an error naming it**, and
the error lists what it does implement. That is deliberate: a caller cannot tell a satisfied pin from
an ignored one by looking at the picture, so accepting and dropping a constraint
is the worst of the three possible answers. Ask an engine what it takes with
`get_supported_constraint_kinds`.

## Determinism

The same graph answers the same positions, or nothing downstream can compare,
cache or screenshot a drawing:

- vertex order is the graph's own order (`layout_vertices`), and no `Dict`
  iteration reaches a coordinate;
- `FruchtermanReingoldLayout` starts on a sunflower spiral in that order, so it
  needs no random numbers, and two bodies on one point are pushed apart by the
  order of their indices;
- no engine here stops on elapsed time; a bound on the rounds bounds the work.

## Measuring

`graphlayoutbench()`, in `test/bench/graphlayoutbench.jl` and exported by [ProjecturedBench](../../../package/ProjecturedBench/), times every engine
over 10, 60 and 300 vertices and prints the answer as characters beside the
numbers. Run it before changing a constant, and again after.
