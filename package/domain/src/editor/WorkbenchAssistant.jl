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
import ..ProjectionApiModule: projection_read, projection_print
import ..ReactiveModule: Cell
import ..TextModule: TextText, TextString
import ..PrimitiveModule: PrimitiveString
import ..CollectionModule: CellVector
import ..JuliaModule: JuliaDocument
import ..JsonModule: JsonDocument
import ..XmlModule: XmlDocument
import ..SequentialProjectionModule: SequentialProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..JuliaToSyntaxModule: JuliaToSyntax
import ..JsonToSyntaxModule: JsonToSyntax
import ..XmlToSyntaxModule: XmlToSyntax
import ..SyntaxToTextModule: SyntaxToText
import ..JuliaParserModule: juliaparse
import ..JsonParserModule: jsonparse
import ..XmlParserModule: xmlparse
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart,
                              ConversationThinking, thinking_part
import ..EvaluatorModule: EvaluatorForm, result_text, eval_kind_label
import ..JuliaModule: JuliaDocument, JuliaIdentifier
import ..WorkbenchModule: WorkbenchAssistant
import ..WorkbenchToWidgetModule: WorkbenchAssistantToWidgetSplitPane
import ..KeyboardModule: KeyDown
import ..ToolRegistryModule: list_tools, list_resources, call_tool, read_resource,
                              anthropic_tool_schema, Tool
import ..KeyboardModule: KeyPress
import ..EventCaseModule: var"@event_case"
import ..PrimitiveModule: StringReplaceRangeOperation
import ..LlmModule: LlmBackend, stream_turn, FakeLlm, AnthropicLlm
import ..McpModule: execute_julia_code, last_eval_value, register_default_tools_and_resources!
import ..DocumentModule: Document
import ..ConversationModule: ConversationDraft
import ..ConversationEditorModule: composer_read, ComposerSubmitOperation,
                                    finalize_draft!, reset_draft!, SUBMIT_HANDLER
import ..JsonModule: JsonDocument, JsonNull, JsonBool, JsonNumber, JsonString,
                     JsonArray, JsonObject
import ..JsonParserModule: jsonparse

using Markdown

# Convert a parsed JsonDocument into native Julia values (so LLM tool-call argument
# JSON can be parsed with the project's own parser instead of JSON3, keeping this
# module dependency-free).
_json_native(::JsonNull)   = nothing
_json_native(j::JsonBool)   = j.value
_json_native(j::JsonNumber) = j.value
_json_native(j::JsonString) = String(j.value)
_json_native(j::JsonArray)  = Any[_json_native(e) for e in j.elements]
# Iterate the `entries` collection field directly: JsonObject no longer forwards
# `length` (collection-fold), which the Dict constructor needs to presize the
# generator, so building the Dict straight off `j` throws.
_json_native(j::JsonObject) = Dict{String,Any}(e.key => _json_native(e.value) for e in j.entries)

export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, conversation_to_string, write_conversation, assistant_tool_schemas, dispatch_assistant_tool,
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

# ── Domain document → source text, via its print chain ─────────────────────────
# Serialize a structured document by projecting it through `…→syntax→text` and
# flattening the resulting (possibly nested) TextText — the same rendering the
# editor shows, so the LLM sees exactly the displayed source. Built once.

const _JULIA_TO_TEXT = SequentialProjection(RecursiveProjection(JuliaToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _JSON_TO_TEXT  = SequentialProjection(RecursiveProjection(JsonToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _XML_TO_TEXT   = SequentialProjection(RecursiveProjection(XmlToSyntax()),
                                            RecursiveProjection(SyntaxToText()))

_flatten_text!(io, s::TextString) = (c = s.content; c isa AbstractString && print(io, c); nothing)
_flatten_text!(io, t::TextText)   = (for e in t.elements; _flatten_text!(io, e); end; nothing)
_flatten_text!(io, _)             = nothing

function _via_chain(chain, doc)
    try
        io = IOBuffer()
        _flatten_text!(io, projection_print(chain, doc).output)
        String(take!(io))
    catch
        _content_to_string(doc)
    end
end

# Source text for a structured document (no fence).
_doc_source(c::JuliaDocument) = _via_chain(_JULIA_TO_TEXT, c)
_doc_source(c::JsonDocument)  = _via_chain(_JSON_TO_TEXT, c)
_doc_source(c::XmlDocument)   = _via_chain(_XML_TO_TEXT, c)
_doc_source(c)               = _content_to_string(c)

# One LLM text-block string for a part's content: prose as-is, a structured
# document fenced with its kind (```julia / ```json / ```xml).
_block_text(c::TextText)      = _content_to_string(c)
_block_text(c::JuliaDocument) = "```julia\n" * _doc_source(c) * "\n```"
_block_text(c::JsonDocument)  = "```json\n"  * _doc_source(c) * "\n```"
_block_text(c::XmlDocument)   = "```xml\n"   * _doc_source(c) * "\n```"
_block_text(c)               = _content_to_string(c)

# Part / turn helpers for the uniform turn/part model.
_part_content(p::ConversationPart) = p.content
_part_text(p::ConversationPart) = _content_to_string(p.content)
_eval_code(ef::EvaluatorForm)   = _doc_source(ef.form)
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
    # A Document return value (e.g. a live SimulationTaskDocument) is embedded as
    # the result so it renders live; anything else falls back to its text repr.
    val = last_eval_value()
    result = val isa Document ? val : result_text(output)
    push!(a.conversation.turns,
          ConversationTurn(:user, [ConversationPart(
              EvaluatorForm(_eval_form_doc(code);
                            result = result, is_error = is_error))]))

    _set_input!(a, "")
    nothing
end

# Flip to streaming and launch the agent loop on a task. `FakeLlm` synthesises
# events in-process (tests / offline); `AnthropicLlm` streams from Claude — the
# same `_handle_sse_event!` consumes both.
function _launch_agent_turn!(editor, a::WorkbenchAssistant)
    a.status = :streaming
    @async begin
        try
            _run_agent_loop!(editor, a)
        catch e
            a.status = :error
            err = sprint(showerror, e, catch_backtrace())
            @error "Assistant turn failed" exception = (e, catch_backtrace())
            push!(a.conversation.turns,
                  ConversationTurn(:assistant, [ConversationPart("Error: " * err)]))
        finally
            a.status === :streaming && (a.status = :idle)
        end
    end
    nothing
end

function evaluate_operation(editor, op::SubmitProseOperation)
    a = op.assistant
    text = _text_to_string(a.input)
    isempty(strip(text)) && return nothing

    push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart(text)]))
    _set_input!(a, "")
    _launch_agent_turn!(editor, a)
end

"""
    SubmitDraftTurnOperation(assistant)

Submit the composer's draft turn: finalize it (`finalize_draft!`), push it into
the conversation history, reset the draft in place, and launch a streaming turn.
This is what the panel emits when the composer's `ComposerSubmitOperation` fires
(ENTER on a text typein).
"""
struct SubmitDraftTurnOperation <: Operation
    assistant::WorkbenchAssistant
end

function evaluate_operation(editor, op::SubmitDraftTurnOperation)
    a = op.assistant
    draft = a.draft
    finalize_draft!(draft) || return nothing          # nothing to submit
    push!(a.conversation.turns, ConversationTurn(:user, collect(draft.parts)))
    reset_draft!(draft)
    _launch_agent_turn!(editor, a)
end

# Register the composer's submit hook so ENTER on the draft (anywhere it is
# rendered — incl. the nested workbench, where the panel reader isn't reached)
# becomes a SubmitDraftTurnOperation rather than a bare draft-normalize.
SUBMIT_HANDLER[] = a -> SubmitDraftTurnOperation(a)

# ═══════════════════════════════════════════════════════════════════════
# Code → JuliaDocument for an EvaluatorForm
# ═══════════════════════════════════════════════════════════════════════
# Parse the executed code into a real `JuliaDocument` so it renders as a
# syntax-highlighted Julia document in the conversation (its natural form), not a
# single opaque identifier. Fall back to the smallest projectable wrapper
# (`JuliaIdentifier`) if the snippet doesn't parse.

function _eval_form_doc(code::AbstractString)
    # Strip surrounding blank lines so the rendered form does not carry an empty
    # leading/trailing gutter line (common when the snippet is a triple-quoted
    # block). Execution still runs the original code; only the display is trimmed.
    src = strip(String(code))
    try
        juliaparse(src)
    catch
        JuliaIdentifier(src)
    end
end

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
                if c isa ConversationThinking
                    # User turns never legitimately contain thinking; drop it.
                    continue
                elseif c isa EvaluatorForm
                    text = "I ran the following Julia code:\n```julia\n" * _eval_code(c) *
                           "\n```\nResult:\n```\n" * _eval_result(c) * "\n```"
                    push!(content, Dict("type" => "text", "text" => text))
                else
                    push!(content, Dict("type" => "text", "text" => _block_text(c)))
                end
            end
            isempty(content) && push!(content, Dict("type" => "text", "text" => " "))
            push!(out, Dict("role" => "user", "content" => content))
            i += 1
        elseif t.role === :assistant
            # Coalesce consecutive assistant turns into one logical turn before
            # serialising: Anthropic merges consecutive same-role messages, and a
            # tool_use block must share its assistant message with the preceding
            # thinking/text. A later assistant turn that only carries the tool call
            # would otherwise emit a second assistant message (and 400 the API).
            parts = Any[]
            while i <= length(turns) && turns[i].role === :assistant
                append!(parts, collect(turns[i].parts))
                i += 1
            end
            _emit_assistant_turn!(out, parts)
        else
            i += 1
        end
    end
    out
end

# Serialize one :assistant turn — an ordered mix of thinking / text / eval parts —
# into the Anthropic wire shape. The tool-use protocol requires each tool call to
# sit in an assistant message whose immediately-following user message carries the
# `tool_result`, so a single turn becomes one or more
# `assistant(thinking+text+tool_use) → user(tool_result)` pairs, split at each run
# of eval parts, plus a trailing assistant message for any closing prose. Thinking
# blocks must lead each assistant message and keep their signature unchanged, or a
# tool-use continuation 400s.
function _emit_assistant_turn!(out, parts)
    thinking = Any[]
    text     = Any[]
    evals    = EvaluatorForm[]

    flush_segment! = function ()
        content = Any[]
        append!(content, thinking)    # thinking first
        append!(content, text)        # then text
        for ef in evals               # then tool_use blocks
            push!(content, Dict("type"  => "tool_use",
                                 "id"    => ef.tool_use_id,
                                 "name"  => "execute_julia_code",
                                 "input" => Dict("code" => _eval_code(ef))))
        end
        isempty(content) || push!(out, Dict("role" => "assistant", "content" => content))
        if !isempty(evals)
            results = Any[Dict("type"        => "tool_result",
                                "tool_use_id" => ef.tool_use_id,
                                "content"     => _eval_result(ef),
                                "is_error"    => ef.is_error) for ef in evals]
            push!(out, Dict("role" => "user", "content" => results))
        end
        empty!(thinking); empty!(text); empty!(evals)
    end

    prev_was_eval = false
    for part in parts
        c = part.content
        if c isa EvaluatorForm
            push!(evals, c)
            prev_was_eval = true
        else
            # Prose after a run of evals begins a new assistant message — close the
            # current (thinking+text+tool_use) → tool_result segment first.
            prev_was_eval && flush_segment!()
            if c isa ConversationThinking
                push!(thinking, _thinking_block(c))
            else
                push!(text, Dict("type" => "text", "text" => _block_text(c)))
            end
            prev_was_eval = false
        end
    end
    flush_segment!()
end

# One Anthropic content block for a thinking part. Redacted blocks carry an
# opaque `data` payload; normal blocks carry the reasoning text plus signature.
function _thinking_block(c::ConversationThinking)
    if c.redacted
        return Dict("type" => "redacted_thinking", "data" => c.data)
    end
    Dict("type"      => "thinking",
         "thinking"  => _content_to_string(c.text),
         "signature" => c.signature)
end

"""
    conversation_to_string(conversation) -> String

A plain, human-readable rendering of the whole conversation (for logging and as a
non-API fallback): each turn labelled by role, each part rendered with its kind
(prose, fenced code/JSON/XML, or an `EvaluatorForm` as `> code` / `= result`).
"""
function conversation_to_string(conversation::ConversationConversation)
    io = IOBuffer()
    for t in conversation.turns
        println(io, uppercasefirst(string(t.role)), ":")
        for part in t.parts
            c = part.content
            if c isa EvaluatorForm
                println(io, "> ", _eval_code(c))
                println(io, "= ", _eval_result(c))
            elseif c isa ConversationThinking
                println(io, "∴ ", c.redacted ? "[redacted thinking]" : _content_to_string(c.text))
            else
                println(io, _block_text(c))
            end
        end
        println(io)
    end
    String(take!(io))
end

"""
    write_conversation(assistant_or_conversation, path) -> path

Write the assistant's chat history to `path` as a readable transcript (the same
rendering as `conversation_to_string`: `Role:` headers, prose / fenced source
blocks, `> code` / `= result` for tool calls, `∴` for thinking). Accepts a
`WorkbenchAssistant` (uses its `.conversation`) or a `ConversationConversation`
directly. Returns `path`.
"""
write_conversation(a::WorkbenchAssistant, path::AbstractString) =
    write_conversation(a.conversation, path)

function write_conversation(conversation::ConversationConversation, path::AbstractString)
    write(path, conversation_to_string(conversation))
    path
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

# Extended-thinking request config for a model. Opus 4.x / Sonnet thinking
# models accept `{"type":"adaptive","display":"summarized"}`; `display:
# "summarized"` is what yields readable reasoning text (vs. the `"omitted"`
# default). Returns `nothing` for models where we don't enable thinking, so the
# `thinking` param is simply omitted from the request.
function _thinking_config(model::AbstractString)
    m = lowercase(String(model))
    if occursin("opus", m) || occursin("sonnet", m)
        return Dict("type" => "adaptive", "display" => "summarized")
    end
    nothing
end

# Resource reads (`list_resources` / `read_resource`) collapse by default —
# they are lookup chatter, secondary to the answer, like thinking. Evaluations
# (`execute_julia_code`) and other tool calls stay expanded. Keyed off
# `eval_kind_label` so the resource/eval/tool classification stays single-sourced.
_collapse_tool_default(tool_name::AbstractString) = eval_kind_label(tool_name) == "resource"

function _run_agent_loop!(editor, a::WorkbenchAssistant)
    # `AnthropicLlm.stream_turn` errors with a clear HTTP message if the
    # API key is empty. `FakeLlm` doesn't need one. So leave validation
    # to the backend.
    register_default_tools_and_resources!()
    tools = assistant_tool_schemas()
    # Resolve the backend and key now (not at construction): a `nothing` default
    # becomes AnthropicLlm when a key is available, else FakeLlm. Reading ENV here
    # — rather than baking it into the precompiled document — is what lets a key
    # exported before launch take effect. Write the resolution back so the live
    # document reflects the real backend/key (e.g. when inspecting `a.llm`).
    key = isempty(a.api_key) ? get(ENV, "ANTHROPIC_API_KEY", "") : a.api_key
    llm = a.llm === nothing ? (isempty(key) ? FakeLlm() : AnthropicLlm()) : a.llm
    a.llm === llm || (a.llm = llm)
    a.api_key == key || (a.api_key = key)
    turn_t0 = time()
    iter = 0
    # TEMPORARY: cap the agent loop so it can't run away during debugging.
    max_iters = 5
    @info "[assistant] turn start" llm=nameof(typeof(llm)) model=a.model tools=length(tools)

    # One assistant turn for the whole response. The SSE handler appends thinking/
    # text parts as deltas arrive, and each tool call appends an EvaluatorForm part
    # below — so the conversation stays strictly alternating user/assistant, with
    # this single turn holding every part in order. `build_messages` re-expands it
    # into the Anthropic tool_use/tool_result wire shape.
    turn = ConversationTurn(:assistant)
    push!(a.conversation.turns, turn)

    while true
        iter += 1
        if iter > max_iters
            @warn "[assistant] hit iteration cap; stopping turn" max_iters rounds=iter - 1
            break
        end

        # Prior turns plus this turn's parts so far (its trailing tool_results are
        # exactly the continuation prompt). An empty turn on round 1 serializes to
        # nothing, so no placeholder needs stripping.
        msgs = build_messages(a.conversation)

        # Live state for this round
        state = Dict{Symbol,Any}(
            :current_block    => nothing,         # text block being filled
            :current_thinking => nothing,         # thinking part being filled
            :current_tool     => nothing,         # _PendingToolUse being filled
            :tool_input_buf   => IOBuffer(),
            :pending_tools    => _PendingToolUse[],
            :stop_reason      => :end_turn,
        )

        @info "[assistant] round $iter: streaming" messages=length(msgs)
        stream_t0 = time()
        stream_turn(a.llm, a.api_key, a.model, a.system, msgs, tools;
                    on_event = ev -> _handle_sse_event!(ev, a, turn, state),
                    thinking = _thinking_config(a.model))
        @info "[assistant] round $iter: stream done" elapsed_s=round(time() - stream_t0; digits=2) stop=state[:stop_reason] parts=length(turn.parts) pending_tools=length(state[:pending_tools])

        turn.stop_reason = state[:stop_reason]

        pending = state[:pending_tools]::Vector{_PendingToolUse}
        if isempty(pending) || state[:stop_reason] !== :tool_use
            @info "[assistant] turn done" rounds=iter elapsed_s=round(time() - turn_t0; digits=2)
            break
        end

        # Dispatch each tool and append one EvaluatorForm *part* per call to the
        # single assistant turn. The code and result live together in one
        # EvaluatorForm and `tool_use_id` pairs the call with its API tool_use /
        # tool_result blocks when `build_messages` re-serialises the conversation.
        for tu in pending
            @info "[assistant] tool call" name=tu.name
            tool_t0 = time()
            output = try
                dispatch_assistant_tool(tu.name, tu.input, editor)
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            @info "[assistant] tool done" name=tu.name elapsed_s=round(time() - tool_t0; digits=2) out_chars=length(output)
            code = tu.input isa AbstractDict && haskey(tu.input, "code") ?
                       String(tu.input["code"]) : ""
            is_err = occursin("ERROR", output) || occursin("Error", output)
            # For execute_julia_code, a Document return value is embedded as the
            # live result (renders in place); other tools / non-Document values
            # keep the text repr. (Claude still sees the text tool_result, which
            # build_messages derives from this result.)
            val = tu.name == "execute_julia_code" ? last_eval_value() : nothing
            result = val isa Document ? val : result_text(output)
            push!(turn.parts, Cell(ConversationPart(
                EvaluatorForm(_eval_form_doc(code);
                              result = result,
                              is_error = is_err, tool_use_id = tu.id,
                              tool_name = tu.name);
                collapsed = _collapse_tool_default(tu.name))))
        end
    end

    # If the whole turn produced nothing (e.g. immediate stop / error before any
    # content), drop the empty placeholder so it doesn't render as a bare
    # "assistant:" line.
    if isempty(turn.parts)
        elems = getfield(a.conversation.turns, :elements)[]
        if !isempty(elems) && elems[end][] === turn
            deleteat!(a.conversation.turns, length(elems))
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
        elseif block_type == "thinking"
            # Collapsed by default — reasoning is verbose and secondary — unless the
            # assistant opts to keep thinking expanded (`collapse_thinking=false`).
            part = thinking_part(""; collapsed = a.collapse_thinking)
            push!(turn.parts, Cell(part))
            state[:current_thinking] = part
        elseif block_type == "redacted_thinking"
            # No deltas follow; the opaque `data` is all there is. Finalize now.
            part = thinking_part(""; redacted = true,
                                 data = String(get(block_data, :data, "")))
            push!(turn.parts, Cell(part))
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
        elseif dtype == "thinking_delta"
            _append_thinking_delta!(state[:current_thinking], String(get(delta, :thinking, "")))
        elseif dtype == "signature_delta"
            _set_thinking_signature!(state[:current_thinking], String(get(delta, :signature, "")))
        elseif dtype == "input_json_delta"
            print(state[:tool_input_buf], String(get(delta, :partial_json, "")))
        end
    elseif et === :content_block_stop
        ct = state[:current_tool]
        cb = state[:current_block]
        if ct isa _PendingToolUse
            raw = String(take!(state[:tool_input_buf]))
            parsed = try
                nv = _json_native(jsonparse(raw))
                nv isa Dict{String,Any} ? nv : Dict{String,Any}()
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
        # Thinking is plain prose — no markdown parse. Just close the block.
        state[:current_block] = nothing
        state[:current_thinking] = nothing
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

# Accumulate a thinking_delta into the thinking part's text (rebuild a
# single-span TextText with the accumulated reasoning, mirroring
# `_append_text_delta!`).
function _append_thinking_delta!(part::ConversationPart, s::AbstractString)
    c = part.content
    c isa ConversationThinking || return nothing
    current = _content_to_string(c.text)
    c.text = TextText(TextString(current * String(s)))
    nothing
end

_append_thinking_delta!(_, _) = nothing

# A signature_delta carries the opaque signature near the end of the block.
function _set_thinking_signature!(part::ConversationPart, s::AbstractString)
    c = part.content
    c isa ConversationThinking || return nothing
    c.signature = String(s)
    nothing
end

_set_thinking_signature!(_, _) = nothing

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
Recognises headings, fenced code (with `julia`/`json`/`xml` parsed into real
`JuliaDocument`/`JsonDocument`/`XmlElement` content), bulleted lists, and prose
paragraphs. A block whose language is unknown or that fails to parse falls back
to fenced text, so a malformed block never breaks the turn.
"""
# A fenced code block → a part whose content is the parsed domain document, with
# a graceful fallback to fenced text when the language is unknown or won't parse.
function _code_part(lang::AbstractString, body::AbstractString)
    parser = lang == "julia" ? juliaparse :
             lang == "json"  ? jsonparse  :
             lang == "xml"   ? xmlparse   : nothing
    if parser !== nothing
        doc = try
            parser(body)
        catch
            nothing
        end
        doc === nothing || return ConversationPart(doc)
    end
    ConversationPart("```" * lang * "\n" * body * "\n```")
end

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
            push!(out, _code_part(String(node.language), String(node.code)))
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

# Inline code span (`code`) — render the code text, not the `Markdown.Code(...)`
# constructor repr the generic fallback would produce.
_md_walk(io, x::Markdown.Code)    = print(io, '`', x.code, '`')
_md_walk(io, x::Markdown.LaTeX)   = print(io, x.formula)
_md_walk(io, ::Markdown.LineBreak) = print(io, '\n')

function _md_walk(io, x)
    # Generic fallback for Markdown inline nodes (Bold/Italic/Link carry `.text`).
    if hasproperty(x, :text)
        _md_walk(io, x.text)
    elseif hasproperty(x, :content)
        _md_walk(io, x.content)
    elseif hasproperty(x, :code)
        print(io, x.code)
    else
        print(io, string(x))
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Assistant input event handling
# ═══════════════════════════════════════════════════════════════════════
# The panel routes input key events to the composer on `assistant.draft` (the
# message being composed). `composer_read` maps the gesture to a composer
# operation on the draft turn; the panel intercepts the composer's
# `ComposerSubmitOperation` (ENTER on a text typein) and turns it into a
# `SubmitDraftTurnOperation`, which pushes the draft into the conversation and
# launches a streaming turn. The widget tree's default reader does not route key
# events to nested content, so we intercept here at the assistant layer.

# The draft is rendered through the composer in the panel's projection chain, so
# the composer's own reader already turns input keys into composer operations on
# the draft turn. The panel only needs to intercept the composer's
# `ComposerSubmitOperation` (ENTER on a text typein) — which merely normalizes the
# draft — and turn it into a `SubmitDraftTurnOperation` that pushes the draft into
# the conversation and launches a streaming turn.
function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op::ComposerSubmitOperation)
    iomap.input isa WorkbenchAssistant || return op
    SubmitDraftTurnOperation(iomap.input::WorkbenchAssistant)
end

# Fallback for when the composer chain declines a raw key (so it reaches the
# panel directly): route it to the draft, intercepting submit as above.
function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyPress)
    iomap.input isa WorkbenchAssistant || return nothing
    composer_read(iomap.input.draft, evt)
end

function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyDown)
    iomap.input isa WorkbenchAssistant || return nothing
    a = iomap.input::WorkbenchAssistant
    op = composer_read(a.draft, evt)
    op isa ComposerSubmitOperation ? SubmitDraftTurnOperation(a) : op
end

end # module
