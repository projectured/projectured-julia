"""
    ProjecturedAdaptagrams

The native graph-layout engine for ProjecturEd: an `AdaptagramsLayout` that places
vertices with **libcola** (constraint-based force-directed layout) and routes
edges with **libavoid** (obstacle-avoiding connectors), bridged through a small
`extern "C"` shim (`deps/adaptagrams_shim.cpp`) via `ccall`.

This lives in its own package, separate from `ProjecturedDomain`, precisely
because it carries an external native dependency (the Adaptagrams C++ libraries).
`ProjecturedDomain` only defines the `GraphLayoutEngine` interface and the
pure-Julia `GridEmbedding`; this package adds an `AdaptagramsLayout`
method to `layout_graph` behind that same interface, so nothing in core depends
on Adaptagrams being installed.

## Building

The shim is compiled by `deps/build.jl` against an installed/built Adaptagrams:

    using Pkg; Pkg.build("ProjecturedAdaptagrams")

Point `ADAPTAGRAMS_DIR` at the `cola/` directory of an Adaptagrams checkout, or
install it so its `.pc` files are on `PKG_CONFIG_PATH`. Until the shim is built,
`AdaptagramsLayout` loads, says once what to run, and hands each layout to the
pure-Julia engine that would have drawn it anyway. The layout records which
engine really placed it, so the substitution is visible rather than silent.

## Use

    using ProjecturedExample, ProjecturedAdaptagrams
    proj = make_graph_projection_example(engine = AdaptagramsLayout())
"""
module ProjecturedAdaptagrams

import ProjecturedGraph.GraphLayoutEngineModule: GraphLayoutEngine, layout_graph,
                                                  supported_constraint_kinds,
                                                  check_constraints, get_constraint_pins,
                                                  get_vertex_sizes, get_extent_transform,
                                                  layout_engine_name, layout_vertices
import ProjecturedGraph.GraphLayoutChoiceModule: register_layout_engine!,
                                                 make_pure_julia_layout_engine,
                                                 resolve_layout_engine
import ProjecturedGraph.GraphModule: GraphGraph, GraphVertex, GraphEdge
import Libdl

include("../../../source/adaptagrams/Adaptagrams.jl")

end # module ProjecturedAdaptagrams
