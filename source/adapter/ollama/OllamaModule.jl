"""
    OllamaModule

Opt-in package: the Ollama adapter, for a model that runs on this machine. Depends
on `ProjecturedKernel` plus HTTP/JSON3, and implements the kernel's `LlmModule`
seam — `OllamaLlm`, its `stream_turn`, its `render_tool_schema`, its `make_llm`
method, and the meaning vectors it asks the server for.

**Every piece of Ollama's wire format lives here and nowhere else.** The kernel's
`LlmMessage` / `LlmEvent` / `Tool` vocabulary is the project's own; this package
renders a request into Ollama's JSON and translates its newline-delimited stream
back into `LlmEvent`s. Nothing upstream of `stream_turn` knows that `done_reason`
or `num_predict` exist.

Ollama's stream is shaped differently from Anthropic's in three ways that this
package answers and nobody else sees: there is no block framing, so the adapter
opens and closes the blocks itself; a tool call arrives whole in one line rather
than as streamed fragments; and a turn that made tool calls still reports
`done_reason: "stop"`, so the stop reason counts the calls.
"""
module OllamaModule

using ..KernelModule
using HTTP
using JSON3

# Imported to extend: this module adds a method to each of these.
import ..LlmModule: stream_turn, render_tool_schema, make_llm, get_default_llm_model,
                    has_meaning_model, get_meaning_model_name, compute_meaning_vectors

export OllamaLlm

include("OllamaLlm.jl")

end # module OllamaModule
