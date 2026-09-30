"""
    LlmModule

The **provider abstraction**: how the editor drives a language model, and what
comes back. Five fragments share this namespace:

- [`LlmInterface.jl`](LlmInterface.jl) — the provider contract, declaration-only:
  the `Llm` supertype, the `stream_turn` / `render_tool_schema` seams a provider
  implements, the seams of the meaning model a provider can have, and the factory
  seams `make_llm` and `get_default_llm_model`.
- [`LlmDefaults.jl`](LlmDefaults.jl) — the fallbacks: a backend with no meaning
  model, and the forms of the two factories that take a symbol.
- [`Llm.jl`](Llm.jl) — what the layer does with the contract: a backend is opaque
  to the reflection walk, `bind_meaning_model!` gives a tool set the meaning model
  of a backend, and `get_llm_backend_names` reads the backends off the method
  table of `make_llm`.
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
package. A caller that must build one names it by symbol — `make_llm(kind)` —
and never its type, which is what lets the adapter live in a package whose types
cannot be referenced at load time.
"""
module LlmModule

using ..DocumentModule
using ..ToolModule

export Llm, stream_turn, render_tool_schema,
       has_meaning_model, get_meaning_model_name, compute_meaning_vectors,
       bind_meaning_model!,
       make_llm, get_default_llm_model, get_llm_backend_names,
       LlmContent, LlmText, LlmThinking, LlmRedactedThinking, LlmToolUse, LlmToolResult,
       LlmMessage, LlmRequest,
       LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
       LlmThinkingStart, LlmThinkingDelta, LlmThinkingSignature, LlmThinkingStop,
       LlmRedactedThinkingBlock,
       LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
       LlmTurnEnd, LlmFailure

include("LlmInterface.jl")  # the provider contract (declaration-only)
include("LlmDefaults.jl")   # the fallback behaviours the contract supplies itself
include("Llm.jl")
include("LlmMessage.jl")
include("LlmEvent.jl")

end # module
