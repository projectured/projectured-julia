# ── Llm layer — the provider abstraction ───────────────────────────────────
# The ordered include list of the llm layer; a fragment of ProjecturedKernel.
# LlmModule is what an editor drives a language model *through*: a request
# (system prompt, messages, the tools it may call), a stream of events coming
# back, and the `stream_turn` seam a provider implements.
#
# The vocabulary here is deliberately nobody's wire format. A provider adapter
# translates its own protocol into these messages and events, so a second
# provider is a new adapter, not a transcoding of the first provider's event
# names. The concrete adapters and the test doubles live outside this package.
#
# The layer imports the tool layer (a request carries the tools the model may
# call) and knows nothing of MCP or of the agent loop above it.
include("LlmModule.jl")
