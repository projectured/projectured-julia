# Graph layout

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

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
shown in two panes, needs two different layouts. This is the same pair OMNeT++ passes as
`GraphLayouter::setSize(width, height, border)`.

This package has no notion of what a domain is. An engine is told **what to satisfy**,
never **why**: that a module pinned by a display string must not move is the
caller's business, and what `:pin` means to an algorithm is this package's.

## The engines

| engine | what it is | node sizes | cost |
| --- | --- | --- | --- |
| `GridEmbedding` | rows and columns, or a ring inside an extent. No simulation. | honoured, never changed | instant |
| `SpringEmbedderLayout` | the port of OMNeT++'s `BasicSpringEmbedderLayout` | **ignored**, except that an edge grows a little with its ends | 0.04 s at 300 vertices |
| `ForceDirectedLayout` | the port of OMNeT++'s `ForceDirectedGraphLayouter` | carried through every force | 41 s at 300 vertices |
| `AdaptagramsLayout` | libcola placement and libavoid routing, through a C shim | carried | native |
| `DeferredLayout` | becomes one of the above when the layout runs | — | — |

The two ported ones are the two OMNeT++ draws a network with, and they are ports
rather than new algorithms because the caller wants *the* picture Qtenv draws,
not *a* force-directed layout. Their positions are asserted against the C++
originals — see [../test/reference/](../../../test/graph/reference/).

`AdaptagramsLayout` is the only one with a native dependency, so it lives in its
own package and reaches this one through `register_layout_engine!`. When its
shim is not built it says so once and hands each layout to the pure-Julia engine
that would have drawn it anyway.

## Which engine runs

`DeferredLayout` is what a caller names when it has no reason to name a specific
engine, and it determines **when the layout runs** rather than when the projection
is built. A projection is usually constructed at module load, long before an
optional engine package can be loaded.

It follows the same rule as Qtenv: twenty vertices or more go to
`SpringEmbedderLayout`, which is fast, and fewer go to `ForceDirectedLayout`,
which is better and costs more. A registered native engine takes over both.

The layout says which one ran. `GraphLayout.engine` is `:grid`,
`:spring_embedder`, `:force_directed` or `:adaptagrams`, so a view can tell a
reader what it is looking at and a test can assert the choice went the way it
should have.

## Constraints

A `GraphConstraint` wraps a vertex with a `kind` and a `payload`.

| kind | payload | what the layout must do |
| --- | --- | --- |
| `:pin` | `(x, y)` | place this vertex at this corner and never move it |
| `:fixed_size` | `(w, h)` or `nothing` | use this size, and do not resize it |
| `:cluster` | `group` or `(group, offx, offy)` | this vertex belongs to a family that moves as one body, at this offset |
| `:align` | — | not implemented by anything |
| `:same_rank` | — | not implemented by anything |
| `:min_separation` | — | not implemented by anything |

`:cluster` is how a module vector is laid out: `rte[0..56]` is 57 vertices and
one anchor point, so the row or the ring keeps its shape while the whole family
finds its place. It is OMNeT++'s `addAnchoredNode`, and `:pin` is its
`addFixedNode`.

**An engine that does not implement a kind raises an error naming it**, and
the error lists what it does implement. That is deliberate: a caller cannot tell a satisfied pin from
an ignored one by looking at the picture, so accepting and dropping a constraint
is the worst of the three possible answers. Ask an engine what it takes with
`get_supported_constraint_kinds`.

## Determinism

The same graph and the same seed answer the same positions, or nothing
downstream can compare, cache or screenshot a drawing. Both ported engines
scatter or draw parameters at random, and both get repeatability the same way
OMNeT++ does:

- a private linear congruential generator, ported from `common/lcgrandom.h`,
  never a session-wide one;
- a `seed` field on the engine, default 1, which is what Qtenv seeds a module
  type with the first time it lays that type out;
- vertex order is the graph's own order, and no `Dict` iteration reaches a
  coordinate.

One deviation from the original for the same reason: OMNeT++ also stops on
elapsed wall-clock time, which makes the drawing depend on the machine.
`max_calculation_time` is here and honoured, and defaults to `Inf`; `max_cycle`
and `max_iterations` bound the work instead.

## The ported files

`source/graph/omnetpp/` holds the port, one file per C++ file in
`src/layout/` of the OMNeT++ source tree, keeping the original's name and the order of its
definitions so a later fix over there can be read across.

| here | there |
| --- | --- |
| `LcgRandom.jl` | `common/lcgrandom.{h,cc}` |
| `LayoutGeometry.jl` | `geometry.h` |
| `GraphComponent.jl` | `graphcomponent.{h,cc}` |
| `BasicSpringEmbedderLayout.jl` | `basicspringembedderlayout.{h,cc}` |
| `ForceDirectedParametersBase.jl` | `forcedirectedparametersbase.h` |
| `ForceDirectedParameters.jl` | `forcedirectedparameters.h` |
| `ForceDirectedEmbedding.jl` | `forcedirectedembedding.{h,cc}` |
| `StarTreeEmbedding.jl` | `startreeembedding.{h,cc}` |
| `HeapEmbedding.jl` | `heapembedding.{h,cc}` |
| `ForceDirectedGraphLayouter.jl` | `forcedirectedgraphlayouter.{h,cc}` |

Each file's docstring names the deviations it makes and why. Nothing is
reorganised on the way across, because a port that is cannot be diffed against
its original.

## Measuring

`graphlayoutbench()` in [../../../bench/](../../../package/ProjecturedBench/) times every engine
over 10, 60 and 300 vertices and prints the answer as characters beside the
numbers. Run it before changing a constant, and again after.
