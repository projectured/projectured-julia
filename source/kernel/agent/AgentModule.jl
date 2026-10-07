"""
    AgentModule

The agent layer, in its three directions. The **outbound** half is the only thing
in the kernel that is actually an *agent*: the glue between a language model, a set
of tools, and something to act on. The **inbound** half is the contract through
which an agent outside the process drives this editor. The **external** direction
is the contract through which this editor drives an agent that runs its own loop
in another process.

Seven fragments share this namespace:

- [`Agent.jl`](Agent.jl) — the `Agent` itself, and the `AgentToolResult` event it
  reports a completed tool call with.
- [`AgentLoop.jl`](AgentLoop.jl) — `run_turn!`, the loop.
- [`AgentInterface.jl`](AgentInterface.jl) — the agent-server contract:
  `make_agent_server`, `start_agent_server!`, `stop_agent_server!` and
  `run_on_editor_task!`, each a body-less generic.
- [`AgentDefaults.jl`](AgentDefaults.jl) — the fallback behaviours for that
  contract, answered when no concrete server package is loaded.
- [`AgentConnectionInterface.jl`](AgentConnectionInterface.jl) — the
  external-agent contract: `make_agent_connection`, `start_agent_connection!`,
  `open_agent_session!`, `send_agent_prompt!`, `cancel_agent_prompt!`,
  `close_agent_session!` and `stop_agent_connection!`, each a body-less generic.
- [`AgentConnectionDefaults.jl`](AgentConnectionDefaults.jl) — the fallback
  behaviours for that contract.
- [`AgentConnectionEvent.jl`](AgentConnectionEvent.jl) — the events an external
  agent reports: `AgentToolCallUpdate`, `AgentPlanUpdate` and
  `AgentPermissionRequest`.

**What the loop owns, and what it does not.** It owns the *control flow* of an agent
turn: stream a round, collect the tool calls the model made, dispatch them through
the `ToolSet`, go again while the model asks for a tool, and stop at the round cap.
It owns nothing about *conversations* — how a transcript is stored, how a
message is built from it, how an answer is rendered are all the caller's, because
they are the caller's domain and not an agent's. The seam is two functions:
`messages`, which the loop calls to get the prompt, and `on_event`, which the loop
calls with everything that happens.

The agent-server contract of `AgentInterface.jl` is the mirror image: the
inbound direction, where an agent outside the process drives *this* editor.
A concrete server (e.g. `:mcp`) lives in its own optional package and answers
`make_agent_server(::Val{kind}, editor; kwargs...)`. Both halves use the editor's
`ToolSet`: an agent server publishes it, and an agent loop calls it. Both call it
from a task that is not the editor's, so both make their calls through
`run_on_editor_task!`.

The external contract has no tool set of its own: the agent runs its own tools,
and it reaches the tools of the editor through an agent server that the caller
names in `open_agent_session!`.
"""
module AgentModule

using ..FaultModule
using ..LlmModule
using ..ToolModule

export Agent, run_turn!, AgentEvent, AgentToolResult
export make_agent_server, start_agent_server!, stop_agent_server!, run_on_editor_task!
export get_agent_server_names
export make_agent_connection, start_agent_connection!, open_agent_session!,
       send_agent_prompt!, cancel_agent_prompt!, close_agent_session!,
       stop_agent_connection!, get_agent_connection_names
export AgentToolCallUpdate, AgentPlanEntry, AgentPlanUpdate,
       AgentPermissionOption, AgentPermissionRequest

include("AgentInterface.jl")
include("AgentDefaults.jl")
include("Agent.jl")
include("AgentLoop.jl")
include("AgentConnectionInterface.jl")
include("AgentConnectionDefaults.jl")
include("AgentConnectionEvent.jl")

end # module
