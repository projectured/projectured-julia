"""
    AcpModule

Opt-in package: the client of the Agent Client Protocol (ACP), version 1, for an
agent that runs its own loop in another process, such as Claude through the
adapter `claude-agent-acp`. Depends on `ProjecturedKernel` plus
`AgentClientProtocol`, and implements the external-agent seam of the kernel's
`AgentModule`:
`AcpConnection` and its methods of `make_agent_connection`,
`start_agent_connection!`, `open_agent_session!`, `set_agent_option!`,
`send_agent_prompt!`, `cancel_agent_prompt!`, `close_agent_session!` and
`stop_agent_connection!`.

**ACP reaches the editor only through this package.** The editor speaks the
kernel's vocabulary: an `LlmText` prompt, the `LlmText…` and `LlmThinking…`
events of the answer, and the `AgentEvent`s of what the agent does and asks.
The package `AgentClientProtocol` holds the types of the protocol and the
connection: JSON-RPC 2.0 over two streams, the process of the agent and its
end. This package makes the requests of the protocol from the calls of the
seam, and it translates each `session/update` of the agent back into the
events of the kernel.

Two fragments share this namespace:

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
import AgentClientProtocol as ACP

# Imported to extend: this module adds a method to each of these.
import ..AgentModule: make_agent_connection, start_agent_connection!, open_agent_session!,
                      set_agent_option!, send_agent_prompt!, cancel_agent_prompt!,
                      close_agent_session!, stop_agent_connection!

export AcpConnection

include("AcpUpdate.jl")
include("AcpConnection.jl")

end # module AcpModule
