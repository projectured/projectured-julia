# Fragment of `LlmModule` — the conversation as a model sees it, and the request
# for one turn.
#
# This is the project's own vocabulary, not any provider's. An adapter renders it
# into its wire format; a caller builds it from whatever it actually has.

"""
    LlmContent

One block inside a message. A message is an ordered sequence of these, because
that is what the model produces: reasoning, then prose, then a tool call, in order.
"""
abstract type LlmContent end

"""
    LlmText(text)

Prose — what the model says, or what the user typed.
"""
struct LlmText <: LlmContent
    text::String
end

"""
    LlmThinking(text, signature)

A block of the model's reasoning. `signature` is an opaque token the provider
returns with the block and expects back verbatim when the conversation continues;
dropping or altering it invalidates the turn, so it is carried, never inspected.
"""
struct LlmThinking <: LlmContent
    text::String
    signature::String
end

"""
    LlmRedactedThinking(data)

Reasoning the provider withheld: an opaque payload with no readable text. It must
still be echoed back with the conversation, so it is kept as-is.
"""
struct LlmRedactedThinking <: LlmContent
    data::String
end

"""
    LlmToolUse(id, name, input)

The model asking for a tool to be run. `id` pairs this call with the
`LlmToolResult` that answers it.
"""
struct LlmToolUse <: LlmContent
    id::String
    name::String
    input::Dict{String,Any}
end

"""
    LlmToolResult(tool_use_id, content, is_error)

The answer to an `LlmToolUse`, carrying the tool's textual output. `tool_use_id`
is the `id` of the call it answers.
"""
struct LlmToolResult <: LlmContent
    tool_use_id::String
    content::String
    is_error::Bool
end

"""
    LlmMessage(role, content)

One message: a `role` (`:user` or `:assistant`) and its ordered content blocks.
"""
struct LlmMessage
    role::Symbol
    content::Vector{LlmContent}
end

LlmMessage(role::Symbol, content::LlmContent) = LlmMessage(role, LlmContent[content])
LlmMessage(role::Symbol, text::AbstractString) = LlmMessage(role, LlmText(String(text)))

"""
    LlmRequest(; system, messages, tools, thinking)

Everything one turn needs, and nothing that belongs to the backend:

- `system`   — the system prompt.
- `messages` — the conversation so far.
- `tools`    — the tools the model may call. The adapter renders them with
               `render_tool_schema`; a `Tool` carries no wire format itself.
- `thinking` — ask for extended reasoning if this provider has it. A *request*,
               not a configuration: whether the model supports it, and what the
               provider's parameter for it looks like, is the adapter's business.

The API key, model name, and endpoint are deliberately absent — they identify the
backend, and live on it.
"""
struct LlmRequest
    system::String
    messages::Vector{LlmMessage}
    tools::Vector{Tool}
    thinking::Bool
end

LlmRequest(; system::AbstractString = "",
             messages::AbstractVector{LlmMessage} = LlmMessage[],
             tools::AbstractVector{Tool} = Tool[],
             thinking::Bool = false) =
    LlmRequest(String(system), collect(LlmMessage, messages), collect(Tool, tools),
               thinking)
