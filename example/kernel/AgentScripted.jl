# Fragment of `ProjecturedKernelExample` — `ScriptedAgentConnection`, a test
# double for the kernel's external-agent seam (`AgentModule`), and
# `make_scripted_permission_step`, the step of a script that asks a person. It
# lives in the example package (never in `main`) so no fake reaches a
# production build.

"""
    ScriptedAgentConnection(turns; failing_opens = 0, on_start = nothing)

An external agent that plays `turns`, one for each prompt. A turn is a vector of
steps. A step that is an event goes to `on_event` as it is. A step that is a
function gets the connection and `on_event`, for an agent that waits, as
[`make_scripted_permission_step`](@ref) does.

The connection records what a test asserts: `sessions` holds the `directory` and
the `mcp_servers` of each session that opened, and `prompts` each prompt. A
cancel answers each request that waits as cancelled, and the turn then answers
`:cancelled`. A turn with no script answers `:end_turn` at once.

The first `failing_opens` sessions fail to open, as for an agent that needs a
sign-in. `on_start`, when given, gets the connection at each start, for a start
that takes its time.
"""
mutable struct ScriptedAgentConnection
    turns::Vector{Vector{Any}}
    cursor::Int
    is_started::Bool
    is_cancelled::Bool
    sessions::Vector{Any}
    prompts::Vector{Vector{Any}}
    waiting_replies::Vector{Function}
    answers::Vector{Any}
    failing_opens::Int
    on_start::Any
end

ScriptedAgentConnection(turns::AbstractVector; failing_opens::Integer = 0, on_start = nothing) =
    ScriptedAgentConnection([collect(Any, turn) for turn in turns], 0, false, false,
                            Any[], Vector{Any}[], Function[], Any[], Int(failing_opens), on_start)

function AgentModule.start_agent_connection!(connection::ScriptedAgentConnection)
    connection.on_start === nothing || connection.on_start(connection)
    connection.is_started = true
    connection
end

function AgentModule.open_agent_session!(connection::ScriptedAgentConnection;
                                         directory::AbstractString = pwd(),
                                         mcp_servers::AbstractVector = Any[])
    if connection.failing_opens > 0
        connection.failing_opens -= 1
        error("The scripted agent needs a sign-in.")
    end
    push!(connection.sessions, (directory = String(directory), mcp_servers = collect(mcp_servers)))
    "scripted-session-$(length(connection.sessions))"
end

function AgentModule.send_agent_prompt!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                        prompt::AbstractVector; on_event::Function)
    connection.is_cancelled = false
    push!(connection.prompts, collect(Any, prompt))
    connection.cursor += 1
    connection.cursor > length(connection.turns) && return :end_turn
    for step in connection.turns[connection.cursor]
        connection.is_cancelled && break
        step isa Function ? step(connection, on_event) : on_event(step)
    end
    connection.is_cancelled ? :cancelled : :end_turn
end

function AgentModule.cancel_agent_prompt!(connection::ScriptedAgentConnection, session_id::AbstractString)
    connection.is_cancelled = true
    foreach(reply -> reply(nothing), copy(connection.waiting_replies))
    nothing
end

AgentModule.close_agent_session!(connection::ScriptedAgentConnection, session_id::AbstractString) = nothing
AgentModule.stop_agent_connection!(connection::ScriptedAgentConnection) = nothing

"""
    make_scripted_permission_step(tool_call, options) -> Function

A step that asks a person whether the agent can run `tool_call`, an
`AgentToolCallUpdate`, with `options`, a vector of `AgentPermissionOption`. The
step waits at most ten seconds for the reply, and pushes the id of the chosen
option, or `nothing`, to the `answers` of the connection.
"""
function make_scripted_permission_step(tool_call::AgentToolCallUpdate,
                                       options::AbstractVector{AgentPermissionOption})
    function (connection::ScriptedAgentConnection, on_event::Function)
        choice = Channel{Any}(1)
        is_answered = Threads.Atomic{Bool}(false)
        reply = option_id -> (Threads.atomic_xchg!(is_answered, true) ? false : (put!(choice, option_id); true))
        push!(connection.waiting_replies, reply)
        on_event(AgentPermissionRequest(tool_call, collect(options), reply))
        answer = timedwait(() -> isready(choice), 10.0; pollint = 0.01) === :ok ? take!(choice) : nothing
        filter!(waiting -> waiting !== reply, connection.waiting_replies)
        push!(connection.answers, answer)
        nothing
    end
end
