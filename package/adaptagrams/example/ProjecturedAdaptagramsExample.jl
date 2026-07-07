"""
    ProjecturedAdaptagramsExample

The Adaptagrams opt-in example package (opt-in tier of the example DAG; see
plan/done/extras-example-split.md). It hosts the native-graph-layout
examples `graph_adaptagrams` and `dvdrental_relationship` (both projections in
projection/Graph.jl, laid out by the native `AdaptagramsEngine`). The
relationship diagram's DB-derived document comes from `ProjecturedOdbcExample`
— the one example that needs two engines, so this package depends on both.

Reuses `ProjecturedExample`'s harness + engine-free graph builders. Resolves
through the root env; precompiles only where the ProjecturedAdaptagrams C++
shim is built.
"""
module ProjecturedAdaptagramsExample

using Projectured
using ProjecturedAdaptagrams   # AdaptagramsEngine
import ProjecturedExample: Example, run_example, run_console_example, run_web_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_graph_document_example, make_graph_projection_example,
                           make_table_projection_example, make_mixed_projection_example
import ProjecturedOdbcExample: make_dvdrental_relationship_graph_document_example

const _PKG_DIR = @__DIR__

include(joinpath(_PKG_DIR, "projection", "Graph.jl"))
include(joinpath(_PKG_DIR, "Examples.jl"))

export make_graph_adaptagrams_projection_example, make_dvdrental_relationship_projection_example
export graph_adaptagrams_example, dvdrental_relationship_example, adaptagrams_examples
export Example, run_example, run_console_example, run_web_example,
       print_example, write_example_image, write_example_pdf, record_example_video

end # module ProjecturedAdaptagramsExample
