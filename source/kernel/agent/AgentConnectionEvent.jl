# Fragment of `AgentModule` — the events an external agent reports, beside the
# text and the reasoning that arrive as `LlmEvent`s, the sign-in that an agent
# can ask for, and the queue that holds the events of a session between two
# prompts. A connection translates its protocol into these, so a caller never
# sees the protocol.

"""
    AgentToolCallUpdate(id; name, title, kind, status, input, output, output_mime_type, output_uri)

A tool call of an external agent, new or changed. The agent runs the tool
itself, and the event only reports it. `id` names the call across its updates,
and a field that is `nothing` keeps the value of the last update of the same
`id`.

- `name`   — the name of the tool for a program, when the agent gives one.
- `title`  — the words that tell a person what the call does.
- `kind`   — `:read`, `:edit`, `:delete`, `:move`, `:search`, `:execute`,
             `:think`, `:fetch`, `:switch_mode` or `:other`.
- `status` — `:pending`, `:in_progress`, `:completed` or `:failed`.
- `input`  — the input of the tool, as the agent gives it.
- `output` — the text of what the tool answered.
- `output_mime_type` — the media type of `output`, such as `"text/markdown"`, when
  the agent says it, as it does for the text of a file that the tool read.
- `output_uri` — the uri of what `output` holds, such as `file:///a.md`, when the
  agent says it.

`output_mime_type` and `output_uri` go with the `output` of the same update.
"""
struct AgentToolCallUpdate <: AgentEvent
    id::String
    name::Union{Nothing,String}
    title::Union{Nothing,String}
    kind::Union{Nothing,Symbol}
    status::Union{Nothing,Symbol}
    input::Union{Nothing,Dict{String,Any}}
    output::Union{Nothing,String}
    output_mime_type::Union{Nothing,String}
    output_uri::Union{Nothing,String}
end

AgentToolCallUpdate(id::AbstractString; name = nothing, title = nothing, kind = nothing,
                    status = nothing, input = nothing, output = nothing, output_mime_type = nothing,
                    output_uri = nothing) =
    AgentToolCallUpdate(String(id), name, title, kind, status, input, output, output_mime_type, output_uri)

"""
    AgentPlanEntry(content, priority, status; id = "", description = "", active_title = "", blocked_by = String[])

One step of a plan of an external agent: `content` is its title, `priority` is
`:high`, `:medium` or `:low`, and `status` is `:pending`, `:in_progress` or
`:completed`.

- `id`           — the id of the step, which `blocked_by` of another step
                   names; empty when the agent gives none.
- `description`  — what the step is about, in more words than its title.
- `active_title` — what the agent does while the step is in progress, such as
                   "Running the tests"; empty when the agent gives none.
- `blocked_by`   — the ids of the steps that must be completed before this one.

Two entries are equal when their fields are equal.
"""
struct AgentPlanEntry
    content::String
    priority::Symbol
    status::Symbol
    id::String
    description::String
    active_title::String
    blocked_by::Vector{String}
end

AgentPlanEntry(content::AbstractString, priority::Symbol, status::Symbol; id::AbstractString = "",
               description::AbstractString = "", active_title::AbstractString = "",
               blocked_by::AbstractVector = String[]) =
    AgentPlanEntry(String(content), priority, status, String(id), String(description), String(active_title),
                   String[String(blocker) for blocker in blocked_by])

Base.:(==)(a::AgentPlanEntry, b::AgentPlanEntry) =
    (a.content, a.priority, a.status, a.id, a.description, a.active_title, a.blocked_by) ==
    (b.content, b.priority, b.status, b.id, b.description, b.active_title, b.blocked_by)

Base.hash(entry::AgentPlanEntry, seed::UInt) =
    hash((entry.content, entry.priority, entry.status, entry.id, entry.description, entry.active_title,
          entry.blocked_by), hash(AgentPlanEntry, seed))

"""
    AgentPlanUpdate(entries; id = "", markdown = nothing, uri = nothing, is_removed = false)

A plan of an external agent as it stands now. A session can have several plans,
each with its `id`, and the one plan of an agent that names no plan has the
empty id. Each update replaces the plan of its `id`.

The content of a plan is one of three: its steps, `entries`; a Markdown text,
`markdown`; or the `uri` of a file that holds it. The other two are then empty
and `nothing`. An update with `is_removed` removes the plan of its `id`, and has
no content.
"""
struct AgentPlanUpdate <: AgentEvent
    entries::Vector{AgentPlanEntry}
    id::String
    markdown::Union{Nothing,String}
    uri::Union{Nothing,String}
    is_removed::Bool
end

AgentPlanUpdate(entries::AbstractVector; id::AbstractString = "", markdown::Union{Nothing,AbstractString} = nothing,
                uri::Union{Nothing,AbstractString} = nothing, is_removed::Bool = false) =
    AgentPlanUpdate(collect(AgentPlanEntry, entries), String(id), markdown === nothing ? nothing : String(markdown),
                    uri === nothing ? nothing : String(uri), is_removed)

"""
    AgentPermissionOption(id, name, kind)

One answer that a person can give to an `AgentPermissionRequest`. `kind` is
`:allow_once`, `:allow_always`, `:reject_once` or `:reject_always`.
"""
struct AgentPermissionOption
    id::String
    name::String
    kind::Symbol
end

"""
    AgentPermissionRequest(tool_call, options, reply)

An external agent asks whether it can run `tool_call`, and waits for the answer.
`reply` takes the `id` of the option that the person chose, or `nothing` when
the person chose none. The first call answers the agent and answers `true`. A
later call does nothing and answers `false`, so a caller can tell an answer that
reached the agent from one that came too late. A cancel of the turn answers the
request as `nothing`.
"""
struct AgentPermissionRequest <: AgentEvent
    tool_call::AgentToolCallUpdate
    options::Vector{AgentPermissionOption}
    reply::Function
end


"""
    AgentOptionValue(value, name, description)

One value that an option of an external agent can take: `value` is what the
agent reads, and `name` and `description` are what a person reads.
"""
struct AgentOptionValue
    value::String
    name::String
    description::String
end

"""
    AgentQuestionField(name, title, description, kind, options, is_required)

One field of a question that an external agent asks a person. `name` is the key
of its value in the answer, and `title` and `description` are what a person
reads. `kind` is `:choice` (one of `options`), `:choices` (any of `options`),
`:text`, `:number`, `:integer` or `:boolean`. `options` are the values of a
choice, each an `AgentOptionValue` with the `value` that the answer holds and
the `name` and `description` that a person reads; they are empty for another
kind.
"""
struct AgentQuestionField
    name::String
    title::String
    description::String
    kind::Symbol
    options::Vector{AgentOptionValue}
    is_required::Bool
end

"""
    AgentQuestionRequest(message, fields, reply)

An external agent asks a person a question, and waits for the answer. `message`
says what the agent asks, and `fields` are what the person fills in. `reply`
takes a `Dict{String,Any}` from the `name` of each field that the person filled
to its value: a `String` for a choice or a text, a `Vector{String}` for
choices, a number, or a `Bool`; or `nothing` when the person declined. The
first call answers the agent and answers `true`; a later call does nothing and
answers `false`. A cancel of the turn answers the request as cancelled.
"""
struct AgentQuestionRequest <: AgentEvent
    message::String
    fields::Vector{AgentQuestionField}
    reply::Function
end

"""
    AgentOption(id, name, description, category, current_value, values)

One option of a session of an external agent, such as its model. `category`
says what kind of option it is: `:mode`, `:model`, `:thought_level` (how much
the model reasons), `:model_config`, or `:other`. `current_value` is the
`value` of the value that holds now, and `values` lists every value it can take.
"""
struct AgentOption
    id::String
    name::String
    description::String
    category::Symbol
    current_value::String
    values::Vector{AgentOptionValue}
end

"""
    AgentOptionsUpdate(options)

All the options of a session of an external agent as they stand now. Each update
replaces the options before it.
"""
struct AgentOptionsUpdate <: AgentEvent
    options::Vector{AgentOption}
end

"""
    AgentUsageUpdate(used, size, cost, currency)

How much of its context window the session of an external agent uses: `used`
tokens of `size`. `cost` is what the session has cost so far, in `currency`, or
`nothing` when the agent does not say.
"""
struct AgentUsageUpdate <: AgentEvent
    used::Int
    size::Int
    cost::Union{Nothing,Float64}
    currency::String
end

"""
    AgentSessionInfoUpdate(title; process_id = nothing)

What the agent says of its session: its `title`, a short name of what the
session is about, and `process_id`, the id of the system process that does the
work of the session. `nothing` keeps the value before, and an empty title
clears the title.
"""
struct AgentSessionInfoUpdate <: AgentEvent
    title::Union{Nothing,String}
    process_id::Union{Nothing,Int}
end

AgentSessionInfoUpdate(title::Union{Nothing,AbstractString}; process_id::Union{Nothing,Integer} = nothing) =
    AgentSessionInfoUpdate(title === nothing ? nothing : String(title),
                           process_id === nothing ? nothing : Int(process_id))

"""
    AgentCommand(name, description, input_hint)

A command that an external agent offers, which a person runs by writing `/name`
at the start of a prompt. `input_hint` says what the command takes after its
name, empty when it takes nothing.
"""
struct AgentCommand
    name::String
    description::String
    input_hint::String
end

"""
    AgentCommandsUpdate(commands)

All the commands that the session of an external agent offers now. Each update
replaces the commands before it.
"""
struct AgentCommandsUpdate <: AgentEvent
    commands::Vector{AgentCommand}
end

"""
    AgentSubagentUpdate(id; title, description, state, stop_reason, token_count, tool_call_count, duration,
                        last_tool, summary, can_cancel, event)

A subagent of an external agent, new or changed: an agent that the agent starts
for a part of its work, with a session of its own. `id` names the subagent
across its updates, and a field that is `nothing` keeps the value of the last
update of the same `id`.

- `title`, `description` — what the subagent is for, in words for a person.
- `state`           — `:running`, `:idle` (it waits for work), `:requires_action`
                      (it waits for a person) or `:unknown`.
- `stop_reason`     — why its last work ended, as `send_agent_prompt!` answers
                      it, such as `:end_turn` or `:cancelled`.
- `token_count`     — how many tokens its work used.
- `tool_call_count` — how many tool calls it made.
- `duration`        — how long it worked, in seconds.
- `last_tool`       — the name of the last tool that it called.
- `summary`         — what it did, in a few words.
- `can_cancel`      — whether `cancel_agent_subagent!` can stop its work.
- `event`           — one event of the subagent, as `send_agent_prompt!` gives
                      the events of a session: its text, its reasoning, a tool
                      call or a plan. The prompt of the subagent is an
                      `LlmMessage` of the role `:user`. An update of a subagent
                      of this subagent is an `AgentSubagentUpdate` here.
"""
struct AgentSubagentUpdate <: AgentEvent
    id::String
    title::Union{Nothing,String}
    description::Union{Nothing,String}
    state::Union{Nothing,Symbol}
    stop_reason::Union{Nothing,Symbol}
    token_count::Union{Nothing,Int}
    tool_call_count::Union{Nothing,Int}
    duration::Union{Nothing,Float64}
    last_tool::Union{Nothing,String}
    summary::Union{Nothing,String}
    can_cancel::Union{Nothing,Bool}
    event::Union{Nothing,AgentEvent,LlmEvent,LlmMessage}
end

AgentSubagentUpdate(id::AbstractString; title = nothing, description = nothing, state = nothing,
                    stop_reason = nothing, token_count = nothing, tool_call_count = nothing, duration = nothing,
                    last_tool = nothing, summary = nothing, can_cancel = nothing, event = nothing) =
    AgentSubagentUpdate(String(id), title, description, state, stop_reason, token_count, tool_call_count,
                        duration, last_tool, summary, can_cancel, event)

"""
    AgentBackgroundTaskUpdate(id; kind, title, status, tool_call_id, subagent_id, output_uri, summary,
                              start_time, end_time, can_stop)

A background task of an external agent, new or changed: work that the agent
started and that runs after the call that started it, such as a command that
runs in the background. `id` names the task across its updates, and a field
that is `nothing` keeps the value of the last update of the same `id`.

- `kind`         — what kind of work it is, as the agent names it, such as
                   `:local_bash` or `:monitor`.
- `title`        — what it does, in words for a person.
- `status`       — `:running`, `:completed`, `:failed` or `:stopped`.
- `tool_call_id` — the `id` of the `AgentToolCallUpdate` that started it.
- `subagent_id`  — the `id` of the `AgentSubagentUpdate` of the subagent that
                   started it.
- `output_uri`   — the uri of the file that holds its output, such as
                   `file:///tmp/output.txt`.
- `summary`      — what it did, in a few words.
- `start_time`, `end_time` — when it started and when it ended, in seconds
                   since 1970, as `time()` answers.
- `can_stop`     — whether `stop_agent_background_task!` can stop it.
"""
struct AgentBackgroundTaskUpdate <: AgentEvent
    id::String
    kind::Union{Nothing,Symbol}
    title::Union{Nothing,String}
    status::Union{Nothing,Symbol}
    tool_call_id::Union{Nothing,String}
    subagent_id::Union{Nothing,String}
    output_uri::Union{Nothing,String}
    summary::Union{Nothing,String}
    start_time::Union{Nothing,Float64}
    end_time::Union{Nothing,Float64}
    can_stop::Union{Nothing,Bool}
end

AgentBackgroundTaskUpdate(id::AbstractString; kind = nothing, title = nothing, status = nothing,
                          tool_call_id = nothing, subagent_id = nothing, output_uri = nothing, summary = nothing,
                          start_time = nothing, end_time = nothing, can_stop = nothing) =
    AgentBackgroundTaskUpdate(String(id), kind, title, status, tool_call_id, subagent_id, output_uri, summary,
                              start_time, end_time, can_stop)

"""
    AgentNoticeUpdate(severity, title, description)

A note of an external agent for a person, which needs no answer, such as a
request to its model that it tries again. `severity` is `:info`, `:warning` or
`:error`, and `description` is empty when the agent gives none.
"""
struct AgentNoticeUpdate <: AgentEvent
    severity::Symbol
    title::String
    description::String
end

"""
    AgentCompactionUpdate(id, status, summary)

A compaction of the context of a session of an external agent, new or changed:
the agent puts a summary in the place of the older part of its history, so the
session fits its context window. `id` names the compaction across its updates,
and `status` is `:in_progress`, `:completed`, `:failed` or `:cancelled`.
`summary` is the text that the compaction keeps; `nothing` keeps the summary of
the last update of the same `id`, and an empty one clears it.
"""
struct AgentCompactionUpdate <: AgentEvent
    id::String
    status::Symbol
    summary::Union{Nothing,String}
end

"""
    AgentSignInMethod(id, name, description, command)

A way to sign in to an external agent. `command` is the program of a sign-in in
a terminal, with its arguments, its environment and its folder: a person answers
it in a terminal, and it ends with the status 0 when the sign-in worked. A
`command` of `nothing` is a sign-in that the agent runs itself, such as in the
browser, when [`sign_in_agent!`](@ref) asks for it.
"""
struct AgentSignInMethod
    id::String
    name::String
    description::String
    command::Union{Cmd,Nothing}
end

"""
    AgentSignInException(agent_title, methods, message)

Thrown when an external agent needs a sign-in before it opens a session or runs
a prompt. `methods` are the ways to sign in that this editor can run, and can be
empty. `message` says how to sign in, in words for a person.
"""
struct AgentSignInException <: Exception
    agent_title::String
    methods::Vector{AgentSignInMethod}
    message::String
end

Base.showerror(io::IO, exception::AgentSignInException) = print(io, exception.message)

"""
    AgentEventQueue()

The events of a stream in the order in which they came: the events of a session
of an external agent, which a connection puts with [`put_agent_event!`](@ref) on a
task of its own, or the events of a turn of a model that a task streams. The
caller that opened the session or started the turn takes them all with
[`take_agent_events!`](@ref). The queue holds the events and a lock, and no
function.
"""
mutable struct AgentEventQueue
    lock::ReentrantLock
    events::Vector{Any}
end

AgentEventQueue() = AgentEventQueue(ReentrantLock(), Any[])

"""
    put_agent_event!(queue, event)

Put `event` at the end of `queue`. Any task can call it.
"""
function put_agent_event!(queue::AgentEventQueue, event)
    lock(() -> push!(queue.events, event), queue.lock)
    nothing
end

"""
    take_agent_events!(queue) -> Vector{Any}

Every event of `queue`, the oldest first, which leaves the queue empty. Any task
can call it.
"""
function take_agent_events!(queue::AgentEventQueue)
    lock(queue.lock) do
        events = queue.events
        queue.events = Any[]
        events
    end
end
