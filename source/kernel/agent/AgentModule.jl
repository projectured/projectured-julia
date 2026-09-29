"""
    AgentModule

The agent layer, in both of its halves. The **outbound** half is the only thing in
the kernel that is actually an *agent*: the glue between a language model, a set of
tools, and something to act on. The **inbound** half is the contract through which
an agent outside the process drives this editor.

Four fragments share this namespace:

- [`Agent.jl`](Agent.jl) — the `Agent` itself, and the `AgentToolResult` event it
  reports a completed tool call with.
- [`AgentLoop.jl`](AgentLoop.jl) — `run_turn!`, the loop.
- [`AgentInterface.jl`](AgentInterface.jl) — the agent-server contract:
  `make_agent_server`, `start_agent_server!`, `stop_agent_server!` and
  `run_on_editor_task!`, each a body-less generic.
- [`AgentDefaults.jl`](AgentDefaults.jl) — the fallback behaviours for that
  contract, answered when no concrete server package is loaded.

**What the loop owns, and what it does not.** It owns the *control flow* of an agent
turn: stream a round, collect the tool calls the model made, dispatch them through
the `ToolSet`, decide from the stop reason whether to go again, and stop at the round
cap. It owns nothing about *conversations* — how a transcript is stored, how a
message is built from it, how an answer is rendered are all the caller's, because
they are the caller's domain and not an agent's. The seam is two functions:
`messages`, which the loop calls to get the prompt, and `on_event`, which the loop
calls with everything that happens.

The agent-server contract of `AgentInterface.jl` is the mirror image: the
inbound direction, where an agent outside the process drives *this* editor.
A concrete server (e.g. `:mcp`) lives in its own optional package and answers
`make_agent_server(::Val{kind}, editor; kwargs...)`.
"""
module AgentModule

using ..FaultModule
using ..LlmModule
using ..ToolModule

export Agent, run_turn!, AgentEvent, AgentToolResult
export make_agent_server, start_agent_server!, stop_agent_server!, run_on_editor_task!

include("AgentInterface.jl")
include("AgentDefaults.jl")
include("Agent.jl")
include("AgentLoop.jl")

end # module
