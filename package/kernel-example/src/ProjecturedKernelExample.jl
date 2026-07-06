"""
    ProjecturedKernelExample

The base of the example-package DAG that parallels the runtime DAG
(kernel ← visual ← domain ← umbrella; see
plan/pending/example-package-split.md). It hosts the **example harness
core** — the `Example` struct that every example package instantiates and the
test drivers dispatch on, plus the harness entry points that compile against
kernel API alone: `write_example_image` / `record_example_video` (the kernel
`write_image` / `record_video` backend seams — the SDL/Video packages register
the methods when loaded) and `make_typein_gestures` (kernel keyboard events).

There are no kernel-tier examples: a runnable example pairs a document with a
projection to a presentable output domain, which needs at least the visual
package — the concrete examples start in `ProjecturedVisualExample`.
"""
module ProjecturedKernelExample

using ProjecturedKernel.CellModule
using ProjecturedKernel.KeyboardModule
using ProjecturedKernel.ModifiersModule
using ProjecturedKernel.BackendModule: write_image, record_video

include("Harness.jl")

export Example
export write_example_image, record_example_video, make_typein_gestures

end # module ProjecturedKernelExample
