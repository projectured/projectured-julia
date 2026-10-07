# Fragment of `AgentModule` — the agent-server **contract**: the seams of the
# inbound half, a channel that lets an agent *outside* this process inspect
# and manipulate a running editor — conceptually another device/backend,
# reading operations from an agent and writing document state back — and
# `run_on_editor_task!`, which both halves call.
#
# Concrete servers live in their own packages and register methods for these
# generics. A caller reaches a server only through them, so it never names a
# concrete server type, which is what lets the implementation live in an
# optional package whose types cannot be referenced at load time. Nothing here
# carries a body — the fallback behaviours sit in `AgentDefaults.jl`.

"""
    make_agent_server(kind::Symbol, editor; kwargs...)

Construct an agent server of the given `kind` (e.g. `:mcp`) bound to `editor`.
A server package answers `make_agent_server(::Val{kind}, editor; kwargs...)`;
the `Symbol` entry redispatches, and a missing method (its optional package
not loaded) raises a helpful error — both in `AgentDefaults.jl`.
"""
function make_agent_server end

"""
    start_agent_server!(server)

Start the agent server (begin processing in the background).
"""
function start_agent_server! end

"""
    stop_agent_server!(server)

Stop the agent server and release its resources.
"""
function stop_agent_server! end

"""
    get_agent_server_access(server) -> (name, url, headers)

What a client needs to reach `server`: its `name`, its `url`, and the `headers`
that each request must carry, a `Vector{Pair{String,String}}`. The tuple has the
shape that `open_agent_session!` takes for an MCP server, so a caller hands the
server of its editor to an external agent.
"""
function get_agent_server_access end

"""
    run_on_editor_task!(function_, target; wait = true) -> value

Run `function_()` on the task that owns `target`, and answer its value.

A frame of a running editor reads, evaluates and paints the document, so a write
from another task races the frame. A tool that a client calls from the task of a
server, and a turn of a model that streams on a task of its own, therefore make
their writes through this door: the editor applies the call at the top of its
next frame, where it applies every posted operation, and the calling task waits
for the answer. An exception that `function_` throws is thrown again on the
calling task.

With `wait = false` the call is only posted, and the answer is `nothing`. The
posts of one task are applied in the order they were made, and before any call
that the same task makes after them with `wait = true`.

The call runs at once, on the calling task, when nothing runs a loop for
`target`, or when the calling task is the one that runs it. So a call from the
editor's own task, and a call in a test that drives no loop, never wait.

The default runs the call at once for every target. A target type whose loop can
run on another task adds a method that posts the call to that loop.
"""
function run_on_editor_task! end
