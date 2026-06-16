"""
    WorkbenchAssistantModule

Operations, streaming orchestration, and message building for the
in-editor AI chat surface. Glue between `WorkbenchModule.WorkbenchAssistant`,
`ToolRegistryModule`, and `AnthropicModule`.

Submit flows:
- `SubmitProseOperation(assistant)`  — append a user message from `assistant.input`,
  clear the input, launch a streaming Claude turn on an `@async` task.
- `SubmitJuliaOperation(assistant)`  — parse `assistant.input` as Julia, run it
  via `ToolRegistry.call_tool("execute_julia_code", ...)`, append the input/result
  message pair, clear the input. No Claude call now; the next prose turn synthesizes
  the eval into the conversation history.

Internal helpers:
- `build_messages(conversation)`  — walk the conversation history and produce
  the JSON array Anthropic expects.
- `assistant_tool_schemas()`      — list_tools() schemas plus the two bridging
  tools `list_resources` and `read_resource`.
- `dispatch_assistant_tool(name, args, editor)` — calls registered tools and
  resolves the bridging tools to `ToolRegistry.list_resources` / `read_resource`.
- `parse_markdown_blocks(text)`   — chop a finished assistant text block into
  `ConversationBlock`s. Streaming-safe: invoked once per text block at
  `content_block_stop`.
"""
module WorkbenchAssistantModule

import ..OperationApiModule: Operation, evaluate_operation
import ..ProjectionApiModule: projection_read
import ..ReactiveModule: Cell
import ..TextModule: TextText, TextString
import ..PrimitiveModule: PrimitiveString
import ..CollectionModule: CellVector
import ..JuliaModule: JuliaDocument
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart
import ..EvaluatorModule: EvaluatorForm, result_text
import ..JuliaModule: JuliaDocument, JuliaIdentifier
import ..WorkbenchModule: WorkbenchAssistant
import ..WorkbenchToWidgetModule: WorkbenchAssistantToWidgetSplitPane
import ..KeyboardModule: KeyDown
import ..ToolRegistryModule: list_tools, list_resources, call_tool, read_resource,
                              anthropic_tool_schema, Tool
import ..KeyboardModule: KeyPress
import ..EventCaseModule: var"@event_case"
import ..PrimitiveModule: StringReplaceRangeOperation
import ..AnthropicModule: stream_message
import ..LlmModule: LlmBackend, stream_turn
import ..McpModule: execute_julia_code, register_default_tools_and_resources!

using Markdown
using JSON3

export SubmitProseOperation, SubmitJuliaOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, assistant_tool_schemas, dispatch_assistant_tool,
       parse_markdown_blocks

# ═══════════════════════════════════════════════════════════════════════
# Operations
# ═══════════════════════════════════════════════════════════════════════

"""
    SubmitProseOperation(assistant)

Snapshot `assistant.input` into a user message, clear the input,
flip `status` to `:streaming`, and launch an async Claude turn.
"""
struct SubmitProseOperation <: Operation
    assistant::WorkbenchAssistant
end

"""
    SubmitJuliaOperation(assistant)

Snapshot `assistant.input`, parse it as Julia, evaluate via the shared
`execute_julia_code` tool, and append the input/result message pair.
Synchronous (no network).
"""
struct SubmitJuliaOperation <: Operation
    assistant::WorkbenchAssistant
end

"""
    ClearInputOperation(assistant)

Empty `assistant.input`.
"""
struct ClearInputOperation <: Operation
    assistant::WorkbenchAssistant
end

"""
    ResetConversationOperation(assistant)

Drop all messages from `assistant.conversation` and clear the input.
"""
struct ResetConversationOperation <: Operation
    assistant::WorkbenchAssistant
end

# ═══════════════════════════════════════════════════════════════════════
# Helpers for input/output mutation
# ═══════════════════════════════════════════════════════════════════════

function _text_to_string(t::TextText)
    io = IOBuffer()
    for span in t.elements
        if hasproperty(span, :content)
            print(io, span.content)
        end
    end
    String(take!(io))
end

_text_to_string(s::PrimitiveString) = something(s.value, "")

# Stringify an arbitrary part content (text / Julia placeholder / etc).
_content_to_string(t::TextText) = _text_to_string(t)
_content_to_string(d) = hasproperty(d, :name) ? String(d.name) : string(d)

# Part / turn helpers for the uniform turn/part model.
_part_content(p::ConversationPart) = p.content
_part_text(p::ConversationPart) = _content_to_string(p.content)
_is_eval_part(p::ConversationPart) = p.content isa EvaluatorForm
_is_eval_turn(t::ConversationTurn) = any(_is_eval_part, t.parts)
function _first_eval(t::ConversationTurn)
    for p in t.parts
        p.content isa EvaluatorForm && return p.content
    end
    nothing
end
_eval_code(ef::EvaluatorForm)   = _content_to_string(ef.form)
_eval_result(ef::EvaluatorForm) = _content_to_string(ef.result)

function _set_input!(a::WorkbenchAssistant, s::AbstractString)
    a.input.value = String(s)
    n = length(s)
    a.input.selection = @reference value{n}
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# evaluate_operation
# ═══════════════════════════════════════════════════════════════════════

function evaluate_operation(editor, op::ClearInputOperation)
    _set_input!(op.assistant, "")
    nothing
end

function evaluate_operation(editor, op::ResetConversationOperation)
    op.assistant.conversation = ConversationConversation()
    _set_input!(op.assistant, "")
    nothing
end

function evaluate_operation(editor, op::SubmitJuliaOperation)
    a = op.assistant
    code = _text_to_string(a.input)
    isempty(strip(code)) && return nothing

    # Make sure the editor's exec tool is registered (no-op if already done).
    register_default_tools_and_resources!()
    output = try
        call_tool("execute_julia_code", Dict("code" => code), editor)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_error = occursin("ERROR", output) || occursin("Error", output)
    push!(a.conversation,
          ConversationTurn(:user, [ConversationPart(
              EvaluatorForm(JuliaIdentifier(code);
                            result = result_text(output), is_error = is_error))]))

    _set_input!(a, "")
    nothing
end

function evaluate_operation(editor, op::SubmitProseOperation)
    a = op.assistant
    text = _text_to_string(a.input)
    isempty(strip(text)) && return nothing

    push!(a.conversation, ConversationTurn(:user, [ConversationPart(text)]))
    _set_input!(a, "")
    a.status = :streaming

    # The agent loop dispatches through `a.llm::LlmBackend` — `FakeLlm`
    # synthesises events in-process for tests / offline use; `AnthropicLlm`
    # streams from Claude. The same `_handle_sse_event!` consumes both.
    @async begin
        try
            _run_agent_loop!(editor, a)
        catch e
            a.status = :error
            err = sprint(showerror, e, catch_backtrace())
            # Also dump to stderr so it's visible regardless of how the
            # in-editor scroll pane sizes the result message.
            @error "Assistant turn failed" exception = (e, catch_backtrace())
            # Surface the error in the conversation as an assistant prose turn
            # so the user sees what went wrong inline.
            push!(a.conversation,
                  ConversationTurn(:assistant, [ConversationPart("Error: " * err)]))
        finally
            a.status === :streaming && (a.status = :idle)
        end
    end
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Placeholder JuliaDocument
# ═══════════════════════════════════════════════════════════════════════
# v1 keeps the structural representation minimal — we wrap the code text in
# the smallest JuliaDocument that can still be projected. The Conversation
# code-block projection treats `body` polymorphically, so this is fine.

_placeholder_julia_doc(code::AbstractString) = JuliaIdentifier(String(code))

# ═══════════════════════════════════════════════════════════════════════
# Tool schemas exposed to Claude
# ═══════════════════════════════════════════════════════════════════════

"""
    assistant_tool_schemas()

Return the tool schemas to send to Claude:
- every registered tool from `ToolRegistry`, plus
- two bridging tools (`list_resources`, `read_resource`) that expose the
  registry's read-only resources through the Anthropic tool-use interface.
"""
function assistant_tool_schemas()
    schemas = anthropic_tool_schema(list_tools())
    push!(schemas, Dict(
        "name"         => "list_resources",
        "description"  => "List every read-only documentation resource registered in the editor. " *
                           "Returns a markdown bullet list of URIs and their one-line descriptions.",
        "input_schema" => Dict("type" => "object", "properties" => Dict{String,Any}(), "required" => String[]),
    ))
    push!(schemas, Dict(
        "name"         => "read_resource",
        "description"  => "Read the full body of a documentation resource by URI " *
                           "(URIs come from `list_resources`).",
        "input_schema" => Dict(
            "type" => "object",
            "properties" => Dict(
                "uri" => Dict("type" => "string",
                              "description" => "Resource URI from `list_resources`"),
            ),
            "required" => ["uri"],
        ),
    ))
    schemas
end

"""
    dispatch_assistant_tool(name, args, editor) -> String

Call a tool by name. Resolves the bridging `list_resources` / `read_resource`
tools to `ToolRegistry.list_resources()` / `ToolRegistry.read_resource(uri)`;
all other names go to `ToolRegistry.call_tool`.
"""
function dispatch_assistant_tool(name::AbstractString, args, editor)
    if name == "list_resources"
        io = IOBuffer()
        println(io, "# Resources")
        for r in list_resources()
            println(io, "- `", r.uri, "` — ", r.description)
        end
        return String(take!(io))
    elseif name == "read_resource"
        return read_resource(String(get(args, "uri", "")))
    else
        return call_tool(String(name), args, editor)
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Conversation → Anthropic messages
# ═══════════════════════════════════════════════════════════════════════

"""
    build_messages(conversation::ConversationConversation) -> Vector{Dict}

Walk the conversation and produce the JSON array Anthropic expects.

Code executions are all stored as `ConversationCodeExecution`, with the
originator carried on the `initiator` field:

  * `:user`      (ALT+ENTER) → serialised as a single `user` text turn
    ("I ran the following Julia code: …  Result: …"). Claude sees this
    as the human reporting an execution they did themselves.

  * `:assistant` (Claude calling `execute_julia_code`) → reassembled into
    the Anthropic tool-use protocol shape: appended to the preceding
    assistant message as a `tool_use` block (using `tool_use_id`), and
    followed by a `user` turn whose `tool_result` block carries the
    result. The id pairs the two so the API recognises the call.

Keep the `initiator` distinction load-bearing here: collapsing user calls
into the tool-use shape would tell Claude it had asked for a run it
never requested.
"""
function build_messages(conversation::ConversationConversation)
    out = Dict[]
    turns = collect(conversation.turns)
    i = 1
    while i <= length(turns)
        t = turns[i]
        if t.role === :user
            content = Any[]
            for part in t.parts
                c = part.content
                if c isa EvaluatorForm
                    text = "I ran the following Julia code:\n```julia\n" * _eval_code(c) *
                           "\n```\nResult:\n```\n" * _eval_result(c) * "\n```"
                    push!(content, Dict("type" => "text", "text" => text))
                else
                    push!(content, Dict("type" => "text", "text" => _part_text(part)))
                end
            end
            isempty(content) && push!(content, Dict("type" => "text", "text" => " "))
            push!(out, Dict("role" => "user", "content" => content))
            i += 1
        elseif t.role === :assistant && _is_eval_turn(t)
            # An assistant tool-call turn not preceded by an assistant text
            # turn — emit a standalone assistant tool_use + user tool_result
            # pair so the API contract still holds.
            ef = _first_eval(t)
            push!(out, Dict("role" => "assistant",
                            "content" => Any[Dict("type"  => "tool_use",
                                                   "id"    => ef.tool_use_id,
                                                   "name"  => "execute_julia_code",
                                                   "input" => Dict("code" => _eval_code(ef)))]))
            push!(out, Dict("role" => "user",
                            "content" => Any[Dict("type"        => "tool_result",
                                                   "tool_use_id" => ef.tool_use_id,
                                                   "content"     => _eval_result(ef),
                                                   "is_error"    => ef.is_error)]))
            i += 1
        elseif t.role === :assistant
            content = _assistant_content(t)
            # Look ahead: each consecutive :assistant eval turn belongs in this
            # assistant turn as a tool_use block, with all their results forming
            # the following user turn as tool_result blocks.
            j = i + 1
            while j <= length(turns) && turns[j].role === :assistant && _is_eval_turn(turns[j])
                ef = _first_eval(turns[j])
                push!(content, Dict("type"  => "tool_use",
                                     "id"    => ef.tool_use_id,
                                     "name"  => "execute_julia_code",
                                     "input" => Dict("code" => _eval_code(ef))))
                j += 1
            end
            isempty(content) && push!(content, Dict("type" => "text", "text" => " "))
            push!(out, Dict("role" => "assistant", "content" => content))
            if j > i + 1
                results = Any[]
                for k in (i + 1):(j - 1)
                    ef = _first_eval(turns[k])
                    push!(results, Dict("type"        => "tool_result",
                                         "tool_use_id" => ef.tool_use_id,
                                         "content"     => _eval_result(ef),
                                         "is_error"    => ef.is_error))
                end
                push!(out, Dict("role" => "user", "content" => results))
            end
            i = j
        else
            i += 1
        end
    end
    out
end

# Build the Anthropic content blocks for an assistant text turn (eval/tool_use
# parts are handled by `build_messages`'s lookahead, so they are skipped here).
function _assistant_content(t::ConversationTurn)
    content = Any[]
    for part in t.parts
        c = part.content
        c isa EvaluatorForm && continue
        if c isa JuliaDocument
            push!(content, Dict("type" => "text",
                                 "text" => "```julia\n" * _content_to_string(c) * "\n```"))
        else
            push!(content, Dict("type" => "text", "text" => _part_text(part)))
        end
    end
    content
end

# ═══════════════════════════════════════════════════════════════════════
# Streaming agent loop
# ═══════════════════════════════════════════════════════════════════════

# In-flight record of a streaming tool_use block. Lives only on the agent
# loop's state dict — once the stream's content_block_stop fires the
# `input` JSON is finalised, and once the tool actually runs we package
# everything into a `ConversationCodeExecution(:assistant, …)` pushed to
# the conversation.
mutable struct _PendingToolUse
    id::String
    name::String
    input::Any
end

function _run_agent_loop!(editor, a::WorkbenchAssistant)
    # `AnthropicLlm.stream_turn` errors with a clear HTTP message if the
    # API key is empty. `FakeLlm` doesn't need one. So leave validation
    # to the backend.
    register_default_tools_and_resources!()
    tools = assistant_tool_schemas()

    while true
        # Append a fresh assistant turn; the SSE handler fills its prose parts
        # as deltas arrive. Tool calls do NOT go into this turn — they end up as
        # separate :assistant eval turns (EvaluatorForm parts) after the tool runs.
        turn = ConversationTurn(:assistant)
        push!(a.conversation, turn)

        msgs = build_messages(a.conversation)
        # Drop the empty assistant turn we just appended from the outgoing
        # request — Anthropic only wants prior turns.
        !isempty(msgs) && msgs[end]["role"] == "assistant" && pop!(msgs)

        # Live state for this turn
        state = Dict{Symbol,Any}(
            :current_block    => nothing,         # text block being filled
            :current_tool     => nothing,         # _PendingToolUse being filled
            :tool_input_buf   => IOBuffer(),
            :pending_tools    => _PendingToolUse[],
            :stop_reason      => :end_turn,
        )

        stream_turn(a.llm, a.api_key, a.model, a.system, msgs, tools;
                    on_event = ev -> _handle_sse_event!(ev, a, turn, state))

        turn.stop_reason = state[:stop_reason]

        # If the turn produced no prose parts (e.g. Claude went straight to a
        # tool call), drop the placeholder so it doesn't render as an empty
        # "assistant:" line in front of the eval turn that carries its own
        # label. `build_messages` falls back to emitting the tool_use +
        # tool_result standalone in that case.
        if isempty(turn.parts)
            elems = getfield(a.conversation.turns, :elements)[]
            if !isempty(elems) && elems[end][] === turn
                deleteat!(a.conversation.turns, length(elems))
            end
        end

        pending = state[:pending_tools]::Vector{_PendingToolUse}
        if isempty(pending) || state[:stop_reason] !== :tool_use
            return
        end

        # Dispatch each tool and emit one :assistant eval turn per call. The
        # code and result live together in one EvaluatorForm and `tool_use_id`
        # pairs the call with its API tool_use block when `build_messages`
        # re-serialises the conversation for Claude.
        for tu in pending
            output = try
                dispatch_assistant_tool(tu.name, tu.input, editor)
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            code = tu.input isa AbstractDict && haskey(tu.input, "code") ?
                       String(tu.input["code"]) : ""
            is_err = occursin("ERROR", output) || occursin("Error", output)
            push!(a.conversation,
                  ConversationTurn(:assistant, [ConversationPart(
                      EvaluatorForm(JuliaIdentifier(code);
                                    result = result_text(output),
                                    is_error = is_err, tool_use_id = tu.id))]))
        end
    end
end

function _handle_sse_event!(ev, a, turn, state)
    et = ev.type
    data = ev.data
    if et === :content_block_start
        block_data = get(data, :content_block, nothing)
        block_data === nothing && return
        block_type = get(block_data, :type, "")
        if block_type == "text"
            part = ConversationPart(TextText(TextString("")))
            push!(turn.parts, Cell(part))
            state[:current_block] = part
        elseif block_type == "tool_use"
            state[:current_tool] = _PendingToolUse(
                String(get(block_data, :id, "")),
                String(get(block_data, :name, "")),
                Dict{String,Any}(),
            )
            state[:tool_input_buf] = IOBuffer()
        end
    elseif et === :content_block_delta
        delta = get(data, :delta, nothing)
        delta === nothing && return
        dtype = get(delta, :type, "")
        if dtype == "text_delta"
            _append_text_delta!(state[:current_block], String(get(delta, :text, "")))
        elseif dtype == "input_json_delta"
            print(state[:tool_input_buf], String(get(delta, :partial_json, "")))
        end
    elseif et === :content_block_stop
        ct = state[:current_tool]
        cb = state[:current_block]
        if ct isa _PendingToolUse
            raw = String(take!(state[:tool_input_buf]))
            parsed = try
                JSON3.read(raw, Dict{String,Any})
            catch
                Dict{String,Any}()
            end
            ct.input = parsed
            push!(state[:pending_tools], ct)
            state[:current_tool] = nothing
        elseif cb isa ConversationPart
            parts = parse_markdown_blocks(_part_text(cb))
            if !isempty(parts)
                # Replace the streamed scratch part with parsed parts.
                _replace_last_part!(turn, parts)
            end
        end
        state[:current_block] = nothing
    elseif et === :message_delta
        delta = get(data, :delta, nothing)
        if delta !== nothing
            sr = get(delta, :stop_reason, nothing)
            if sr !== nothing && !isnothing(sr)
                state[:stop_reason] = Symbol(sr)
            end
        end
    elseif et === :message_stop
        # nothing more to do
    elseif et === :error
        state[:stop_reason] = :error
    end
end

function _append_text_delta!(part::ConversationPart, s::AbstractString)
    # Append to the part's TextText content. Simplest reliable approach:
    # rebuild a single-span TextText with the accumulated content.
    current = _content_to_string(part.content)
    part.content = TextText(TextString(current * String(s)))
    nothing
end

_append_text_delta!(_, _) = nothing

function _replace_last_part!(turn::ConversationTurn, new_parts::Vector)
    # Drop the scratch part at the end, replace with new_parts.
    elems = getfield(turn.parts, :elements)[]
    !isempty(elems) && pop!(elems)
    for p in new_parts
        push!(elems, Cell(p))
    end
    getfield(turn.parts, :elements)[] = elems
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Markdown → structured blocks
# ═══════════════════════════════════════════════════════════════════════

"""
    parse_markdown_blocks(text::AbstractString) -> Vector{ConversationBlock}

Parse a completed assistant text-block body into structured blocks.
Recognises headings, fenced code (with `julia` getting a `JuliaIdentifier`
body), bulleted lists, and prose paragraphs.
"""
function parse_markdown_blocks(text::AbstractString)
    out = Any[]
    md = try
        Markdown.parse(text)
    catch
        return Any[ConversationPart(String(text))]
    end
    for node in md.content
        if node isa Markdown.Header
            level = _header_level(node)
            push!(out, ConversationPart(repeat("#", level) * " " * _md_to_plain(node.text)))
        elseif node isa Markdown.Code
            lang = String(node.language)
            body = String(node.code)
            if lang == "julia"
                push!(out, ConversationPart(JuliaIdentifier(body)))
            else
                push!(out, ConversationPart("```" * lang * "\n" * body * "\n```"))
            end
        elseif node isa Markdown.List
            io = IOBuffer()
            for it in node.items
                println(io, "- ", _md_to_plain(it))
            end
            push!(out, ConversationPart(String(take!(io))))
        elseif node isa Markdown.Paragraph
            push!(out, ConversationPart(_md_to_plain(node.content)))
        else
            push!(out, ConversationPart(_md_to_plain(node)))
        end
    end
    isempty(out) && push!(out, ConversationPart(String(text)))
    out
end

_header_level(::Markdown.Header{L}) where {L} = L::Int

function _md_to_plain(x)
    io = IOBuffer()
    _md_walk(io, x)
    String(take!(io))
end

function _md_walk(io, x::AbstractString)
    print(io, x)
end

function _md_walk(io, x::AbstractVector)
    for el in x
        _md_walk(io, el)
    end
end

function _md_walk(io, x)
    # Generic fallback for Markdown inline nodes
    if hasproperty(x, :text)
        _md_walk(io, x.text)
    elseif hasproperty(x, :content)
        _md_walk(io, x.content)
    else
        print(io, string(x))
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Assistant input event handling
# ═══════════════════════════════════════════════════════════════════════
# Additional methods on the existing `WorkbenchAssistantToWidgetSplitPane`
# projection_read so the editor's read! loop dispatches:
#
#   Enter      → SubmitProseOperation
#   Alt+Enter  → SubmitJuliaOperation
#   KeyPress   → insert character into `assistant.input`
#   Backspace  → delete char before cursor in `assistant.input`
#   Delete     → delete char after cursor in `assistant.input`
#
# We translate KeyPress / Backspace / Delete directly into
# `StringReplaceRangeOperation`s with paths rooted at the WorkbenchAssistant
# (i.e. `.input.value[range]`) — the widget tree's default projection_read
# does not route key events to nested document content, so we intercept
# at the assistant layer. Cursor movement (arrow keys, home, end) is not
# handled here yet; for the MVP, typing + backspace + Enter is sufficient.

# Pull the current `.value[range]` cursor out of the assistant's input.
function _input_range(a::WorkbenchAssistant)
    @reference_case a.input.selection begin
        value{s:e} => RangeReference(s, e)
    end
end

# Build a path rooted at WorkbenchAssistant: `.input.value[range]`.
_input_path(range::RangeReference) = @reference input.value.^(range)

function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyPress)
    iomap.input isa WorkbenchAssistant || return nothing
    evt.modifiers.ctrl && return nothing
    a = iomap.input::WorkbenchAssistant
    range = _input_range(a)
    range === nothing && return nothing
    StringReplaceRangeOperation(_input_path(range), evt.text)
end

function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyDown)
    iomap.input isa WorkbenchAssistant || return nothing
    a = iomap.input::WorkbenchAssistant

    submit = @event_case evt begin
        KeyDown(:return; alt) => SubmitJuliaOperation(a)
        KeyDown(:return)      => SubmitProseOperation(a)
    end
    submit === nothing || return submit

    range = _input_range(a)
    range === nothing && return nothing
    text = something(a.input.value, "")
    n = length(text)
    new_range = @event_case evt begin
        KeyDown(:backspace) => begin
            if range.start != range.stop
                range
            elseif range.start > 0
                RangeReference(range.start - 1, range.start)
            else
                return nothing
            end
        end
        KeyDown(:delete) => begin
            if range.start != range.stop
                range
            elseif range.stop < n
                RangeReference(range.stop, range.stop + 1)
            else
                return nothing
            end
        end
    end
    new_range === nothing && return nothing
    StringReplaceRangeOperation(_input_path(new_range), "")
end

end # module
