"""
    LlmModule

The **provider abstraction**: how the editor drives a language model, and what
comes back. Three fragments share this namespace:

- [`Llm.jl`](Llm.jl) — the `Llm` supertype and the `stream_turn` / `tool_schema`
  seams a provider implements.
- [`LlmMessage.jl`](LlmMessage.jl) — the conversation as the model sees it: content
  blocks, messages, and the `LlmRequest` for one turn.
- [`LlmEvent.jl`](LlmEvent.jl) — what streams back while the model answers.

**Nothing here is any provider's wire format.** Messages and events are the
project's own vocabulary; each adapter translates its protocol into them
(`ProjecturedLlm` for the Anthropic Messages API, the example doubles for tests).
That is the difference between an abstraction with implementations and a hook the
one implementation leaks through: a second provider writes an adapter, rather than
transcoding its stream into the first provider's event names.

Provider *configuration* — an API key, a model name, an endpoint, a token budget —
belongs to the concrete `Llm`, not to this seam. A local model has no API key and a
hosted one may want a region; `stream_turn` therefore takes only what varies per
turn.

Concrete backends live outside `main`: the real one in the opt-in `ProjecturedLlm`
package, the fakes (`FakeLlm`, `ScriptedLlm`) in `ProjecturedKernelExample`, never
in a `main` package (AR-NO-TEST-DOUBLES-IN-MAIN).
"""
module LlmModule

import ..DocumentModule: is_walk_opaque
import ..ToolModule: Tool

export Llm, stream_turn, tool_schema,
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
