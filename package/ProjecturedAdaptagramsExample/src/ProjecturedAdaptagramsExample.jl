"""
    ProjecturedAdaptagramsExample

The Adaptagrams opt-in example package (opt-in tier of the example DAG; see
plan/done/extras-example-split.md). It hosts the native-graph-layout
examples `graph_adaptagrams` and `dvdrental_relationship` (both projections in
projection/Graph.jl, laid out by the native `AdaptagramsLayout`). The
relationship diagram's DB-derived document comes from `ProjecturedODBCExample`
— the one example that needs two engines, so this package depends on both.

Reuses `ProjecturedExample`'s harness + engine-free graph builders. Resolves
through the root env; precompiles only where the ProjecturedAdaptagrams C++
shim is built.
"""
module ProjecturedAdaptagramsExample

using ProjecturedAll
using ProjecturedAdaptagrams   # AdaptagramsLayout
import ProjecturedExample: Example, run_example, run_console_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_graph_document_example, make_graph_projection_example,
                           make_table_projection_example, make_mixed_projection_example
import ProjecturedODBCExample: make_dvdrental_relationship_graph_document_example

# The bodies live in `example/adapter/adaptagrams`, not beside this file:
# a package is a name and an include list.
const _PKG_DIR = normpath(joinpath(@__DIR__, "../../../example/adapter/adaptagrams"))

include(joinpath(_PKG_DIR, "GraphProjectionExample.jl"))
include(joinpath(_PKG_DIR, "AdaptagramsExamples.jl"))

export make_graph_adaptagrams_projection_example, make_dvdrental_relationship_projection_example
export graph_adaptagrams_example, make_dvdrental_relationship_example, adaptagrams_examples
export Example, run_example, run_console_example,
       print_example, write_example_image, write_example_pdf, record_example_video

end # module ProjecturedAdaptagramsExample
