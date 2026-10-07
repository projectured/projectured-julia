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
package — the concrete examples start in `ProjecturedPlatformExample`. What does
live here are the **kernel-seam test doubles**: the in-process `FakeLlm` and the
scripted `ScriptedLlm` backends (with their `make_scripted_*` builders) for the
kernel's `LlmModule.Llm` seam, the `ScriptedAgentConnection` for the kernel's
external-agent seam of `AgentModule`, and the in-memory `HeadlessBackend` for the
`BackendModule.Backend` seam. They are doubles, so by architectural requirement
they live in an example package, never in `main` — none is reachable from a
production build.
"""
module ProjecturedKernelExample

using ProjecturedKernel.CellModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.BackendModule
import ProjecturedKernel.ToolModule
import ProjecturedKernel.ToolModule: ToolSet, declare_api!, search_api, search_guides
import ProjecturedKernel.LlmModule: bind_meaning_model!
import ProjecturedKernel.LlmModule: Llm, stream_turn, LlmRequest, LlmToolUse,
    has_meaning_model, get_meaning_model_name, compute_meaning_vectors,
    LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
    LlmThinkingStart, LlmThinkingDelta, LlmThinkingSignature, LlmThinkingStop,
    LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
    LlmTurnEnd
import ProjecturedKernel.AgentModule
import ProjecturedKernel.AgentModule: AgentToolCallUpdate, AgentPermissionOption, AgentPermissionRequest,
    AgentOption, AgentOptionValue, AgentOptionsUpdate

include("../../../example/kernel/Harness.jl")
include("../../../example/kernel/LlmFake.jl")         # FakeLlm — canned-reply test double (no network)
include("../../../example/kernel/LlmScripted.jl")     # ScriptedLlm + scripted-round builders
include("../../../example/kernel/AgentScripted.jl")   # ScriptedAgentConnection — external-agent test double
include("../../../example/kernel/BackendHeadless.jl") # HeadlessBackend — in-memory backend test double
include("../../../example/kernel/SearchScaleMeasurement.jl") # what a search costs on a large corpus
include("../../../example/kernel/SearchCorpus.jl")           # the corpus of a whole application
include("../../../example/kernel/CallSite.jl")               # where a caller writes each name
include("../../../example/kernel/SearchRanking.jl")          # rankings of a search compared

export Example, AtomicDocument, force_projected
export write_example_image, record_example_video, make_typein_gestures
export FakeLlm, ScriptedLlm,
       make_scripted_turn, make_scripted_think, make_scripted_say, make_scripted_run
export ScriptedAgentConnection, make_scripted_permission_step, make_scripted_agent_options
export HeadlessBackend, rendered_output, push_event!
export ScaleQuestion, measure_search_scale!
export collect_package_modules, make_corpus_declaration, make_corpus_tool_set,
       describe_search_corpus
export CallSite, collect_call_sites, find_module_folder, rank_call_sites, format_call_sites,
       collect_definition_code
export SearchQuestion, make_search_question, make_candidate_text, SearchRanker,
       make_word_ranker, make_meaning_ranker, make_classifier_ranker, make_cascade_ranker,
       make_tree_ranker, measure_search_rankings, make_guide_units

end # module ProjecturedKernelExample
