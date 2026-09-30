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
import ProjecturedExample: Example, run_example, run_console_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_constraint_layout_document_example, make_constraint_layout_projection_example

# The bodies live in `example/adapter/tulip`, not beside this file:
# a package is a name and an include list.
const _PKG_DIR = normpath(joinpath(@__DIR__, "../../../example/adapter/tulip"))

include(joinpath(_PKG_DIR, "LayoutProjectionExample.jl"))
include(joinpath(_PKG_DIR, "TulipExamples.jl"))

export make_constraint_layout_tulip_projection_example
export constraint_layout_tulip_example, tulip_examples
export Example, run_example, run_console_example,
       print_example, write_example_image, write_example_pdf, record_example_video

end # module ProjecturedTulipExample
