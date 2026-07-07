"""
    ProjecturedTulipExample

The Tulip opt-in example package (opt-in tier of the example DAG; see
plan/done/extras-example-split.md). It hosts the `constraint_layout_tulip`
example — the engine-free constraint-layout document from `ProjecturedExample`
projected with the real LP-backed `TulipConstraintSolver` swapped in for the
dependency-free `FallbackConstraintSolver`.

Resolves through the root env; precompiles only where ProjecturedTulip
(Tulip + MathOptInterface) is available.
"""
module ProjecturedTulipExample

using Projectured
using ProjecturedTulip         # TulipConstraintSolver
import ProjecturedExample: Example, run_example, run_console_example, run_web_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_constraint_layout_document_example, make_constraint_layout_projection_example

const _PKG_DIR = @__DIR__

include(joinpath(_PKG_DIR, "projection", "Layout.jl"))
include(joinpath(_PKG_DIR, "Examples.jl"))

export make_constraint_layout_tulip_projection_example
export constraint_layout_tulip_example, tulip_examples
export Example, run_example, run_console_example, run_web_example,
       print_example, write_example_image, write_example_pdf, record_example_video

end # module ProjecturedTulipExample
