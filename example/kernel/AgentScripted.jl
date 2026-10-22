# Fragment of `ProjecturedKernelExample` — `ScriptedAgentConnection`, a test
# double for the kernel's external-agent seam (`AgentModule`), and
# `make_scripted_permission_step`, the step of a script that asks a person. It
# lives in the example package (never in `main`) so no fake reaches a
# production build.

"""
    ScriptedAgentConnection(turns; failing_opens = 0, on_start = nothing, options = AgentOption[],
                            can_resume = false, is_signed_in = true, sign_in_methods = AgentSignInMethod[],
                            can_sign_out = false, can_steer = false)

An external agent that plays `turns`, one for each prompt. A turn is a vector of
steps. A step that is an event goes to `on_event` as it is, also an event of the
work of the agent, such as an `AgentSubagentUpdate` or an
`AgentBackgroundTaskUpdate`. A step that is a function gets the connection and
`on_event`, for an agent that waits, as [`make_scripted_permission_step`](@ref)
does.

The connection records what a test asserts: `sessions` holds the `directory`,
the `mcp_servers`, the `instructions`, the asked `session_id` and the `events`
queue of each session that opened, and `prompts` each prompt. A test puts an
event that the agent sends between two prompts into that queue with
`put_agent_event!(connection.sessions[k].events, event)`. A connection that
`can_resume` resumes an asked session and answers its id; another one opens a
new session. A cancel answers each request that waits as cancelled, and the
turn then answers `:cancelled`. A turn with no script answers `:end_turn` at
once. `subagent_cancels` records each `cancel_agent_subagent!` as `session_id =>
subagent_id`, and `background_task_stops` each `stop_agent_background_task!` as
`session_id => task_id`, which answers `true`.

The first `failing_opens` sessions fail to open with a plain error. While
`is_signed_in` is `false`, an open and a prompt throw an `AgentSignInException`
with `sign_in_methods`; a test sets it to `true` for a sign-in that worked. A
method of `sign_in_methods` with no `command` is a sign-in that the agent runs
itself: `sign_in_agent!` with its id signs the connection in and answers
`true`, and `agent_sign_ins` records each call. A connection that
`can_sign_out` signs out when asked, and is then not signed in.
A connection that `can_steer` takes a prompt into the turn that runs, and
`steered` records each one; it takes none while no prompt runs.
`on_start`, when given, gets the connection at each start, for a start that
takes its time. `options` are the options of each session: an open and a
set give them to their `on_event`, and `option_sets` records each set as
`option_id => value`.
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
    options::Vector{AgentOption}
    option_sets::Vector{Pair{String,String}}
    can_resume::Bool
    is_signed_in::Bool
    sign_in_methods::Vector{AgentSignInMethod}
    agent_sign_ins::Vector{String}
    can_sign_out::Bool
    can_steer::Bool
    steered::Vector{Vector{Any}}
    is_prompting::Bool
    subagent_cancels::Vector{Pair{String,String}}
    background_task_stops::Vector{Pair{String,String}}
end

ScriptedAgentConnection(turns::AbstractVector; failing_opens::Integer = 0, on_start = nothing,
                        options::AbstractVector = AgentOption[], can_resume::Bool = false,
                        is_signed_in::Bool = true, sign_in_methods::AbstractVector = AgentSignInMethod[],
                        can_sign_out::Bool = false, can_steer::Bool = false) =
    ScriptedAgentConnection([collect(Any, turn) for turn in turns], 0, false, false,
                            Any[], Vector{Any}[], Function[], Any[], Int(failing_opens), on_start,
                            collect(AgentOption, options), Pair{String,String}[], can_resume,
                            is_signed_in, collect(AgentSignInMethod, sign_in_methods), String[], can_sign_out,
                            can_steer, Vector{Any}[], false, Pair{String,String}[], Pair{String,String}[])

# What a scripted agent that is not signed in throws.
_make_scripted_sign_in_exception(connection::ScriptedAgentConnection) =
    AgentSignInException("The scripted agent", copy(connection.sign_in_methods),
                         "The scripted agent needs a sign-in.")

function AgentModule.start_agent_connection!(connection::ScriptedAgentConnection)
    connection.on_start === nothing || connection.on_start(connection)
    connection.is_started = true
    connection
end

function AgentModule.open_agent_session!(connection::ScriptedAgentConnection;
                                         directory::AbstractString = pwd(),
                                         mcp_servers::AbstractVector = Any[], instructions::AbstractString = "",
                                         session_id::AbstractString = "", on_event = nothing,
                                         events::Union{Nothing,AgentEventQueue} = nothing)
    connection.is_signed_in || throw(_make_scripted_sign_in_exception(connection))
    if connection.failing_opens > 0
        connection.failing_opens -= 1
        error("The scripted agent fails to open a session.")
    end
    push!(connection.sessions, (directory = String(directory), mcp_servers = collect(mcp_servers),
                                instructions = String(instructions), session_id = String(session_id), events))
    on_event === nothing || isempty(connection.options) || on_event(AgentOptionsUpdate(copy(connection.options)))
    connection.can_resume && !isempty(session_id) && return String(session_id)
    "scripted-session-$(length(connection.sessions))"
end

function AgentModule.set_agent_option!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                       option_id::AbstractString, value::AbstractString; on_event = nothing)
    push!(connection.option_sets, String(option_id) => String(value))
    connection.options = AgentOption[option.id == option_id ?
        AgentOption(option.id, option.name, option.description, option.category, String(value), option.values) :
        option for option in connection.options]
    on_event === nothing || on_event(AgentOptionsUpdate(copy(connection.options)))
    nothing
end

"""
    make_scripted_agent_options() -> Vector{AgentOption}

Three options in the shape that `claude-agent-acp` gives: the model, the effort
and the mode, each with two values.
"""
make_scripted_agent_options() = AgentOption[
    AgentOption("model", "Model", "", :model, "opus",
                [AgentOptionValue("opus", "Opus 5.5", ""), AgentOptionValue("sonnet", "Sonnet 5.5", "")]),
    AgentOption("effort", "Effort", "", :thought_level, "high",
                [AgentOptionValue("high", "High", ""), AgentOptionValue("max", "Max", "")]),
    AgentOption("mode", "Mode", "", :mode, "default",
                [AgentOptionValue("default", "Manual", ""), AgentOptionValue("plan", "Plan", "")])]

function AgentModule.send_agent_prompt!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                        prompt::AbstractVector; on_event::Function)
    connection.is_signed_in || throw(_make_scripted_sign_in_exception(connection))
    connection.is_cancelled = false
    push!(connection.prompts, collect(Any, prompt))
    connection.cursor += 1
    connection.cursor > length(connection.turns) && return :end_turn
    connection.is_prompting = true
    try
        for step in connection.turns[connection.cursor]
            connection.is_cancelled && break
            step isa Function ? step(connection, on_event) : on_event(step)
        end
    finally
        connection.is_prompting = false
    end
    connection.is_cancelled ? :cancelled : :end_turn
end

AgentModule.has_agent_steering(connection::ScriptedAgentConnection) = connection.can_steer && connection.is_started

function AgentModule.steer_agent_prompt!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                         prompt::AbstractVector)
    (connection.can_steer && connection.is_prompting) || return false
    push!(connection.steered, collect(Any, prompt))
    true
end

function AgentModule.cancel_agent_prompt!(connection::ScriptedAgentConnection, session_id::AbstractString)
    connection.is_cancelled = true
    foreach(reply -> reply(nothing), copy(connection.waiting_replies))
    nothing
end

function AgentModule.cancel_agent_subagent!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                            subagent_id::AbstractString)
    push!(connection.subagent_cancels, String(session_id) => String(subagent_id))
    nothing
end

function AgentModule.stop_agent_background_task!(connection::ScriptedAgentConnection, session_id::AbstractString,
                                                 task_id::AbstractString)
    push!(connection.background_task_stops, String(session_id) => String(task_id))
    true
end

AgentModule.close_agent_session!(connection::ScriptedAgentConnection, session_id::AbstractString) = nothing
AgentModule.stop_agent_connection!(connection::ScriptedAgentConnection) = nothing

function AgentModule.sign_in_agent!(connection::ScriptedAgentConnection, method_id::AbstractString)
    push!(connection.agent_sign_ins, String(method_id))
    any(method -> method.id == method_id && method.command === nothing, connection.sign_in_methods) ||
        return false
    connection.is_signed_in = true
    true
end

AgentModule.has_agent_sign_out(connection::ScriptedAgentConnection) = connection.can_sign_out && connection.is_started

function AgentModule.sign_out_agent!(connection::ScriptedAgentConnection)
    AgentModule.has_agent_sign_out(connection) || return false
    connection.is_signed_in = false
    true
end

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

"""
    make_scripted_question_step(message, fields) -> Function

A step that asks a person a question in a form, an `AgentQuestionRequest` with
`message` and `fields`, a vector of `AgentQuestionField`. The step waits at most
ten seconds for the reply, and pushes the values, or `nothing`, to the
`answers` of the connection.
"""
function make_scripted_question_step(message::AbstractString, fields::AbstractVector{AgentQuestionField})
    function (connection::ScriptedAgentConnection, on_event::Function)
        answer = Channel{Any}(1)
        is_answered = Threads.Atomic{Bool}(false)
        reply = values -> (Threads.atomic_xchg!(is_answered, true) ? false : (put!(answer, values); true))
        push!(connection.waiting_replies, reply)
        on_event(AgentQuestionRequest(String(message), collect(fields), reply))
        values = timedwait(() -> isready(answer), 10.0; pollint = 0.01) === :ok ? take!(answer) : nothing
        filter!(waiting -> waiting !== reply, connection.waiting_replies)
        push!(connection.answers, values)
        nothing
    end
end
