# Two graph layout algorithms, and the constraints both honour

**Status:** done. **Scope:** graph placement — which algorithms exist
behind `GraphLayoutEngine`, and what a caller can ask of them.

This plan owns nothing about any domain. It is asked for by
`omnetpp-julia`'s `plan/pending/submodule-layout-parity.md`, which needs a
network drawn the way OMNeT++ draws one, but **nothing here knows what a network
is**. §1 is the argument that it should stay that way.

## 1. Nothing here depends on the caller

`ProjecturedGraph` depends on `ProjecturedCollection`, `ProjecturedGraphics`,
`ProjecturedKernel`, `ProjecturedNatural`, `ProjecturedProjection` and
`ProjecturedStyle`. `ProjecturedAdaptagrams` is a package of its own, because it
carries a native dependency, and it reaches this one through
`register_layout_engine!` rather than the other way round.

So a layout engine takes a graph, a size per vertex and a vector of constraints,
and answers positions and routes. It is told **what to satisfy**, never **why**.
That is the whole seam, and it means the domain work stays in the domain:

| the domain decides | this plan decides |
| --- | --- |
| that a module pinned by `@display p=` must not move | what `:pin` means to an algorithm |
| that `rte[0..56]` is one family | what `:cluster` does to a set of vertices |
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
the engine that resolves late defers the choice to layout time rather than
construction time — so a projection built at module load still gets the native
engine when one is loaded later. That reasoning is written out in the module and
is correct.

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

### 2.4 The names say the role, not the algorithm

`FallbackLayoutEngine` is a grid and `DefaultLayoutEngine` is late binding.
Neither name says so. §3.3 renames them.

## 3. The design: OMNeT++'s two layouters, ported

### 3.1 Which two, and why exactly those two

The caller asks for a network drawn the way OMNeT++ draws one. OMNeT++ draws one
with two layouters and picks between them by size
(`omnetpp-cpp/src/qtenv/modulelayouter.cc:363-372`):

```cpp
choice = submodCountLimited >= LIMIT ? LAYOUTER_FAST : LAYOUTER_ADVANCED;   // LIMIT = 20
GraphLayouter *graphLayouter = choice == LAYOUTER_FAST ?
            (GraphLayouter *)new BasicSpringEmbedderLayout() :
            (GraphLayouter *)new ForceDirectedGraphLayouter();
```

So the two algorithms are not a matter of taste. They are
`BasicSpringEmbedderLayout` and `ForceDirectedGraphLayouter`, and parity means
porting both, plus the rule that chooses between them.

### 3.2 What each of the two is

- **`SpringEmbedderLayout`** — the port of `BasicSpringEmbedderLayout` (687
  lines), the layouter OMNeT++ 3.x shipped and the one Qtenv still uses for 20
  submodules or more, because it is fast. Edge attraction, pairwise repulsion
  that ceases at 100 units between unconnected partitions, a movement limit of
  50 per step, and a halving friction. It honours fixed nodes and anchors. It
  **ignores node sizes**, which its own header says, so it does not answer §2.3
  on its own.
- **`ForceDirectedLayout`** — the port of `ForceDirectedGraphLayouter` and its
  stack (about 3100 lines across seven files): sized bodies, wall bodies for the
  border, electric repulsion in three forms, five kinds of spring, a drag, and a
  star-tree or heap pre-embedding per connected component. This is the one that
  carries node sizes, so this is the one that answers §2.3. §6 says which force
  providers are not ported and why.
- **`AdaptagramsLayout`** stays what it is: an opt-in third engine with a native
  dependency, libcola placement and libavoid routing. It is not one of the two;
  it is the better answer when it is installed.
- **`GridEmbedding`** stays as the trivial deterministic placement — instant, no
  simulation, and what a test names when it wants a known picture.

### 3.3 The names

The types say the algorithm. The abstract type keeps its name.

| was | is |
| --- | --- |
| `FallbackLayoutEngine` | `GridEmbedding` |
| — | `SpringEmbedderLayout` |
| — | `ForceDirectedLayout` |
| `AdaptagramsEngine` | `AdaptagramsLayout` |
| `DefaultLayoutEngine` | `DeferredLayout` |
| `default_layout_engine()` | `deferred_layout_engine()` |

`GridLayout` was the obvious name for the first one and it is taken:
`ProjecturedLayout` already exports a `GridLayout` widget document, and
`ProjecturedGraphTest` does a `using` over both packages, so two exported
`GridLayout` bindings would clash. `Embedding` is OMNeT++'s own word for an
initial placement — `StarTreeEmbedding`, `HeapEmbedding`,
`ConcentricTreeEmbedding` — so the grid takes it too.

### 3.4 The constraint vocabulary is already OMNeT++'s

The seam this plan describes and the seam `graphlayouter.h` describes are the
same seam under different names. That is the strongest argument that the port
fits behind it:

| this plan | `GraphLayouter` |
| --- | --- |
| the extent (§4, stage A) | `setSize(width, height, border)` |
| `:pin` with payload `(x, y)` | `addFixedNode(id, x, y, w, h)` |
| `:cluster` with payload `(group, offx, offy)` | `addAnchoredNode(id, anchorname, offx, offy, w, h)` |
| a per-edge ideal length | `addEdge(src, dst, preferredLength)` |
| determinism (§3.6) | `setSeed` plus a private LCG |

So the kinds a port implements are `:pin`, `:cluster` and `:fixed_size`.
`:align`, `:same_rank` and `:min_separation` have no counterpart in either
layouter and stay unimplemented — and therefore **refused**, not dropped.

`:cluster` is what `rte[0..56]` needs: OMNeT++ lays a module vector out by
anchoring every element to one movable anchor point with a per-element offset,
so the family moves as one body. The payload carries the group name and the
offset, which is exactly `addAnchoredNode`'s argument list.

### 3.5 An unimplemented kind is refused

§2.2's real defect is not that constraints are unimplemented, it is that they
are accepted and dropped. A caller cannot tell a satisfied pin from an ignored
one by looking at the output, and a picture that ignores a pin looks exactly
like a picture that has no pin.

So an engine declares the kinds it implements, and `layout_graph` refuses any
other kind by name, and says what the engine does implement.

### 3.6 Determinism comes from a seed, the way OMNeT++ gets it

Two runs of one layout must answer the same positions, or nothing downstream can
be compared, cached or screenshotted. Neither ported layouter is deterministic
without help: the spring embedder randomises its start positions, and the
force-directed one draws most of its own parameters from `privUniform` in
`setParameters`. Both get determinism the same way, and so do we:

- a private linear congruential generator, ported from `common/lcgrandom.h`
  (`a = 16807, q = 127773, r = 2836`, modulus `2^31-1`), never the session RNG;
- a `seed` field on the engine, default 1 — Qtenv seeds each module type with 1
  the first time it lays it out (`modulelayouter.cc:381`);
- vertex order is the graph's own order, and no `Dict` iteration reaches a
  coordinate.

Say it once, here, and test it once, for every engine.

## 4. Stages

### Stage A — the names, the extent, and a refusal — **done**

- [x] Rename per §3.3, and rename `AdaptagramsEngine` in its own package.
- [x] `layout_graph` learns an optional extent — `(width, height)` plus a
      `border`, matching `setSize`.
- [x] `GridEmbedding` places into that extent — a circle for a small graph, a
      bounded grid for a large one — instead of growing without limit. A graph
      that does not fit is scaled down rather than clipped.
- [x] Every engine declares `supported_constraint_kinds`, and an unimplemented
      kind is refused by name (§3.5).

Found while implementing:

- **Only centres scale, never sizes.** `BasicSpringEmbedderLayout::execute`
  rescales `n.x` and `n.y` and leaves `n.sx`, `n.sy` alone, so a scaled-down
  graph keeps readable boxes and may overlap rather than becoming unreadably
  small. `fit_into_extent!` does the same, which is also what makes
  `:fixed_size` true for every engine without any engine acting on it.
- **The extent lives on the projection, not on the engine.** D3 says it is an
  argument; `GraphGraphToGraphLayout` is where a view states it, along with a
  `constraints` function of the graph, because a constraint names a vertex and
  vertices exist only once there is a document.
- **`AdaptagramsLayout` honours `:pin` on the way out.** The shim takes no
  constraint argument, so the native run places the graph as if the vertex were
  free and the vertex is then moved to its pin. The contract holds; the
  neighbours were placed without knowing about it. §6 records what that costs.

**Why first.** It is what a fresh checkout draws, and it is what every
screenshot of the caller's window has been drawn with.

### Stage B — the substrate both ports need — **done**

- [x] `LcgRandom`, ported from `common/lcgrandom.h`, with its self-test as a
      test: 10000 draws from seed 1 must leave the seed at 1043618065.
- [x] The geometry the force-directed stack is written in: `Pt`, `Rs`, `Rc`.
- [x] `GraphComponent`: vertices, edges, connected sub-components, spanning
      tree — the graph algorithms both the pre-embeddings and the repulsions
      read.

Found while implementing:

- The ported files live in `package/graph/main/omnetpp/`, one per C++ file, per
  D5. `Vertex` and `Edge` became `LayoutVertex` and `LayoutEdge`, because beside
  this domain's `GraphVertex` and `GraphEdge` documents they would read as the
  same thing. `Pt`, `Rs`, `Rc` and `Ln` are immutable, because the original
  copies by hand and a missed copy is a silent aliasing bug.
- `GraphComponent::getBoundingRectangle` seeds its maxima with `DBL_MIN`, which
  is the smallest *positive* double. It is reproduced rather than corrected: a
  port that fixes it draws a different picture from the one it is a port of.

### Stage C — `SpringEmbedderLayout` — **done**

- [x] The port of `basicspringembedderlayout.cc`: anchors with bounding boxes,
      fixed nodes, the connected-partition colouring, `markNodesConnectedToFixed`,
      `assignInitialPositions`, `relax`, and the rescale-and-shift tail.
- [x] `:pin` is `addFixedNode`; `:cluster` is `addAnchoredNode`.
- [x] The stopping rule is OMNeT++'s: stop when the largest movement stays under
      0.05 for 20 iterations in a row, or at `max_iterations` (500).

**A reader sees.** A network that reads as a network, with nothing installed.

**Parity is asserted, not claimed.** `package/graph/test/reference/` holds a C++
program that links against an OMNeT++ checkout's `libopplayout` and prints the
positions its own layouter answers. The suite asserts the port against those
numbers over four scenarios — a four-by-four mesh, a chain with a pinned end, a
chain with four anchored nodes, and a chain in a 600 by 400 box. Every node
agrees to six decimals. The port is not merely of the same family; it is the
same picture.

### Stage D — `ForceDirectedLayout` — **done**

- [x] `forcedirectedparametersbase`: `Variable`, `PointConstrainedVariable`,
      `IBody`, `IForceProvider`.
- [x] `forcedirectedparameters`: `Body`, `RelativelyPositionedBody`, `WallBody`,
      the three electric repulsions, the five springs and `Drag`.
- [x] `forcedirectedembedding`: the adaptive-time-step integrator and its
      relaxation and stopping rules.
- [x] `startreeembedding` and `heapembedding`, the two pre-embeddings.
- [x] `forcedirectedgraphlayouter` itself: expected measures, borders, electric
      repulsions per connected sub-component, the pre-embedding pass, and the
      scale-and-translate tail.

Six scenarios are asserted against `libopplayout` and agree to six decimals: a
chain, a mesh in a box, a pinned end, an anchored row, a seed that turns the
pre-embedding on, and a graph in two parts.

Found while implementing:

- **`20 + 2400 / (20 + bodies.size())` is integer division.** Both operands are
  integral in C++, so the quotient truncates before it widens to a double: eight
  bodies give 105, not 105.714. Every length in the layout is measured against
  that number, and computing it in floating point moved every node by about a
  unit. This one line was the whole difference between a port that looks right
  and a port that is right.
- **The reported position is the last probe, not the accepted step.** `embed()`
  leaves the variables holding what the fourth Runge-Kutta probe assigned, and
  `getNodePosition` reads that. Writing the accepted `pn` back is a slightly
  better answer and the wrong one.
- **A pinned variable ignores x and y in every assignment**, including the
  scale and the translate at the end. `assignPosition` is virtual over there for
  exactly this reason.
- **The wall-clock limit is not ported.** OMNeT++ stops on elapsed real time,
  drawn at random between 1000 and 20000 milliseconds, which makes the drawing
  depend on the machine. `max_calculation_time` exists and defaults to `Inf`;
  `max_cycle` bounds the work. The draw is still made, so the random sequence
  stays in step.
- **Not ported, because the layouter never builds them:** `Friction`,
  `PointConstraint`, `LineConstraint`, `CircleConstraint`. A force nothing
  constructs is not part of the picture.
- **The vertex lookup is a table.** `GraphComponent::findVertex` is a linear
  scan and the repulsion loop asks it twice per pair, which is cubic. The answer
  never changes once a vertex is added.

### Stage E — say which engine drew it, and pick the way Qtenv picks — **done**

- [x] `DeferredLayout` picks `SpringEmbedderLayout` at 20 vertices or more and
      `ForceDirectedLayout` below that — Qtenv's own rule — unless a native
      engine is registered.
- [x] The layout answers which engine produced it, so a view can say so and a
      test can assert it.
- [x] `ProjecturedAdaptagrams` stops erroring once per layout when the shim is
      not built; it warns once, with what to run to fix it, and the layout
      records the engine that actually ran.

Found while implementing:

- **Choosing between engines means naming them.** `DeferredLayout` cannot live
  in the interface module any more, because that module is included before both
  ports. It moved to `GraphLayoutChoice.jl`, above them, along with
  `register_layout_engine!` and `resolved_layout_engine`.
- **The choice needs the graph.** `resolved_layout_engine` gained a vertex-count
  argument, and `layout_graph(::DeferredLayout, …)` passes it, so one projection
  draws a small graph with the advanced layouter and a large one with the fast
  layouter.
- **`GraphLayout` gained an `engine::Symbol` field.** It is a `ComputedCell` over
  the same memoized cell the positions come from, so a repaint does not re-run
  an engine to ask its name.

### Stage F — measure all of them — **done**

- [x] A benchmark over the graph sizes that matter: 10, 60, 300 vertices.
- [x] Record the time and a picture of each engine's answer at each size.
- [x] The numbers decide the iteration and time caps, rather than a guess.

`bench/graphlayoutbench.jl`, run as `graphlayoutbench()`. The graph is a chain
with a longer-range link every seventh vertex — connected, sparse, not a tree —
and every vertex is 40 by 20. The picture is drawn in characters rather than
written to a file, so the answer sits beside the numbers.

| engine | nodes | seconds | extent | overlaps | mean edge |
| --- | --- | --- | --- | --- | --- |
| `GridEmbedding` | 10 | 0.005 | 280x180 | 0 | 136 |
| `SpringEmbedderLayout` | 10 | 0.0001 | 304x151 | 0 | 61 |
| `ForceDirectedLayout` | 10 | 0.005 | 533x225 | 0 | 122 |
| `GridEmbedding` | 60 | 0.000 | 600x580 | 0 | 154 |
| `SpringEmbedderLayout` | 60 | 0.001 | 927x384 | 5 | 80 |
| `ForceDirectedLayout` | 60 | 0.553 | 717x1039 | 0 | 105 |
| `GridEmbedding` | 300 | 0.0002 | 1400x1300 | 0 | 413 |
| `SpringEmbedderLayout` | 300 | 0.039 | 964x7110 | 6 | 115 |
| `ForceDirectedLayout` | 300 | 41.1 | 2169x4035 | 0 | 104 |

**What the numbers decide.**

- **The threshold at 20 is right, and these are the numbers that say so.** The
  advanced layouter costs 0.55 seconds at 60 vertices and 41 seconds at 300;
  the fast one costs 0.04 seconds at 300. Every cycle asks for a force between
  every pair of bodies, four times, so the cost grows with the square of the
  count. Qtenv's own comment says the advanced layouter is already very slow at
  thirty or forty modules, and that is exactly what this measures.
- **No cap is lowered.** `max_cycle` stays at OMNeT++'s 1000 and
  `max_iterations` at its 500, because changing either changes the picture and
  the picture is the point. The measured cost is written into
  `ForceDirectedLayout`'s docstring instead, so a caller naming it directly for
  a large graph knows what it is asking for, and `max_calculation_time` is there
  for a caller who would rather have a bounded wait than a repeatable answer.
- **Quality is the other half of the trade.** The advanced layouter leaves
  nothing overlapping at any size; the fast one leaves five or six pairs
  overlapping from 60 vertices up. That is the price of ignoring node sizes, and
  it is why the advanced one is worth 0.55 seconds when the graph is small
  enough to afford it.

## 5. Decisions

### D1. The layouters are ports, not new algorithms

*This decision replaces an earlier one that refused a port.* The earlier
reasoning was that `ForceDirectedGraphLayouter` is a decade of tuned force
providers and that porting it is a project of its own. Both halves are true. The
reason it is worth it anyway is §3.1: the caller does not want *a* force-directed
layout, it wants *the* picture Qtenv draws, and that picture is these two
layouters with these tuned constants and this choice rule. A plain
repulsion-springs-friction embedder would be a different picture that is nobody's
specification.

The ports keep OMNeT++'s constants, its stopping rules and its parameter names,
so a difference in the drawing is a bug in the port rather than a difference in
taste.

### D2. An unimplemented constraint is refused

See §3.5. Kept from the earlier plan unchanged.

### D3. The extent belongs to the call, not to the engine

A layout is asked for by a view that knows how much room it has, and the same
graph in two panes wants two layouts. So the extent is an argument, not a field
on an engine. This is also how OMNeT++ does it: `setSize` is called per layout
run, on the layouter, from the display string's `bgb` tag.

### D4. The grid is called `GridEmbedding`, not `GridLayout`

See §3.3. The obvious name is taken by a widget document in `ProjecturedLayout`
and the two would collide in `ProjecturedGraphTest`.

### D5. Ported code keeps its own structure

A port that is reorganised on the way across cannot be diffed against its
original, and every later fix to `omnetpp-cpp` becomes an archaeology problem.
So each ported file keeps the C++ file's name, its order of definitions and its
identifier names, transliterated to Julia spelling. A comment at the top of each
names the C++ file it came from.

## 6. What this plan does not do

- It does not read a display string, a NED file or anything else that knows what
  a module is. That is the caller's, and §1 is why.
- It does not route edges better. libavoid already does that when it is built;
  the two ported layouters draw straight lines, exactly as Qtenv's own
  `arrowcoords` does before it applies the arrowhead geometry.
- It does not add hierarchy or go-into. A graph is flat here; who flattens a
  tree into one is the caller's question.
- It does not port `arrowcoords.cc`, `geometry.cc`'s drawing helpers, or the
  layouter's debug drawing. A debug window is Qtenv's, not ours.
- It does not port `Friction`, `PointConstraint`, `LineConstraint` or
  `CircleConstraint`. `ForceDirectedGraphLayouter` never constructs any of them,
  and a force nothing constructs is not part of the picture.
- It does not port `addEdgeToBorder`. It is `LeastExpandedSpring` and the wall
  bodies, both of which are here, but a `GraphEdge` has no way to name the
  enclosing module as an endpoint. Whoever gives it one wires this up.
- It does not teach libcola about constraints. `AdaptagramsLayout` honours
  `:pin` by placing the vertex after the native run, so the contract holds and
  the neighbours were arranged without knowing about it. A wider C ABI is
  someone else's plan.

## 7. What landed

Nine new files under `package/graph/main/omnetpp/`, one per C++ file, plus
`GraphLayoutChoice.jl` for the choice and `bench/graphlayoutbench.jl` for the
measurements. About 3500 lines of ported layouter, and ten scenarios asserted
against `libopplayout` — four for the spring embedder, six for the
force-directed one — every one of them agreeing to six decimals.

A reader's entry point is
[`package/graph/doc/graph-layout.md`](../../package/graph/doc/graph-layout.md):
the seam, the engines, the constraint vocabulary, what makes a layout
repeatable, and which ported file came from which original.

**The suites.** `test_graph()` 357, `test_fsm()` 153 and `test_process()` 303
are clean, as are the export-collision and package-dependency guards. `test_all()`
answers 869436 pass, 479 fail, 5 error, 2135 broken in 50 minutes. Every one of
those failures also happens on 731709a8, the commit this work started from:
they are the text domain's position navigation, the catalog's outstanding
`Pane*`/`Process*`/`CommandPalette` atoms, the kernel's Rule C, and the chart and
sequencechart click sweeps. The two the sweep reported against the graph example
were a known-throwing marker that had already stopped throwing; it is retired.
