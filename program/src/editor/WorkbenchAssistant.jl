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
import ..ConversationModule: ConversationConversation,
                              ConversationUserMessage, ConversationAssistantMessage,
                              ConversationToolUseMessage, ConversationToolResultMessage,
                              ConversationJuliaInputMessage, ConversationJuliaResultMessage,
                              ConversationTextBlock, ConversationCodeBlock,
                              ConversationHeadingBlock, ConversationListBlock,
                              ConversationToolUseBlock
import ..WorkbenchModule: WorkbenchAssistant
import ..WorkbenchToWidgetModule: WorkbenchAssistantToWidgetScrollPane
import ..KeyboardModule: KeyDown
import ..ToolRegistryModule: list_tools, list_resources, call_tool, read_resource,
                              anthropic_tool_schema, Tool
import ..KeyboardModule: KeyPress
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

function _set_input!(a::WorkbenchAssistant, s::AbstractString)
    a.input.value = String(s)
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(length(s), length(s)),
                              EmptyReferencePath()))
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# evaluate_operation
# ═══════════════════════════════════════════════════════════════════════

function evaluate_operation(op::ClearInputOperation, _document)
    _set_input!(op.assistant, "")
    nothing
end

function evaluate_operation(op::ResetConversationOperation, _document)
    op.assistant.conversation = ConversationConversation()
    _set_input!(op.assistant, "")
    nothing
end

function evaluate_operation(op::SubmitJuliaOperation, _document)
    a = op.assistant
    code = _text_to_string(a.input)
    isempty(strip(code)) && return nothing

    # JuliaDocument is structural; for v1 we store the code as the JuliaIdentifier name
    # so the projection has something to render. The eval uses the raw text.
    julia_doc = _placeholder_julia_doc(code)
    push!(a.conversation, ConversationJuliaInputMessage(julia_doc))

    # Make sure the editor's exec tool is registered (no-op if already done).
    register_default_tools_and_resources!()
    output = try
        call_tool("execute_julia_code", Dict("code" => code), nothing)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_error = occursin("ERROR", output) || occursin("Error", output)
    push!(a.conversation,
          ConversationJuliaResultMessage(output; is_error = is_error))

    _set_input!(a, "")
    nothing
end

function evaluate_operation(op::SubmitProseOperation, _document)
    a = op.assistant
    text = _text_to_string(a.input)
    isempty(strip(text)) && return nothing

    push!(a.conversation, ConversationUserMessage(text))
    _set_input!(a, "")
    a.status = :streaming

    # The agent loop dispatches through `a.llm::LlmBackend` — `FakeLlm`
    # synthesises events in-process for tests / offline use; `AnthropicLlm`
    # streams from Claude. The same `_handle_sse_event!` consumes both.
    @async begin
        try
            _run_agent_loop!(a)
        catch e
            a.status = :error
            err = sprint(showerror, e, catch_backtrace())
            # Also dump to stderr so it's visible regardless of how the
            # in-editor scroll pane sizes the result message.
            @error "Assistant turn failed" exception = (e, catch_backtrace())
            push!(a.conversation,
                  ConversationToolResultMessage("error", err; is_error = true))
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

import ..JuliaModule: JuliaIdentifier

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
"""
function build_messages(conversation::ConversationConversation)
    out = Dict[]
    msgs = collect(conversation.messages)
    i = 1
    while i <= length(msgs)
        m = msgs[i]
        if m isa ConversationUserMessage
            push!(out, Dict(
                "role" => "user",
                "content" => Any[Dict("type" => "text",
                                      "text" => _text_to_string(m.text))],
            ))
        elseif m isa ConversationAssistantMessage
            push!(out, Dict(
                "role" => "assistant",
                "content" => _assistant_content(m),
            ))
        elseif m isa ConversationToolUseMessage
            # tool_use is folded into the preceding assistant message; if not
            # already folded, append as a standalone assistant tool_use.
            push!(out, Dict(
                "role" => "assistant",
                "content" => Any[Dict("type"  => "tool_use",
                                       "id"    => m.id,
                                       "name"  => m.name,
                                       "input" => m.input)],
            ))
        elseif m isa ConversationToolResultMessage
            push!(out, Dict(
                "role" => "user",
                "content" => Any[Dict("type"        => "tool_result",
                                       "tool_use_id" => m.tool_use_id,
                                       "content"     => _text_to_string(m.content),
                                       "is_error"    => m.is_error)],
            ))
        elseif m isa ConversationJuliaInputMessage
            # Pair with the following ConversationJuliaResultMessage if present.
            code = hasproperty(m.code, :name) ? m.code.name : string(m.code)
            output = ""
            if i + 1 <= length(msgs) && msgs[i + 1] isa ConversationJuliaResultMessage
                output = _text_to_string(msgs[i + 1].output)
                i += 1
            end
            text = "I ran the following Julia code:\n```julia\n" * code *
                   "\n```\nResult:\n```\n" * output * "\n```"
            push!(out, Dict("role" => "user",
                            "content" => Any[Dict("type" => "text", "text" => text)]))
        elseif m isa ConversationJuliaResultMessage
            # Stray result (shouldn't usually happen); fold as plain user note.
            text = "Julia result:\n```\n" * _text_to_string(m.output) * "\n```"
            push!(out, Dict("role" => "user",
                            "content" => Any[Dict("type" => "text", "text" => text)]))
        end
        i += 1
    end
    out
end

function _assistant_content(m::ConversationAssistantMessage)
    content = Any[]
    for b in m.blocks
        if b isa ConversationToolUseBlock
            push!(content, Dict("type"  => "tool_use",
                                 "id"    => b.id,
                                 "name"  => b.name,
                                 "input" => b.input))
        elseif b isa ConversationTextBlock
            push!(content, Dict("type" => "text",
                                 "text" => _text_to_string(b.text)))
        elseif b isa ConversationHeadingBlock
            push!(content, Dict("type" => "text",
                                 "text" => repeat("#", b.level) * " " * _text_to_string(b.text)))
        elseif b isa ConversationCodeBlock
            body = b.body isa TextText ? _text_to_string(b.body) :
                   (hasproperty(b.body, :name) ? b.body.name : string(b.body))
            push!(content, Dict("type" => "text",
                                 "text" => "```" * b.language * "\n" * body * "\n```"))
        elseif b isa ConversationListBlock
            io = IOBuffer()
            for item in b.items
                println(io, "- ", _text_to_string(item))
            end
            push!(content, Dict("type" => "text", "text" => String(take!(io))))
        end
    end
    isempty(content) && push!(content, Dict("type" => "text", "text" => ""))
    content
end

# ═══════════════════════════════════════════════════════════════════════
# Streaming agent loop
# ═══════════════════════════════════════════════════════════════════════

function _run_agent_loop!(a::WorkbenchAssistant)
    # `AnthropicLlm.stream_turn` errors with a clear HTTP message if the
    # API key is empty. `FakeLlm` doesn't need one. So leave validation
    # to the backend.
    register_default_tools_and_resources!()
    tools = assistant_tool_schemas()

    while true
        # Append a fresh assistant message for this turn; the SSE handler
        # fills its blocks as deltas arrive.
        assistant_msg = ConversationAssistantMessage()
        push!(a.conversation, assistant_msg)

        msgs = build_messages(a.conversation)
        # Drop the empty assistant message we just appended from the outgoing
        # request — Anthropic only wants prior turns.
        !isempty(msgs) && msgs[end]["role"] == "assistant" && pop!(msgs)

        # Live state for this turn
        state = Dict{Symbol,Any}(
            :current_block    => nothing,   # ConversationBlock being filled
            :current_index    => 0,         # index into `assistant_msg.blocks`
            :tool_input_buf   => IOBuffer(),
            :tool_use_blocks  => ConversationToolUseBlock[],
            :stop_reason      => :end_turn,
        )

        stream_turn(a.llm, a.api_key, a.model, a.system, msgs, tools;
                    on_event = ev -> _handle_sse_event!(ev, a, assistant_msg, state))

        assistant_msg.stop_reason = state[:stop_reason]

        # If Claude requested tool calls, run them, append tool_use + tool_result
        # messages, and loop. Otherwise stop.
        tool_blocks = state[:tool_use_blocks]::Vector{ConversationToolUseBlock}
        if isempty(tool_blocks) || state[:stop_reason] !== :tool_use
            return
        end

        for tu in tool_blocks
            push!(a.conversation,
                  ConversationToolUseMessage(tu.id, tu.name, tu.input;
                                             status = :running))
            output = try
                dispatch_assistant_tool(tu.name, tu.input, nothing)
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            push!(a.conversation,
                  ConversationToolResultMessage(tu.id, output))
        end
    end
end

function _handle_sse_event!(ev, a, assistant_msg, state)
    et = ev.type
    data = ev.data
    if et === :content_block_start
        block_data = get(data, :content_block, nothing)
        block_data === nothing && return
        block_type = get(block_data, :type, "")
        if block_type == "text"
            tb = ConversationTextBlock("")
            push!(assistant_msg.blocks, Cell(tb))
            state[:current_block] = tb
        elseif block_type == "tool_use"
            tb = ConversationToolUseBlock(
                String(get(block_data, :id, "")),
                String(get(block_data, :name, "")),
                Dict{String,Any}(),
            )
            push!(assistant_msg.blocks, Cell(tb))
            push!(state[:tool_use_blocks], tb)
            state[:current_block] = tb
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
        cb = state[:current_block]
        if cb isa ConversationToolUseBlock
            raw = String(take!(state[:tool_input_buf]))
            parsed = try
                JSON3.read(raw, Dict{String,Any})
            catch
                Dict{String,Any}()
            end
            cb.input = parsed
        elseif cb isa ConversationTextBlock
            blocks = parse_markdown_blocks(_text_to_string(cb.text))
            if !isempty(blocks)
                # Replace the streamed scratch block with parsed blocks.
                _replace_last_block!(assistant_msg, blocks)
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

function _append_text_delta!(block::ConversationTextBlock, s::AbstractString)
    # Append to the block's TextText. Simplest reliable approach: rebuild
    # a single-span TextText with the accumulated content.
    current = _text_to_string(block.text)
    block.text = TextText(TextString(current * String(s)))
    nothing
end

_append_text_delta!(_, _) = nothing

function _replace_last_block!(msg::ConversationAssistantMessage, new_blocks::Vector)
    # Drop the scratch block at the end, replace with new_blocks.
    elems = getfield(msg.blocks, :elements)[]
    !isempty(elems) && pop!(elems)
    for b in new_blocks
        push!(elems, Cell(b))
    end
    getfield(msg.blocks, :elements)[] = elems
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
        return Any[ConversationTextBlock(text)]
    end
    for node in md.content
        if node isa Markdown.Header
            level = _header_level(node)
            push!(out, ConversationHeadingBlock(level, _md_to_plain(node.text)))
        elseif node isa Markdown.Code
            lang = String(node.language)
            body = String(node.code)
            if lang == "julia"
                push!(out, ConversationCodeBlock(lang, JuliaIdentifier(body)))
            else
                push!(out, ConversationCodeBlock(lang, TextText(TextString(body))))
            end
        elseif node isa Markdown.List
            items = TextText[]
            for it in node.items
                push!(items, TextText(TextString(_md_to_plain(it))))
            end
            push!(out, ConversationListBlock(items))
        elseif node isa Markdown.Paragraph
            push!(out, ConversationTextBlock(_md_to_plain(node.content)))
        else
            push!(out, ConversationTextBlock(_md_to_plain(node)))
        end
    end
    isempty(out) && push!(out, ConversationTextBlock(text))
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
# Additional methods on the existing `WorkbenchAssistantToWidgetScrollPane`
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
    sel = a.input.selection
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference && h.name == "value" || return nothing
    rest = sel.tail
    rest isa ConcreteReferencePath || return nothing
    r = rest.head
    r isa RangeReference || return nothing
    r
end

# Build a path rooted at WorkbenchAssistant: `.input.value[range]`.
_input_path(range::RangeReference) =
    ConcreteReferencePath(FieldReference("input"),
        ConcreteReferencePath(FieldReference("value"),
            ConcreteReferencePath(range, EmptyReferencePath())))

function projection_read(::WorkbenchAssistantToWidgetScrollPane,
                          iomap, evt::KeyPress)
    iomap.input isa WorkbenchAssistant || return nothing
    evt.modifiers.ctrl && return nothing
    a = iomap.input::WorkbenchAssistant
    range = _input_range(a)
    range === nothing && return nothing
    StringReplaceRangeOperation(_input_path(range), evt.text)
end

function projection_read(::WorkbenchAssistantToWidgetScrollPane,
                          iomap, evt::KeyDown)
    iomap.input isa WorkbenchAssistant || return nothing
    a = iomap.input::WorkbenchAssistant

    if evt.key === :return
        return evt.modifiers.alt ? SubmitJuliaOperation(a) : SubmitProseOperation(a)
    end

    range = _input_range(a)
    range === nothing && return nothing
    text = something(a.input.value, "")
    n = length(text)
    new_range = if evt.key === :backspace
        if range.start != range.stop
            range
        elseif range.start > 0
            RangeReference(range.start - 1, range.start)
        else
            return nothing
        end
    elseif evt.key === :delete
        if range.start != range.stop
            range
        elseif range.stop < n
            RangeReference(range.stop, range.stop + 1)
        else
            return nothing
        end
    else
        return nothing
    end
    StringReplaceRangeOperation(_input_path(new_range), "")
end

end # module
