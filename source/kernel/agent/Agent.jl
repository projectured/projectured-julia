# Fragment of `AgentModule` — the agent, and the one event the loop adds to the
# model's own.

"""
    Agent(llm, tools; system = "", max_rounds = 5, thinking = true)

A language model, the tools it may call, and how a turn with it is run.

- `llm`        — the backend. Its API key and model are its own configuration.
- `tools`      — the `ToolSet` it may call; in practice an editor's own.
- `system`     — the system prompt.
- `max_rounds` — a hard cap on rounds in one turn, so a model that keeps asking for
                 tools can never run away. Hitting it ends the turn with a warning.
- `thinking`   — ask for extended reasoning where the backend has it.

An `Agent` holds no transcript. What was said is the caller's — it already has a
conversation, and a second copy inside the agent could only drift from it.
"""
mutable struct Agent
    llm::Llm
    tools::ToolSet
    system::String
    max_rounds::Int
    thinking::Bool
end

Agent(llm::Llm, tools::ToolSet; system::AbstractString = "",
      max_rounds::Integer = 5, thinking::Bool = true) =
    Agent(llm, tools, String(system), Int(max_rounds), thinking)

"""
    AgentEvent

Something the *loop* did, as opposed to something the model said (an `LlmEvent`).
A turn's `on_event` sees both.
"""
abstract type AgentEvent end

"""
    AgentToolResult(call, output, is_error)

A tool the model asked for has been run. `call` is the request it answers — its
`id` pairs the two when the conversation is replayed — `output` is the tool's
textual result, and `is_error` says whether it failed.

The loop reports the result rather than storing it, because what a result *is* to
the caller varies: one caller renders it live in a chat, another puts it on the
wire, and a script might just print it.
"""
struct AgentToolResult <: AgentEvent
    call::LlmToolUse
    output::String
    is_error::Bool
end
