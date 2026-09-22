# Adaptagrams layout engine

> **Kind:** design · **Status:** current · **Stands on:** [graph.md](../graph/graph.md), [graph-layout.md](../graph/graph-layout.md), [package-rules.md](../../rule/package-rules.md)

`ProjecturedAdaptagrams` is an opt-in package with one graph layout engine, `AdaptagramsLayout`. It places vertices with libcola and routes edges with libavoid, two C++ libraries of [Adaptagrams](https://github.com/mjwybrow/adaptagrams), through a small C shim. This document says how the shim is built and found, what happens when it is missing, and how the package becomes the engine of every deferred layout.

## How it works

### The engine

```julia
AdaptagramsLayout(; ideal_length = 60.0, avoid_overlaps = true, orthogonal = false,
                    node_margin = nothing)
```

- `ideal_length` is the base gap between two connected boxes. The shim gets one length for each edge: `ideal_length` plus half the extent of each end box, where the half extent is `max(w, h) / 2`. So large boxes move apart in proportion to their size.
- `avoid_overlaps = true` makes libcola remove every overlap of two boxes as a hard rule, not only as a soft force.
- `orthogonal = true` makes libavoid route right-angled lines instead of polylines.
- `node_margin` is the minimum gap on each side of each box. With `nothing`, the engine computes it as 20 percent of the mean half extent, and at least 16 pixels.

`layout_graph` returns the same positions and routes as every engine of [graph-layout.md](../graph/graph-layout.md):

1. It calls `check_constraints`. The engine implements `:pin` and `:fixed_size`.
2. It copies the sizes and the edges into C arrays, calls `adaptagrams_layout`, and gets a handle.
3. It reads each box with `adaptagrams_node_box` and each route with `adaptagrams_route_size` and `adaptagrams_route_point`. A `finally` block calls `adaptagrams_free`.
4. `_fit_and_pin!` scales the boxes and the route points into the `extent` together, because a route that was not scaled would miss its own boxes. Then it puts each pinned vertex at its pin.

The shim takes no constraint argument. So libcola places the graph as if each vertex were free, and step 4 moves a pinned vertex afterwards. The pinned vertex is where the caller put it, but its neighbours are not placed around it.

### The shim and where it is found

`package/ProjecturedAdaptagrams/deps/` holds the shim: `adaptagrams_shim.cpp`, `adaptagrams_shim.h` and `build.jl`. The module loads `deps/libadaptagrams_shim.<dlext>` from a fixed path. `isavailable()` is true when that file exists and `Libdl.dlopen` loads it. It checks again on each call, so a shim built during a session is used without a restart.

The path is fixed on purpose. A path read from a generated `deps.jl` goes into the precompile image. If the module loads once before the build, the image keeps an empty path, and a later build does not make the image stale.

### Without the shim

`effective_engine(engine, vertex_count)` returns the engine when the shim is available. If not, it writes a warning once in each session and returns `make_pure_julia_layout_engine(vertex_count)`, the choice that `DeferredLayout` makes without a factory. `layout_graph`, `layout_engine_name` and `resolve_layout_engine` all go through it. So a missing shim raises no error, and `GraphLayout.engine` names the engine that ran, not `:adaptagrams`.

### Build the shim

Adaptagrams has no system package and no Julia JLL, so you build it from source.

1. Install the tools: `sudo apt install build-essential autoconf automake libtool pkg-config`.
2. In the `cola/` folder of an Adaptagrams checkout, run `./autogen.sh && ./configure && make`. The step `sudo make install && sudo ldconfig` is optional.
3. Run `using Pkg; Pkg.build("ProjecturedAdaptagrams")`.

`deps/build.jl` finds Adaptagrams in this order:

1. `pkg-config --exists libcola libavoid libvpsc`, which works after `make install` when the `.pc` files are on `PKG_CONFIG_PATH`.
2. `ADAPTAGRAMS_DIR`, the `cola/` folder of a checkout, with the default `~/workspace/adaptagrams/cola`. The shim then links against the `.libs` folders of the checkout, with an `rpath`, so no install is necessary.

The build never throws. If it finds no Adaptagrams, or the compile fails, it writes a warning and removes an old shim, so that a stale file does not look available. A few calls of libcola, libvpsc and libavoid have a different spelling in different Adaptagrams revisions. The two `VERIFY` notes in `adaptagrams_shim.cpp` mark them. The C interface that Julia calls does not change.

## How it fits

`ProjecturedAdaptagrams` depends on `ProjecturedGraph` and on the standard library `Libdl`. No package of the editor depends on it.

Its `__init__` calls `register_layout_engine!((; orthogonal) -> AdaptagramsLayout(orthogonal = orthogonal))`. From then on, each `DeferredLayout` resolves to this engine; see [graph.md](../graph/graph.md#the-deferred-choice-of-an-engine). A projection that names another engine does not change. In this repository the process flowchart is the one example that names a deferred engine. The graph example, the fsm diagram and the natural row of `GraphGraph` name `GridEmbedding`.

`ProjecturedAdaptagramsExample` holds the examples that name `AdaptagramsLayout` directly, so the other example packages do not depend on the native library.

## Design decisions

- **A separate package for the native dependency.** No other package needs Adaptagrams to load or to draw a graph. See `plan/done/graph-domain.md`.
- **A fixed shim path and a check at each call.** A generated `deps.jl` would put a stale path into the precompile image.
- **A missing shim gives the pure-Julia engine and a warning.** A fresh checkout has no shim, and an error on each layout would stop every drawing of a graph. The layout records the engine that ran, so the substitution is visible.
- **The edge length and the margin grow with the box size.** A fixed length puts large card nodes almost on top of each other and hides the edges between them.
- **A pin is applied after the native run.** Pins in libcola need a wider C interface.
- **The registration writes a factory from `__init__`.** A second method of the choice function would be a fatal overwrite during precompilation. See `plan/done/graph-layout-engines.md`.

## Usage

```julia
using Pkg; Pkg.build("ProjecturedAdaptagrams")
using ProjecturedExample, ProjecturedAdaptagrams
projection = make_graph_projection_example(engine = AdaptagramsLayout(orthogonal = true))
run_example("process_diagram")        # its deferred engine now resolves to AdaptagramsLayout
```

- Examples: `graph_adaptagrams_example` in `example/adaptagrams/`. `make_dvdrental_relationship_example()` draws the tables of a live dvdrental database, so no sweep runs it; call it at the prompt.
- Test: none. No test folder exists for this package.

## Limits

- No test covers the engine. On a checkout without the shim, `graph_adaptagrams_example` draws with a pure-Julia engine.
- The `ccall` signatures in `source/adaptagrams/Adaptagrams.jl` must match `adaptagrams_shim.h` by hand. A mismatch fails at the call, not at compile time.
- The engine implements only `:pin` and `:fixed_size`, and the neighbours of a pinned vertex are placed as if it were free.
