"""
    AcpModule

Opt-in package: the client of the Agent Client Protocol (ACP), version 1, for an
agent that runs its own loop in another process, such as Claude through the
adapter `claude-agent-acp`. Depends on `ProjecturedKernel` plus JSON3, and
implements the external-agent seam of the kernel's `AgentModule`:
`AcpConnection` and its methods of `make_agent_connection`,
`start_agent_connection!`, `open_agent_session!`, `send_agent_prompt!`,
`cancel_agent_prompt!`, `close_agent_session!` and `stop_agent_connection!`.

**Every piece of the wire format of ACP lives here and nowhere else.** The
editor speaks the kernel's vocabulary: an `LlmText` prompt, the `LlmText…` and
`LlmThinking…` events of the answer, and the `AgentEvent`s of what the agent
does and asks. This package renders a prompt into JSON-RPC 2.0, and it
translates each `session/update` of the agent back into those events.

Three fragments share this namespace:

- [`AcpTransport.jl`](AcpTransport.jl) — JSON-RPC 2.0 over two streams, one
  message on each line: the ids, the reader task, the answers to the requests
  of the agent, and the end of the process of the agent.
- [`AcpUpdate.jl`](AcpUpdate.jl) — from a `session/update` to the events of the
  kernel.
- [`AcpConnection.jl`](AcpConnection.jl) — the connection: the methods of the
  client, and the methods of the seam.

**The client never handles a credential.** It sends no key, and it reads no
token. The agent signs in with its own flow. A notification that the client
does not use, such as the account status that an agent sends, is dropped
unread, and the transport logs no message content.
"""
module AcpModule

using ..KernelModule
using JSON3

# Imported to extend: this module adds a method to each of these.
import ..AgentModule: make_agent_connection, start_agent_connection!, open_agent_session!,
                      send_agent_prompt!, cancel_agent_prompt!, close_agent_session!,
                      stop_agent_connection!

export AcpRequestException
export AcpConnection

include("AcpTransport.jl")
include("AcpUpdate.jl")
include("AcpConnection.jl")

end # module AcpModule
