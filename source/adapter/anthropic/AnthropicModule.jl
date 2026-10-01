"""
    AnthropicModule

Opt-in package: the Anthropic Messages API adapter. Depends on `ProjecturedKernel`
plus HTTP/JSON3, and implements the kernel's `LlmModule` seam for real Claude —
`AnthropicLlm`, its `stream_turn`, its `render_tool_schema`, and its `make_llm` method.

**Every piece of Anthropic's wire format lives here and nowhere else.** The kernel's
`LlmMessage` / `LlmEvent` / `Tool` vocabulary is the project's own; this package
renders a request into Anthropic's JSON, and translates Anthropic's SSE stream back
into `LlmEvent`s. Nothing upstream of `stream_turn` knows that `content_block_delta`
or `input_schema` exist. A second provider is another package shaped like this one,
not a transcoding into Anthropic's names.
"""
module AnthropicModule

using ..KernelModule
using HTTP
using JSON3

# Imported to extend: this module adds a method to each of these.
import ..LlmModule: stream_turn, render_tool_schema, make_llm, get_default_llm_model

export get_newest_anthropic_model, find_adaptive_model, AnthropicLlm

include("AnthropicLlm.jl")

end # module AnthropicModule
