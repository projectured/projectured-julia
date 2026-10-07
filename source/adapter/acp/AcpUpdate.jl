# Fragment of `AcpModule` — from a `session/update` of the agent to the events of
# the kernel.
#
# ACP sends the text of an answer as chunks with no frame around them, and the
# kernel's events frame a block with a start and a stop. So a turn keeps the
# kind of the block that is open, and a chunk of another kind, another message
# or a new tool call closes it first. A turn's end closes the last one.

"""
    AcpTurn(on_event)

The state of one prompt of a session while it runs: the function that gets its
events, the block that is open, the message that the open block belongs to,
and the replies of the requests that wait for a person.
"""
mutable struct AcpTurn
    on_event::Function
    open_block::Symbol
    message_id::String
    waiting_replies::Vector{Function}
end

AcpTurn(on_event::Function) = AcpTurn(on_event, :none, "", Function[])

# The events of one `session/update`, in order. An update kind that the client
# does not show (`available_commands_update`, `usage_update`,
# `current_mode_update`, `config_option_update`, `session_info_update`,
# `user_message_chunk`), and a kind it does not know, answers no event.
function _translate_session_update!(turn::AcpTurn, update::Dict{String,Any})
    kind = get(update, "sessionUpdate", "")
    events = Any[]
    if kind == "agent_message_chunk"
        _append_chunk!(events, turn, :text, update)
    elseif kind == "agent_thought_chunk"
        _append_chunk!(events, turn, :thinking, update)
    elseif kind == "tool_call"
        _close_open_block!(events, turn)
        push!(events, _read_tool_call(update))
    elseif kind == "tool_call_update"
        push!(events, _read_tool_call(update))
    elseif kind == "plan"
        push!(events, AgentPlanUpdate(AgentPlanEntry[_read_plan_entry(entry)
                                                     for entry in get(update, "entries", Any[])
                                                     if entry isa Dict{String,Any}]))
    end
    events
end

function _append_chunk!(events::Vector{Any}, turn::AcpTurn, block::Symbol, update::Dict{String,Any})
    text = _read_content_text(get(update, "content", nothing))
    isempty(text) && return events
    message_id = string(something(get(update, "messageId", nothing), ""))
    if turn.open_block !== block ||
       (!isempty(message_id) && !isempty(turn.message_id) && message_id != turn.message_id)
        _close_open_block!(events, turn)
        push!(events, block === :text ? LlmTextStart() : LlmThinkingStart())
        turn.open_block = block
    end
    isempty(message_id) || (turn.message_id = message_id)
    push!(events, block === :text ? LlmTextDelta(text) : LlmThinkingDelta(text))
    events
end

function _close_open_block!(events::Vector{Any}, turn::AcpTurn)
    turn.open_block === :text && push!(events, LlmTextStop())
    turn.open_block === :thinking && push!(events, LlmThinkingStop())
    turn.open_block = :none
    turn.message_id = ""
    events
end

# A tool call and its update share one shape, and a field that the update leaves
# out stays `nothing`. An agent that has no `name` field for a tool can give it in
# `_meta.claudeCode.toolName`, as `claude-agent-acp` does.
function _read_tool_call(update::Dict{String,Any})
    name = _find_string(update, "name")
    if name === nothing
        meta = get(update, "_meta", nothing)
        claude = meta isa Dict{String,Any} ? get(meta, "claudeCode", nothing) : nothing
        name = claude isa Dict{String,Any} ? _find_string(claude, "toolName") : nothing
    end
    input = get(update, "rawInput", nothing)
    content = get(update, "content", nothing)
    raw_output = get(update, "rawOutput", nothing)
    output = content isa Vector{Any} && !isempty(content) ? _format_tool_content(content) :
             raw_output isa AbstractString ? String(raw_output) :
             raw_output === nothing ? nothing : JSON3.write(raw_output)
    AgentToolCallUpdate(string(get(update, "toolCallId", ""));
                        name, title = _find_string(update, "title"),
                        kind = _find_symbol(update, "kind"),
                        status = _find_symbol(update, "status"),
                        input = input isa Dict{String,Any} ? input : nothing,
                        output)
end

_read_plan_entry(entry::Dict{String,Any}) =
    AgentPlanEntry(string(get(entry, "content", "")),
                   something(_find_symbol(entry, "priority"), :medium),
                   something(_find_symbol(entry, "status"), :pending))

# The text of a tool's content: its text blocks as they are, a diff as the path
# and its lines marked `-` and `+`, and a terminal by its id.
function _format_tool_content(content::Vector{Any})
    pieces = String[]
    for item in content
        item isa Dict{String,Any} || continue
        kind = get(item, "type", "")
        if kind == "content"
            text = _read_content_text(get(item, "content", nothing))
            isempty(text) || push!(pieces, text)
        elseif kind == "diff"
            lines = String[string(get(item, "path", ""))]
            old_text = get(item, "oldText", nothing)
            old_text isa AbstractString && append!(lines, "-" .* split(old_text, '\n'))
            append!(lines, "+" .* split(string(get(item, "newText", "")), '\n'))
            push!(pieces, join(lines, '\n'))
        elseif kind == "terminal"
            push!(pieces, "[terminal " * string(get(item, "terminalId", "")) * "]")
        end
    end
    join(pieces, '\n')
end

# The text of one content block: the text of a text block, the text or the uri
# of a resource, the uri of a link, and a mark for an image or a sound.
function _read_content_text(block)
    block isa Dict{String,Any} || return ""
    kind = get(block, "type", "")
    kind == "text" && return string(get(block, "text", ""))
    kind == "resource_link" && return string(get(block, "uri", ""))
    if kind == "resource"
        resource = get(block, "resource", nothing)
        resource isa Dict{String,Any} || return ""
        return string(something(get(resource, "text", nothing), get(resource, "uri", "")))
    end
    kind in ("image", "audio") && return "[" * kind * "]"
    ""
end

function _find_string(object::Dict{String,Any}, key::String)
    value = get(object, key, nothing)
    value isa AbstractString ? String(value) : nothing
end

function _find_symbol(object::Dict{String,Any}, key::String)
    value = _find_string(object, key)
    value === nothing ? nothing : Symbol(value)
end
