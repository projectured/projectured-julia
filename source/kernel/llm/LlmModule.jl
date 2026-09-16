"""
    LlmModule

The **provider abstraction**: how the editor drives a language model, and what
comes back. Three fragments share this namespace:

- [`Llm.jl`](Llm.jl) — the `Llm` supertype, the `stream_turn` / `render_tool_schema`
  seams a provider implements, and the meaning model a provider can have.
- [`LlmMessage.jl`](LlmMessage.jl) — the conversation as the model sees it: content
  blocks, messages, and the `LlmRequest` for one turn.
- [`LlmEvent.jl`](LlmEvent.jl) — what streams back while the model answers.

**Nothing here is any provider's wire format.** Messages and events are the
project's own vocabulary; each adapter translates its protocol into them
(one adapter per provider, plus test doubles).
That is the difference between an abstraction with implementations and a hook the
one implementation leaks through: a second provider writes an adapter, rather than
transcoding its stream into the first provider's event names.

Provider *configuration* — an API key, a model name, an endpoint, a token budget —
belongs to the concrete `Llm`, not to this seam. A local model has no API key and a
hosted one may want a region; `stream_turn` therefore takes only what varies per
turn.

Concrete backends live outside `main`: the real provider adapters in their own
opt-in packages, the test doubles in an example package, never in a `main`
package. A caller that must build one names it by symbol — `make_llm(:ollama)` —
and never its type, which is what lets the adapter live in a package whose types
cannot be referenced at load time.
"""
module LlmModule

using ..DocumentModule
using ..ToolModule

export Llm, stream_turn, render_tool_schema,
       has_meaning_model, get_meaning_model_name, compute_meaning_vectors,
       bind_meaning_model!,
       make_llm, default_llm_model, get_llm_backend_names,
       LlmContent, LlmText, LlmThinking, LlmRedactedThinking, LlmToolUse, LlmToolResult,
       LlmMessage, LlmRequest,
       LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
       LlmThinkingStart, LlmThinkingDelta, LlmThinkingSignature, LlmThinkingStop,
       LlmRedactedThinkingBlock,
       LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
       LlmTurnEnd, LlmFailure

include("Llm.jl")
include("LlmMessage.jl")
include("LlmEvent.jl")

end # module
