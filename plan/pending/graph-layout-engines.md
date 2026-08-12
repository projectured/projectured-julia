# Two graph layout algorithms, and the constraints both honour

**Status:** proposed. **Scope:** graph placement — which algorithms exist behind
`GraphLayoutEngine`, and what a caller can ask of them.

This plan owns nothing about any domain. It is asked for by
`omnetpp-julia`'s `plan/pending/submodule-layout-parity.md`, which needs a
network drawn the way OMNeT++ draws one, but **nothing here knows what a network
is**. §1 is the argument that it should stay that way.

## 1. Nothing here depends on the caller

`ProjecturedGraph` depends on `ProjecturedCollection`, `ProjecturedGraphics`,
`ProjecturedKernel`, `ProjecturedNaturalProjection`, `ProjecturedProjection` and
`ProjecturedStyle`. `ProjecturedAdaptagrams` is a package of its own, because it
carries a native dependency, and it reaches this one through
`register_layout_engine!` rather than the other way round.

So a layout engine takes a graph, a size per vertex and a vector of constraints,
and answers positions and routes. It is told **what to satisfy**, never **why**.
That is the whole seam, and it means the domain work stays in the domain:

| the domain decides | this plan decides |
| --- | --- |
| that a module pinned by `@display p=` must not move | what `:pin` means to an algorithm |
| that `rte[0..56]` is one family | what `:align` does to a set of vertices |
| that a queue is 40 by 20 | nothing — `sizes` is an input |

A `GraphConstraint` is the only vocabulary between them, and it already exists.

## 2. What exists today

### 2.1 The interface is right, and is not the problem

```julia
layout_graph(engine, graph, sizes, constraints) -> (positions, routes)
```

`GraphConstraint` (`package/graph/main/GraphLayout.jl:73`) already names the
kinds: `:pin`, `:same_rank`, `:align`, `:fixed_size`, `:min_separation`,
`:cluster`. Its own docstring says v1 ships `:pin` and `:fixed_size`.

`register_layout_engine!` lets an optional package take over at `__init__`, and
`DefaultLayoutEngine` defers the choice to layout time rather than construction
time — so a projection built at module load still gets the native engine when
one is loaded later. That reasoning is written out in the module and is correct.

### 2.2 Two engines, and neither honours a constraint

| engine | what it does | constraints |
| --- | --- | --- |
| `FallbackLayoutEngine` | a grid: `ceil(sqrt(n))` columns, cells sized to the largest member | **ignored** |
| `AdaptagramsEngine` | libcola `cola::ConstrainedFDLayout` — constrained force-directed layout by stress majorization — plus libavoid routing | **ignored**: the shim's `adaptagrams_layout` has no constraint argument |

Both take the `constraints` vector and neither reads it. A caller that pins a
vertex is ignored silently, which is the worst of the three possible answers.

### 2.3 The grid is what a real graph actually gets

Two things make the grid the common case rather than the exceptional one.

- The native shim must be built (`Pkg.build("ProjecturedAdaptagrams")`) and in a
  fresh checkout it is not, so `isavailable()` is false and the fallback runs.
- Every screenshot taken for `omnetpp-julia`'s Qtenv window so far was drawn by
  the grid.

At 276 vertices the grid is 17 columns of full-width nodes — several thousand
pixels across, and it runs off any pane it is given. A grid is a fine answer for
a dozen boxes and no answer at all for a network.

## 3. The design: two algorithms, one contract

### 3.1 Why two, and not one good one

They fail differently, and a caller should be able to choose.

- **`AdaptagramsEngine`** minimises a stress function by majorization. It
  converges well, avoids overlaps properly (`makeFeasible`), and routes edges
  around obstacles with libavoid. It costs a **native dependency** that must be
  built, and when it is absent there is nothing to fall back to but a grid.
- **`SpringLayoutEngine`** (new, pure Julia) integrates explicit forces —
  repulsion between vertices, springs along edges, friction to settle. It is the
  family OMNeT++'s own `ForceDirectedGraphLayouter` belongs to. It will not beat
  libcola on quality, and it needs **nothing installed**, which makes it the
  honest default.

One is better; the other is always there. Neither is a fallback for the other in
the sense of being lesser — they are two answers to one question, and
`DefaultLayoutEngine` picks between them.

### 3.2 Both honour the same constraints

The point of doing two is that a constraint means the same thing to both.

| kind | payload | what an engine must do |
| --- | --- | --- |
| `:pin` | `(x, y)` | place the vertex there and never move it |
| `:fixed_size` | `(w, h)` | do not resize it (already the `sizes` input's job; kept for symmetry) |
| `:align` | an axis, `:x` or `:y` | give every vertex in the set the same coordinate on that axis |
| `:same_rank` | — | the layered form of `:align`, for a directed graph |
| `:min_separation` | a distance | keep two vertices at least that far apart |
| `:cluster` | a group id | keep the members together and others out |

`:pin` and `:align` are what a network needs, and they are what §4 implements.
The rest keep their names and stay unimplemented rather than being invented
speculatively — an engine that silently ignores a kind is §2.2's mistake
repeated, so an unimplemented kind must be **refused**, not dropped.

### 3.3 Determinism is a property of the interface, not of an engine

Two runs of one layout must answer the same positions, or nothing downstream can
be compared, cached or screenshotted. Both algorithms are deterministic given a
deterministic start, so the interface owes the start:

- vertex order is the graph's own order;
- the seed placement is derived from that order;
- no `Dict` iteration reaches a coordinate.

Say it once, here, and test it once, for both engines.

## 4. Stages

### Stage A — a fallback that fits what it is given

- [ ] `layout_graph` learns an optional extent: the box the caller wants filled.
- [ ] `FallbackLayoutEngine` places into that extent — a circle for a small
      graph, a bounded grid for a large one — instead of growing without limit.
- [ ] A graph that does not fit is scaled down rather than clipped.

**Why first.** It is what a fresh checkout draws, and it is what every
screenshot of the caller's window has been drawn with.

### Stage B — the spring embedder

- [ ] `SpringLayoutEngine <: GraphLayoutEngine`, pure Julia: repulsion between
      every pair, a spring along every edge, friction, integrated to a rest.
- [ ] Seeded from stage A's placement, so it starts from something reasonable
      and stays deterministic.
- [ ] A bound on the work: an iteration cap and an energy threshold, both
      stated, so a 300-vertex graph has a known cost.
- [ ] It becomes what `DefaultLayoutEngine` picks when no native engine is
      registered.

**A reader sees.** A network that reads as a network, with nothing installed.

### Stage C — constraints reach both engines

- [ ] `:pin` in `SpringLayoutEngine`: a pinned body has infinite mass.
- [ ] `:pin` in the Adaptagrams shim: a per-vertex fixed flag, which is the
      smallest thing libcola needs.
- [ ] `:align` in both: an axis coordinate shared by a set. libcola has
      `AlignmentConstraint`; the spring embedder projects the force.
- [ ] **An unimplemented kind is refused**, by name, with what the engine does
      support.

### Stage D — say which engine drew it

- [ ] The layout answers which engine produced it, so a view can say so and a
      test can assert it.
- [ ] `ProjecturedAdaptagrams` stops printing "shim unavailable" once per
      layout; it says it once, with what to run to fix it.

### Stage E — measure both

- [ ] A benchmark over the graph sizes that matter: 10, 60, 300 vertices.
- [ ] Record the time and a picture of each engine's answer at each size.
- [ ] The numbers decide the iteration cap of stage B, rather than a guess.

## 5. Decisions

### D1. The spring embedder is not a port

OMNeT++'s `ForceDirectedGraphLayouter` is a decade of tuned force providers —
electric repulsion in three forms, five kinds of spring, friction, drag, wall
bodies, point and line constraints, and three pre-embeddings to start from.
Porting it is a project of its own.

This is the plain form: repulsion, springs, friction. It exists to be *always
available* and *good enough to read*, and the ceiling stays libcola's.

### D2. An unimplemented constraint is refused

§2.2's real defect is not that constraints are unimplemented, it is that they
are accepted and dropped. A caller cannot tell a satisfied pin from an ignored
one by looking at the output, and a picture that ignores a pin looks exactly
like a picture that has no pin.

### D3. The extent belongs to the call, not to the engine

A layout is asked for by a view that knows how much room it has, and the same
graph in two panes wants two layouts. So the extent is an argument, not a field
on an engine.

## 6. What this plan does not do

- It does not read a display string, a NED file or anything else that knows what
  a module is. That is the caller's, and §1 is why.
- It does not route edges better. libavoid already does that when it is built;
  the spring embedder draws straight lines.
- It does not add hierarchy or go-into. A graph is flat here; who flattens a
  tree into one is the caller's question.
