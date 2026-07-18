"""
    WorkbenchAssistantModule

Operations, streaming orchestration, and message building for the
in-editor AI chat surface. Glue between `WorkbenchModule.WorkbenchAssistant`, the
editor's `ToolSet`, and the `LlmModule` provider seam.

Submit flows:
- `SubmitProseOperation(assistant)`  — append a user message from `assistant.input`,
  clear the input, launch a streaming Claude turn on an `@async` task.
- `SubmitJuliaOperation(assistant)`  — parse `assistant.input` as Julia, run it via
  the editor's `execute_julia_code` tool, append the input/result message pair,
  clear the input. No Claude call now; the next prose turn synthesizes the eval
  into the conversation history.

The tools come from `editor.tools` — the `ToolSet` that editor owns. Nothing here
holds a registry of its own, so two editors in one process never share tools or
evaluate code into each other's namespace.

Internal helpers:
- `build_messages(conversation)`  — walk the conversation history and produce
  the `LlmMessage`s the provider seam takes.
- `parse_markdown_blocks(text)`   — split a finished assistant text block into
  parts: top-level fenced code blocks become live domain documents, prose runs
  become real `MarkdownRoot` documents. Streaming-safe: invoked once per text
  block, when it closes.
"""
module WorkbenchAssistantModule

import ..OperationApiModule: Operation, evaluate_operation
import ..ProjectionApiModule: read_intent, print_document
import ..CellModule: Cell
import ..TextModule: TextBlock, TextString
import ..PrimitiveModule: PrimitiveString
import ..CollectionModule: CellVector
import ..JuliaModule: JuliaDocument
import ..JsonModule: JsonDocument
import ..XmlModule: XmlDocument
import ..YamlModule: YamlDocument
import ..MarkdownModule: MarkdownDocument
import ..ChainingProjectionModule: ChainingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..JuliaToSyntaxModule: JuliaToSyntax
import ..JsonToSyntaxModule: JsonToSyntax
import ..XmlToSyntaxModule: XmlToSyntax
import ..YamlToSyntaxModule: YamlToSyntax
import ..MarkdownToSyntaxModule: MarkdownToSyntax
import ..SyntaxToTextModule: SyntaxToText
import ..JuliaParserModule: juliaparse
import ..JsonParserModule: jsonparse
import ..XmlParserModule: xmlparse
import ..YamlParserModule: yamlparse
import ..MarkdownParserModule: markdownparse
import ..ReferenceModule: ConcreteReferencePath, FieldReferenceStep, RangeReferenceStep, EmptyReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart,
                              ConversationThinking, thinking_part
import ..EvaluatorModule: EvaluatorForm, result_text, eval_kind_label
import ..JuliaModule: JuliaDocument, JuliaIdentifier
import ..WorkbenchModule: WorkbenchAssistant
import ..WorkbenchToWidgetModule: WorkbenchAssistantToWidgetSplitPane
import ..EventModule: KeyDown
import ..ToolModule: Tool, ToolSet, list_tools, call_tool,
                      register_default_tools!, execute_julia_code, last_evaluated_value
import ..EventModule: KeyPress
import ..EventPatternModule: var"@event_case"
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..AgentModule: Agent, run_turn!, AgentToolResult
import ..LlmModule: Llm, stream_turn, LlmRequest, LlmMessage, LlmContent,
                     LlmText, LlmThinking, LlmRedactedThinking, LlmToolUse, LlmToolResult,
                     LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
                     LlmThinkingStart, LlmThinkingDelta, LlmThinkingSignature, LlmThinkingStop,
                     LlmRedactedThinkingBlock,
                     LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
                     LlmTurnEnd, LlmFailure
import ..DocumentApiModule: Document
import ..ConversationModule: ConversationDraft
import ..ConversationEditorModule: composer_read, ComposerSubmitOperation,
                                    finalize_draft!, reset_draft!, SUBMIT_HANDLER
import ..JsonModule: JsonDocument, JsonNull, JsonBool, JsonNumber, JsonString,
                     JsonArray, JsonObject
import ..JsonParserModule: jsonparse
import ..MarkdownModule: MarkdownText, MarkdownCode

# Convert a parsed JsonDocument into native Julia values (so LLM tool-call argument
# JSON can be parsed with the project's own parser instead of JSON3, keeping this
# module dependency-free).
_json_native(::JsonNull)   = nothing
_json_native(j::JsonBool)   = j.value
_json_native(j::JsonNumber) = j.value
_json_native(j::JsonString) = String(j.value)
_json_native(j::JsonArray)  = Any[_json_native(e) for e in j.elements]
# Iterate the `entries` collection field directly: JsonObject does not forward
# `length` (collection-fold), which the Dict constructor needs to presize the
# generator, so building the Dict straight off `j` throws.
_json_native(j::JsonObject) = Dict{String,Any}(e.key => _json_native(e.value) for e in j.entries)

export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, conversation_to_string, write_conversation,
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

function _text_to_string(t::TextBlock)
    io = IOBuffer()
    for span in t.elements
        if hasproperty(span, :content)
            print(io, span.content)
        end
    end
    String(take!(io))
end

_text_to_string(s::PrimitiveString) = something(s.value, "")

# Plain (marker-free) text of a parsed-Markdown content: concatenate its string
# leaves. `MarkdownText`/`MarkdownCode` carry a `content::String`; container nodes
# (root, paragraph, strong, …) forward the vector protocol over their children, so
# recurse through those; non-text leaves (thematic break, image, …) contribute
# nothing. Assistant prose is stored as a `MarkdownRoot`, so this reads back its text.
_markdown_plain(d::MarkdownText) = d.content
_markdown_plain(d::MarkdownCode) = d.content
function _markdown_plain(d::MarkdownDocument)
    applicable(length, d) || return ""
    io = IOBuffer()
    for i in 1:length(d)
        c = d[i]
        c isa MarkdownDocument && print(io, _markdown_plain(c))
    end
    String(take!(io))
end
_text_to_string(d::MarkdownDocument) = _markdown_plain(d)

# Stringify an arbitrary part content (text / Julia placeholder / etc).
_content_to_string(t::TextBlock) = _text_to_string(t)
_content_to_string(d::MarkdownDocument) = _markdown_plain(d)
_content_to_string(d) = hasproperty(d, :name) ? String(d.name) : string(d)

# ── Domain document → source text, via its print chain ─────────────────────────
# Serialize a structured document by projecting it through `…→syntax→text` and
# flattening the resulting (possibly nested) TextBlock — the same rendering the
# editor shows, so the LLM sees exactly the displayed source. Built once.

const _JULIA_TO_TEXT = ChainingProjection(RecursiveProjection(JuliaToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _JSON_TO_TEXT  = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _XML_TO_TEXT   = ChainingProjection(RecursiveProjection(XmlToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _YAML_TO_TEXT  = ChainingProjection(RecursiveProjection(YamlToSyntax()),
                                            RecursiveProjection(SyntaxToText()))
const _MARKDOWN_TO_TEXT = ChainingProjection(RecursiveProjection(MarkdownToSyntax()),
                                               RecursiveProjection(SyntaxToText()))

_flatten_text!(io, s::TextString) = (c = s.content; c isa AbstractString && print(io, c); nothing)
_flatten_text!(io, t::TextBlock)   = (for e in t.elements; _flatten_text!(io, e); end; nothing)
_flatten_text!(io, _)             = nothing

function _via_chain(chain, doc)
    try
        io = IOBuffer()
        _flatten_text!(io, print_document(chain, doc).output)
        String(take!(io))
    catch
        _content_to_string(doc)
    end
end

# Source text for a structured document (no fence).
_doc_source(c::JuliaDocument) = _via_chain(_JULIA_TO_TEXT, c)
_doc_source(c::JsonDocument)  = _via_chain(_JSON_TO_TEXT, c)
_doc_source(c::XmlDocument)   = _via_chain(_XML_TO_TEXT, c)
_doc_source(c::YamlDocument)  = _via_chain(_YAML_TO_TEXT, c)
_doc_source(c::MarkdownDocument) = _via_chain(_MARKDOWN_TO_TEXT, c)
_doc_source(c)               = _content_to_string(c)

# One LLM text-block string for a part's content: prose as-is, a structured
# document fenced with its kind (```julia / ```json / ```xml / ```yaml). A
# MarkdownDocument is prose the assistant wrote (or a ```markdown block), so it
# round-trips as its raw markdown *source* — unfenced — which is exactly the text
# Claude produced.
_block_text(c::TextBlock)      = _content_to_string(c)
_block_text(c::JuliaDocument) = "```julia\n" * _doc_source(c) * "\n```"
_block_text(c::JsonDocument)  = "```json\n"  * _doc_source(c) * "\n```"
_block_text(c::XmlDocument)   = "```xml\n"   * _doc_source(c) * "\n```"
_block_text(c::YamlDocument)  = "```yaml\n"  * _doc_source(c) * "\n```"
_block_text(c::MarkdownDocument) = _doc_source(c)
_block_text(c)               = _content_to_string(c)

# Part / turn helpers for the uniform turn/part model.
_part_content(p::ConversationPart) = p.content
_part_text(p::ConversationPart) = _content_to_string(p.content)
_eval_code(ef::EvaluatorForm)   = _doc_source(ef.form)
_eval_result(ef::EvaluatorForm) = _content_to_string(ef.result)

function _set_input!(a::WorkbenchAssistant, s::AbstractString)
    a.input.value = String(s)
    n = length(s)
    a.input.selection = @reference(a.input, value{n})
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

    # This editor's own tools; make sure the exec tool is registered (idempotent).
    set = editor.tools
    register_default_tools!(set)
    output = try
        call_tool(set, "execute_julia_code", Dict("code" => code), editor)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_error = occursin("ERROR", output) || occursin("Error", output)
    # A Document return value (e.g. a live SimulationTaskDocument) is embedded as
    # the result so it renders live; anything else falls back to its text repr.
    val = last_evaluated_value(set)
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
# same `_handle_llm_event!` consumes both, because both speak `LlmEvent`.
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
# The tools exposed to the model
# ═══════════════════════════════════════════════════════════════════════

# The tools the model may call are simply the editor's — `list_tools(editor.tools)`.
# There is nothing to render here: an `LlmRequest` carries `Tool`s, and the provider
# adapter turns them into its own schema (`tool_schema`).
#
# `list_resources` and `read_resource` used to be "bridging tools" this module
# hand-wrote provider schemas for, with a companion dispatcher that resolved them
# by name, because the registry exposed resources through an API no tool call could
# reach. They are ordinary registered tools now, so they arrive through `list_tools`
# like everything else and dispatch through `call_tool` like everything else.

# ═══════════════════════════════════════════════════════════════════════
# Conversation → LlmMessages
# ═══════════════════════════════════════════════════════════════════════

"""
    build_messages(conversation::ConversationConversation) -> Vector{Dict}

Walk the conversation and produce the `LlmMessage`s the provider seam takes.

Code executions are all stored as `ConversationCodeExecution`, with the
originator carried on the `initiator` field:

  * `:user`      (ALT+ENTER) → serialised as a single `user` text turn
    ("I ran the following Julia code: …  Result: …"). Claude sees this
    as the human reporting an execution they did themselves.

  * `:assistant` (Claude calling `execute_julia_code`) → reassembled into
    the tool-use shape: appended to the preceding
    assistant message as a `tool_use` block (using `tool_use_id`), and
    followed by a `user` turn whose `tool_result` block carries the
    result. The id pairs the two so the API recognises the call.

Keep the `initiator` distinction load-bearing here: collapsing user calls
into the tool-use shape would tell Claude it had asked for a run it
never requested.
"""
function build_messages(conversation::ConversationConversation)
    out = LlmMessage[]
    turns = collect(conversation.turns)
    i = 1
    while i <= length(turns)
        t = turns[i]
        if t.role === :user
            texts = String[]
            for part in t.parts
                c = part.content
                if c isa ConversationThinking
                    # User turns never legitimately contain thinking; drop it.
                    continue
                elseif c isa EvaluatorForm
                    push!(texts, "I ran the following Julia code:\n```julia\n" * _eval_code(c) *
                                 "\n```\nResult:\n```\n" * _eval_result(c) * "\n```")
                else
                    push!(texts, _block_text(c))
                end
            end
            # The turn's parts serialize into one text block, blank-line separated so
            # a heading / prose part never runs straight into the next fenced source
            # (adjacent API text blocks concatenate with no separator). An empty turn
            # still needs a non-empty block.
            merged = isempty(texts) ? " " : join(texts, "\n\n")
            push!(out, LlmMessage(:user, LlmContent[LlmText(merged)]))
            i += 1
        elseif t.role === :assistant
            # Coalesce consecutive assistant turns into one logical turn before
            # serialising: a provider merges consecutive same-role messages, and a
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
# into messages. The tool-use protocol requires each tool call to
# sit in an assistant message whose immediately-following user message carries the
# `tool_result`, so a single turn becomes one or more
# `assistant(thinking+text+tool_use) → user(tool_result)` pairs, split at each run
# of eval parts, plus a trailing assistant message for any closing prose. Thinking
# blocks must lead each assistant message and keep their signature unchanged, or a
# tool-use continuation 400s.
function _emit_assistant_turn!(out, parts)
    thinking = LlmContent[]
    text     = String[]
    evals    = EvaluatorForm[]

    flush_segment! = function ()
        content = LlmContent[]
        append!(content, thinking)    # thinking first
        # The segment's text parts join into ONE block, blank-line separated —
        # adjacent text blocks concatenate with no separator otherwise.
        isempty(text) || push!(content, LlmText(join(text, "\n\n")))
        for ef in evals               # then the tool calls
            # KNOWN GAP (pre-existing, held constant by this refactor): the call is
            # replayed as `execute_julia_code` with a `code` argument whatever tool
            # it actually was, so a `read_resource` call re-serialises with an empty
            # code string. Fixing it needs `EvaluatorForm` to keep the tool's raw
            # input, which is a behaviour change, not a move.
            push!(content, LlmToolUse(ef.tool_use_id, "execute_julia_code",
                                      Dict{String,Any}("code" => _eval_code(ef))))
        end
        isempty(content) || push!(out, LlmMessage(:assistant, content))
        if !isempty(evals)
            push!(out, LlmMessage(:user,
                LlmContent[LlmToolResult(ef.tool_use_id, _eval_result(ef), ef.is_error)
                           for ef in evals]))
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
                push!(text, _block_text(c))
            end
            prev_was_eval = false
        end
    end
    flush_segment!()
end

# One content block for a thinking part. Redacted blocks carry an opaque `data`
# payload; normal blocks carry the reasoning text plus the signature that must go
# back unchanged.
_thinking_block(c::ConversationThinking) =
    c.redacted ? LlmRedactedThinking(c.data) :
                 LlmThinking(_content_to_string(c.text), c.signature)

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

# Resource reads (`list_resources` / `read_resource`) collapse by default —
# they are lookup chatter, secondary to the answer, like thinking. Evaluations
# (`execute_julia_code`) and other tool calls stay expanded. Keyed off
# `eval_kind_label` so the resource/eval/tool classification stays single-sourced.
_collapse_tool_default(tool_name::AbstractString) = eval_kind_label(tool_name) == "resource"

# Reflection-based discovery of the real-network backend. `AnthropicLlm` lives
# entirely in the opt-in `ProjecturedLlm` package, which the core stack does not
# depend on — so we cannot name the type. If that package is loaded, construct one
# configured from the assistant's key and model; otherwise return `nothing` and the
# caller errors (production `main` never fabricates a fake backend).
#
# The backend is built per turn rather than cached on the document, because the key
# and the model are now the backend's own configuration: caching it would freeze
# whatever model was selected the first time, and editing `assistant.model` would
# stop taking effect.
function _discover_remote_llm(api_key::AbstractString, model::AbstractString)
    for m in values(Base.loaded_modules)
        nameof(m) === :ProjecturedLlm || continue
        isdefined(m, :AnthropicLlm) || continue
        return Base.invokelatest(getfield(m, :AnthropicLlm); api_key = api_key, model = model)
    end
    nothing
end

function _run_agent_loop!(editor, a::WorkbenchAssistant)
    # The real backend's `stream_turn` errors with a clear HTTP message if the
    # API key is empty, so leave key validation to the backend.
    set = editor.tools
    # Resolve the backend now (not at construction): with no explicit `llm`, build
    # the real-network one when a key is available *and* the opt-in `ProjecturedLlm`
    # package is loaded (found by reflection). Reading ENV here — rather than baking
    # it into the precompiled document — is what lets a key exported before launch
    # take effect. No fallback is fabricated: this is production code, so it never
    # conjures a fake backend. Tests/examples that want offline behaviour pass an
    # explicit `llm` (a `FakeLlm`/`ScriptedLlm` from `ProjecturedKernelExample`).
    key = isempty(a.api_key) ? get(ENV, "ANTHROPIC_API_KEY", "") : a.api_key
    llm = a.llm
    if llm === nothing
        llm = isempty(key) ? nothing : _discover_remote_llm(key, a.model)
        llm === nothing && error(
            "WorkbenchAssistant: no LLM backend available. Set ANTHROPIC_API_KEY " *
            "and load ProjecturedLlm for real Claude, or construct the assistant " *
            "with an explicit `llm` (e.g. a FakeLlm from ProjecturedKernelExample " *
            "in tests/examples).")
    end
    turn_t0 = time()
    @info "[assistant] turn start" llm=nameof(typeof(llm)) model=a.model

    # One assistant turn for the whole response. The event handler appends thinking/
    # text parts as deltas arrive, and each tool call appends an EvaluatorForm part
    # below — so the conversation stays strictly alternating user/assistant, with
    # this single turn holding every part in order. `build_messages` re-expands it
    # into the tool_use/tool_result message shape.
    turn = ConversationTurn(:assistant)
    push!(a.conversation.turns, turn)

    # The blocks currently being streamed into (one text part, one thinking part).
    state = Dict{Symbol,Any}(:current_block => nothing, :current_thinking => nothing)

    # The loop itself is the kernel's. What is left here is the two things that are
    # genuinely this domain's: how a conversation becomes messages, and how an event
    # becomes a part of it.
    #
    # `messages` is re-derived from the conversation at the start of every round —
    # the tool results the previous round appended to it are exactly the continuation
    # prompt — so the conversation stays the single source of truth rather than a
    # view of some message list held elsewhere.
    agent = Agent(llm, set; system = a.system, thinking = true)
    turn.stop_reason = run_turn!(agent, editor;
        messages = () -> build_messages(a.conversation),
        on_event = ev -> _handle_agent_event!(ev, a, turn, state, set))

    @info "[assistant] turn done" elapsed_s=round(time() - turn_t0; digits=2) parts=length(turn.parts)

    # If the whole turn produced nothing (e.g. an immediate stop, or an error before
    # any content), drop the empty placeholder so it doesn't render as a bare
    # "assistant:" line.
    if isempty(turn.parts)
        elems = getfield(a.conversation.turns, :elements)[]
        if !isempty(elems) && elems[end][] === turn
            deleteat!(a.conversation.turns, length(elems))
        end
    end
end

# A tool the model asked for has run. Its code and result live together in one
# `EvaluatorForm` part, and `tool_use_id` is what pairs the call with its
# tool_use/tool_result blocks when `build_messages` re-serialises the conversation.
function _handle_agent_event!(ev::AgentToolResult, a, turn, state, set)
    call = ev.call
    code = get(call.input, "code", "")
    # For `execute_julia_code`, a `Document` return value is embedded as the live
    # result and renders in place; other tools, and non-Document values, keep the
    # text repr. (The model still sees the textual tool_result, which
    # `build_messages` derives from this same result.)
    val = call.name == "execute_julia_code" ? last_evaluated_value(set) : nothing
    result = val isa Document ? val : result_text(ev.output)
    push!(turn.parts, Cell(ConversationPart(
        EvaluatorForm(_eval_form_doc(String(code));
                      result      = result,
                      is_error    = ev.is_error,
                      tool_use_id = call.id,
                      tool_name   = call.name);
        collapsed = _collapse_tool_default(call.name))))
    nothing
end

# Materialise one streamed `LlmEvent` into the conversation. Each block kind opens a
# part, fills it delta by delta, and closes it — so the panel renders the answer as
# it arrives rather than at the end.
#
# The tool-call events pass through unhandled: the loop collects and dispatches them,
# and what this module wants is the *result*, which arrives as an `AgentToolResult`.
function _handle_agent_event!(ev::LlmEvent, a, turn, state, set)
    if ev isa LlmTextStart
        part = ConversationPart(TextBlock(TextString("")))
        push!(turn.parts, Cell(part))
        state[:current_block] = part

    elseif ev isa LlmTextDelta
        _append_text_delta!(state[:current_block], ev.text)

    elseif ev isa LlmTextStop
        # A finished prose block is re-parsed: fenced code becomes live domain
        # documents, prose becomes a real Markdown document.
        cb = state[:current_block]
        if cb isa ConversationPart
            parts = parse_markdown_blocks(_part_text(cb))
            isempty(parts) || _replace_last_part!(turn, parts)
        end
        state[:current_block] = nothing

    elseif ev isa LlmThinkingStart
        # Collapsed by default — reasoning is verbose and secondary — unless the
        # assistant opts to keep thinking expanded (`collapse_thinking = false`).
        part = thinking_part(""; collapsed = a.collapse_thinking)
        push!(turn.parts, Cell(part))
        state[:current_thinking] = part

    elseif ev isa LlmThinkingDelta
        _append_thinking_delta!(state[:current_thinking], ev.text)

    elseif ev isa LlmThinkingSignature
        _set_thinking_signature!(state[:current_thinking], ev.signature)

    elseif ev isa LlmThinkingStop
        # Thinking is plain prose — no markdown parse. Just close the block.
        state[:current_thinking] = nothing

    elseif ev isa LlmRedactedThinkingBlock
        # Nothing streams; the opaque payload is all there is.
        push!(turn.parts, Cell(thinking_part(""; redacted = true, data = ev.data)))
    end
    nothing
end

function _append_text_delta!(part::ConversationPart, s::AbstractString)
    # Append to the part's TextBlock content. Simplest reliable approach:
    # rebuild a single-span TextBlock with the accumulated content.
    current = _content_to_string(part.content)
    part.content = TextBlock(TextString(current * String(s)))
    nothing
end

_append_text_delta!(_, _) = nothing

# Accumulate a thinking_delta into the thinking part's text (rebuild a
# single-span TextBlock with the accumulated reasoning, mirroring
# `_append_text_delta!`).
function _append_thinking_delta!(part::ConversationPart, s::AbstractString)
    c = part.content
    c isa ConversationThinking || return nothing
    current = _content_to_string(c.text)
    c.text = TextBlock(TextString(current * String(s)))
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
# Markdown → structured parts
# ═══════════════════════════════════════════════════════════════════════

# A fenced code block → a part whose content is the parsed domain document, with
# a graceful fallback to fenced text when the language is unknown or won't parse.
function _code_part(lang::AbstractString, body::AbstractString)
    parser = lang == "julia" ? juliaparse :
             lang == "json"  ? jsonparse  :
             lang == "xml"   ? xmlparse   :
             (lang == "yaml" || lang == "yml") ? yamlparse :
             (lang == "markdown" || lang == "md") ? markdownparse : nothing
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

# A run of prose → one real `MarkdownRoot` part, so headings / lists / **bold** /
# `code` / links become a genuine projectured Markdown document (rendered by the
# conversation's `MarkdownDocument` projection) instead of flat text. `markdownparse`
# is contractually total; the try/catch is belt-and-braces so a bug there can never
# break the turn — it degrades to a plain-text part.
function _prose_part(s::AbstractString)
    doc = try
        markdownparse(s)
    catch
        nothing
    end
    doc === nothing ? ConversationPart(String(s)) : ConversationPart(doc)
end

"""
    parse_markdown_blocks(text::AbstractString) -> Vector{ConversationPart}

Split a completed assistant text block into conversation parts. Top-level fenced
code blocks are peeled out at the source level so a ```julia / ```json / ```xml /
```yaml block becomes a live parsed `JuliaDocument` / `JsonDocument` /
`XmlElement` / `YamlDocument`; every run of prose between and around the fences
(headings, lists, **bold**, `code`, links, …) is parsed by the project's own
`markdownparse` into a real `MarkdownRoot`. So the assistant's markdown becomes a
genuine projectured document rather than flat text. A
fenced block whose language is unknown or that fails to parse falls back to fenced
text; a ```markdown block is parsed to `MarkdownRoot` like prose. Nothing here
throws — a malformed block never breaks the turn.
"""
function parse_markdown_blocks(text::AbstractString)
    out = Any[]
    lines = split(replace(String(text), "\r\n" => "\n", "\r" => "\n"), '\n')
    n = length(lines)
    prose = String[]
    # Flush the accumulated prose run as one MarkdownRoot part (blank runs drop).
    flush_prose! = function ()
        body = strip(join(prose, "\n"))
        empty!(prose)
        isempty(body) || push!(out, _prose_part(body))
    end
    i = 1
    while i <= n
        open = match(r"^[ \t]*```[ \t]*([^`]*)$", lines[i])
        if open !== nothing
            flush_prose!()
            lang = lowercase(strip(String(open.captures[1])))
            code = String[]
            i += 1
            while i <= n && match(r"^[ \t]*```[ \t]*$", lines[i]) === nothing
                push!(code, lines[i]); i += 1
            end
            i <= n && (i += 1)              # consume the closing fence
            push!(out, _code_part(lang, join(code, "\n")))
        else
            push!(prose, lines[i]); i += 1
        end
    end
    flush_prose!()
    # A wholly-blank block still yields one part so the turn is never partless.
    isempty(out) && push!(out, _prose_part(String(text)))
    out
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
function read_intent(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op::ComposerSubmitOperation)
    iomap.input isa WorkbenchAssistant || return op
    SubmitDraftTurnOperation(iomap.input::WorkbenchAssistant)
end

# Fallback for when the composer chain declines a raw key (so it reaches the
# panel directly): route it to the draft, intercepting submit as above.
function read_intent(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyPress)
    iomap.input isa WorkbenchAssistant || return nothing
    composer_read(iomap.input.draft, evt)
end

function read_intent(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, evt::KeyDown)
    iomap.input isa WorkbenchAssistant || return nothing
    a = iomap.input::WorkbenchAssistant
    op = composer_read(a.draft, evt)
    op isa ComposerSubmitOperation ? SubmitDraftTurnOperation(a) : op
end

end # module
