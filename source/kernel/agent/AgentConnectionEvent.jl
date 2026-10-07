# Fragment of `AgentModule` — the events an external agent reports in a turn,
# beside the text and the reasoning that arrive as `LlmEvent`s. A connection
# translates its protocol into these, so a caller never sees the protocol.

"""
    AgentToolCallUpdate(id; name, title, kind, status, input, output)

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
"""
struct AgentToolCallUpdate <: AgentEvent
    id::String
    name::Union{Nothing,String}
    title::Union{Nothing,String}
    kind::Union{Nothing,Symbol}
    status::Union{Nothing,Symbol}
    input::Union{Nothing,Dict{String,Any}}
    output::Union{Nothing,String}
end

AgentToolCallUpdate(id::AbstractString; name = nothing, title = nothing, kind = nothing,
                    status = nothing, input = nothing, output = nothing) =
    AgentToolCallUpdate(String(id), name, title, kind, status, input, output)

"""
    AgentPlanEntry(content, priority, status)

One step of the plan of an external agent. `priority` is `:high`, `:medium` or
`:low`, and `status` is `:pending`, `:in_progress` or `:completed`.
"""
struct AgentPlanEntry
    content::String
    priority::Symbol
    status::Symbol
end

"""
    AgentPlanUpdate(entries)

The whole plan of an external agent as it stands now. Each update replaces the
plan before it.
"""
struct AgentPlanUpdate <: AgentEvent
    entries::Vector{AgentPlanEntry}
end

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
