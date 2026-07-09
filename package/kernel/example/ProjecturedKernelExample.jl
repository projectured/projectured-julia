"""
    ProjecturedKernelExample

The base of the example-package DAG that parallels the main DAG
(kernel ← visual ← domain ← umbrella; see
plan/done/example-package-split.md). It hosts the **example harness
core** — the `Example` struct that every example package instantiates and the
test drivers dispatch on, plus the harness entry points that compile against
kernel API alone: `write_example_image` / `record_example_video` (the kernel
`write_image` / `record_video` backend seams — the SDL/Video packages register
the methods when loaded) and `make_typein_gestures` (kernel keyboard events).

There are no kernel-tier example *documents*: a runnable example pairs a document
with a projection to a presentable output domain, which needs at least the visual
package — the concrete examples start in `ProjecturedVisualExample`. What does
live here are the **kernel-seam test doubles**: the in-process `FakeLlm` and the
scripted `ScriptedLlm` backends (with their `make_scripted_*` builders) that
implement the kernel's `LlmModule.Llm` seam. They are fakes, so by architectural
requirement they live in an example package, never in `main` — no fake is
reachable from a production build.
"""
module ProjecturedKernelExample

using ProjecturedKernel.CellModule
using ProjecturedKernel.KeyboardModule
using ProjecturedKernel.ModifiersModule
using ProjecturedKernel.BackendModule: write_image, record_video
import ProjecturedKernel.LlmModule: Llm, stream_turn

include("Harness.jl")
include("LlmFake.jl")     # FakeLlm — canned-reply test double (no network)
include("LlmScripted.jl") # ScriptedLlm + scripted-round builders

export Example
export write_example_image, record_example_video, make_typein_gestures
export FakeLlm, ScriptedLlm,
       make_scripted_turn, make_scripted_think, make_scripted_say, make_scripted_run

end # module ProjecturedKernelExample
