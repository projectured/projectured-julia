# Fragment of `AssistantModule`.
#
# Operations, streaming orchestration, and message building for the
# in-editor AI chat surface. Glue between `AssistantModule.Assistant`, the
# editor's `ToolSet`, and the `LlmModule` provider seam.
#
# Submit flows:
# - `SubmitProseOperation(assistant)`  — append a user message from `assistant.input`,
#   clear the input, launch a streaming Claude turn on an `@async` task.
# - `SubmitJuliaOperation(assistant)`  — parse `assistant.input` as Julia, run it via
#   the editor's `execute_julia_code` tool, append the input/result message pair,
#   clear the input. No Claude call now; the next prose turn synthesizes the eval
#   into the conversation history.
#
# The tools come from `editor.tools` — the `ToolSet` that editor owns. Nothing here
# holds a registry of its own, so two editors in one process never share tools or
# evaluate code into each other's namespace.
#
# Internal helpers:
# - `build_messages(conversation)`  — walk the conversation history and produce
#   the `LlmMessage`s the provider seam takes.
# - `parse_markdown_blocks(text)`   — split a finished assistant text block into
#   parts: top-level fenced code blocks become live domain documents, prose runs
#   become real `MarkdownRoot` documents. Streaming-safe: invoked once per text
#   block, when it closes.
# The assistant names no source domain. What it needs of one — parse this
# fenced block, render this document back to its own text — is the natural-format
# seam, which every domain registers itself with. A domain that is not loaded
# has no method there, and the fenced-text fallback below answers instead.
# Bare, to extend the composer's two generics by qualification below. That is
# `PAR-QUALIFIED-EXTENSION`.
using ..ConversationModule

# ═══════════════════════════════════════════════════════════════════════
# Operations
# ═══════════════════════════════════════════════════════════════════════

"""
    SubmitProseOperation(assistant)

Snapshot `assistant.input` into a user message, clear the input,
flip `status` to `:streaming`, and launch an async Claude turn. While a turn
streams it does nothing, and the input keeps its text.
"""
struct SubmitProseOperation <: Operation
    assistant::Assistant
end

"""
    SubmitJuliaOperation(assistant)

Snapshot `assistant.input`, parse it as Julia, evaluate via the shared
`execute_julia_code` tool, and append the input/result message pair.
Synchronous (no network).
"""
struct SubmitJuliaOperation <: Operation
    assistant::Assistant
end

"""
    ClearInputOperation(assistant)

Empty `assistant.input`.
"""
struct ClearInputOperation <: Operation
    assistant::Assistant
end

"""
    ResetConversationOperation(assistant)

Drop all messages from `assistant.conversation` and clear the input.
"""
struct ResetConversationOperation <: Operation
    assistant::Assistant
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
# Any other content — a document a part holds — answers with its own source
# text, through the seam. `_content_to_string` is where that decision lives.
_text_to_string(d) = _content_to_string(d)

# Stringify an arbitrary part content (text / a document / a placeholder).
# A document the seam can render answers with its own source text, which is what
# the editor shows and therefore what the model should see.
_content_to_string(t::TextBlock) = _text_to_string(t)
function _content_to_string(d)
    make_natural_projection(d, :string) === nothing || return _doc_source(d)
    hasproperty(d, :name) ? String(d.name) : string(d)
end

# ── Document → source text ──────────────────────────────────────────────────
# `print_natural_text` is the natural-format seam's own chain: the domain's
# `*ToSyntax`, then `SyntaxToText`, then `TextToString`. The assistant built five
# copies of it, one per domain, and naming five domains was the price.
#
# A document whose domain registered nothing — or which is not a document at all
# — falls back to the plain stringification above.
function _doc_source(c)
    make_natural_projection(c, :string) === nothing && return _content_to_string(c)
    try
        print_natural_text(c)
    catch
        hasproperty(c, :name) ? String(c.name) : string(c)
    end
end

# One LLM text-block string for a part's content: prose as-is, a structured
# document fenced with its kind (```julia / ```json / ```xml / ```yaml). Markdown
# is prose the assistant wrote (or a ```markdown block), so it round-trips as its
# raw markdown *source* — unfenced — which is exactly the text Claude produced.
#
# The fence names the document's own natural extension, so a domain says what it
# is called rather than this file listing them.
_block_text(c::TextBlock) = _content_to_string(c)
function _block_text(c)
    extension = get_natural_extension(c)
    extension === nothing && return _content_to_string(c)
    name = _fence_language(extension)
    name == "markdown" ? _doc_source(c) :
        "```" * name * "\n" * _doc_source(c) * "\n```"
end

# The fence language a natural extension is written as. The two that differ are
# the two whose extension is an abbreviation of the language's name.
_fence_language(extension::AbstractString) =
    let ext = lstrip(extension, '.')
        ext == "jl" ? "julia" : ext == "md" ? "markdown" : ext
    end

# The natural extension a fence language is written as — the inverse, for a block
# the model sent.
_fence_extension(language::AbstractString) =
    language == "julia" ? :jl :
    language == "markdown" ? :md :
    language == "yml" ? :yaml : Symbol(language)

# Part / turn helpers for the uniform turn/part model.
_part_content(p::ConversationPart) = p.content
_part_text(p::ConversationPart) = _content_to_string(p.content)
# The text the call was made with, as it arrived. Re-deriving it from `ef.form`
# put the display document into the model's history as source: an unparsable
# snippet came back as `PrimitiveString("…")`, a fenced one as `Core.@cmd "…"`,
# and a comment-only one as nothing at all. The model then copied what it was
# shown and called `PrimitiveString(…)`, which no scratch module resolves.
#
# A form kept without a source — one a person typed into the conversation, or one
# an older transcript holds — still answers from the document.
_eval_code(ef::EvaluatorForm) =
    isempty(ef.source) ? _doc_source(ef.form) : String(ef.source)
# The text the tool answered, as it arrived, for the same reason: a result drawn
# as a Markdown page prints back with the lines of each paragraph joined, so the
# model would read a tool result it was never given. A form kept without an
# output — a live value, one a person ran, one an older transcript holds — still
# answers from the result.
_eval_result(ef::EvaluatorForm) =
    isempty(ef.output) ? _content_to_string(ef.result) : String(ef.output)

# The call a form replays as. A form that kept its input replays the call as it
# was made — its own tool, its own arguments. A form that kept none — one a
# person typed, or one an older transcript holds — is an evaluation whose input
# is its code.
_replayed_call(ef::EvaluatorForm) =
    isempty(ef.input) ?
        LlmToolUse(ef.tool_use_id, "execute_julia_code",
                   Dict{String,Any}("code" => _eval_code(ef))) :
        LlmToolUse(ef.tool_use_id, ef.tool_name, Dict{String,Any}(ef.input))

function _set_input!(a::Assistant, s::AbstractString)
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
        execute_julia_code!(set, editor, code; describe_value = describe_value_for_person)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_error = occursin("ERROR", output) || occursin("Error", output)
    # A Document return value (e.g. a live SimulationTaskDocument) is embedded as
    # the result so it renders live; anything else falls back to its text repr.
    val = get_last_evaluated_value(set)
    result = val isa Document ? val : make_evaluator_result_text(output)
    push!(a.conversation.turns,
          ConversationTurn(:user, [ConversationPart(
              EvaluatorForm(_eval_form_doc(code);
                            source = code, result = result, is_error = is_error))]))

    _set_input!(a, "")
    nothing
end

# Flip to streaming and launch the agent loop on a task. `FakeLlm` synthesises
# events in-process (tests / offline); `AnthropicLlm` streams from Claude — the
# same `_handle_llm_event!` consumes both, because both speak `LlmEvent`.
#
# The turn runs on a task of its own, and the frame of a running editor reads
# and paints the assistant. So every write of the turn to the assistant goes
# through `run_on_editor_task!`: a status change and a streamed part are posted
# and applied in the drain of the next frame, which then paints them.
function _launch_agent_turn!(editor, a::Assistant)
    a.status = :streaming
    @async begin
        try
            a.backend === :acp ? _run_external_agent_turn!(editor, a) : _run_agent_loop!(editor, a)
        catch e
            traceback = catch_backtrace()
            err = sprint(showerror, e, traceback)
            # The turn is told to the person in the chat, and the fault is told
            # to the editor's log as well, so one place carries every failure.
            record_fault!(get_fault_store(editor), :tool; origin = :Assistant,
                          exception = e, traceback)
            @error "Assistant turn failed" exception = (e, traceback)
            run_on_editor_task!(editor; wait = false) do
                a.status = :error
                push!(a.conversation.turns,
                      ConversationTurn(:assistant, [ConversationPart("Error: " * err)]))
            end
        finally
            run_on_editor_task!(editor; wait = false) do
                a.status === :streaming && (a.status = :idle)
            end
        end
    end
    nothing
end

function evaluate_operation(editor, op::SubmitProseOperation)
    a = op.assistant
    # A turn that streams owns the end of the conversation, so the submit waits
    # for it to end and the input keeps its text.
    a.status === :streaming && return nothing
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
(ENTER on a text typein). While a turn streams it does nothing, and the draft
keeps its text.
"""
struct SubmitDraftTurnOperation <: Operation
    assistant::Assistant
end

function evaluate_operation(editor, op::SubmitDraftTurnOperation)
    a = op.assistant
    # A turn that streams owns the end of the conversation, so Return waits for
    # it to end and the draft keeps its text.
    a.status === :streaming && return nothing
    draft = a.draft
    finalize_draft!(draft) || return nothing          # nothing to submit
    push!(a.conversation.turns, ConversationTurn(:user, collect(draft.parts)))
    reset_draft!(draft)
    sync_draft_selection!(editor, draft)
    _launch_agent_turn!(editor, a)
end


"""
    EvaluateDraftTurnOperation(assistant)

ALT+ENTER on a draft that belongs to an assistant: evaluate the form, and put
the form and its result into the conversation as one whole, committing the draft
with them. A fresh empty cell takes the draft's place.

This is the notebook gesture. The evaluation itself is the composer's — this
adds the commit and the push, which is the part a composer alone cannot do,
because a conversation is not its to write to.

Prose typed before the form travels with it: the draft is finalized, so a cell
is a turn rather than only a form. And because the composer keeps a `Document`
return value as the result, a form that answers a document puts the live thing
in the transcript instead of a description of it.

No Claude call now. The next prose turn synthesises the evaluation into the
history, which is what `build_messages` already does with an `EvaluatorForm`.

While a turn streams it does nothing, and the draft keeps its text: a user turn
pushed into a streamed turn would come between a tool call and its result.
"""
struct EvaluateDraftTurnOperation <: Operation
    assistant::Assistant
end

# Both of these name the ASSISTANT they act on rather than a path into one, so
# there is nothing for a projection to re-root and nothing for one to place.
# They travel up the chain as they are, which is what lets ENTER and ALT+ENTER in
# a conversation embedded in a page reach the editor at all.
OperationModule.is_self_contained_operation(
    ::Union{SubmitDraftTurnOperation, EvaluateDraftTurnOperation}) = true

function evaluate_operation(editor, op::EvaluateDraftTurnOperation)
    a = op.assistant
    # As for Return: a turn that streams owns the end of the conversation.
    a.status === :streaming && return nothing
    draft = a.draft
    # The composer evaluates the active insertion in place, leaving an
    # `EvaluatorForm` — the form and its result as one part.
    evaluate_operation(editor, ComposerEvaluateOperation(draft))
    finalize_draft!(draft) || return nothing
    push!(a.conversation.turns, ConversationTurn(:user, collect(draft.parts)))
    reset_draft!(draft)
    sync_draft_selection!(editor, draft)
end

"""
What a draft's two owned gestures mean when the draft belongs to an `Assistant`.
ENTER submits the turn and ALT+ENTER evaluates it into one.

These are methods and not a registration. The composer loads first and cannot
name either operation, so it declares `make_submit_operation` and
`make_evaluate_operation` and this module answers for its own type. Two hosts
can therefore mean two different things at once, which a single mutable hook
could not: it held one answer for the whole process and the last writer won.

A method also survives precompilation. The pair this replaces were `Ref`s in the
composer's module, and writing another package's `Ref` while this one
precompiles writes into an image that is thrown away — at run time the fresh
image read `nothing` and both gestures fell back to what the composer alone can
do. That is why they had to be filled from the package's `__init__`, and why a
method needs no `__init__` at all.
"""
ConversationModule.make_submit_operation(assistant::Assistant) =
    SubmitDraftTurnOperation(assistant)

ConversationModule.make_evaluate_operation(assistant::Assistant) =
    EvaluateDraftTurnOperation(assistant)

# ═══════════════════════════════════════════════════════════════════════
# Code → a Julia document for an EvaluatorForm
# ═══════════════════════════════════════════════════════════════════════
# Parse the executed code through the natural-format seam so it renders as a
# syntax-highlighted Julia document in the conversation, which is its natural
# form. With no Julia domain loaded, or with a snippet that does not parse, the
# code is kept as a string: it still renders, and it still runs.

# The form of a call: an evaluation shows its code, parsed; any other tool shows
# its arguments, one line each.
_eval_form_doc(call::LlmToolUse) =
    call.name == "execute_julia_code" ?
        _eval_form_doc(String(get(call.input, "code", ""))) :
        make_evaluator_arguments_text(call.input)

function _eval_form_doc(code::AbstractString)
    # Strip surrounding blank lines so the rendered form does not carry an empty
    # leading/trailing gutter line (common when the snippet is a triple-quoted
    # block). Execution still runs the original code; only the display is trimmed.
    src = strip(String(code))
    has_natural_parser(:jl) || return PrimitiveString(src)
    try
        parse_natural_text(:jl, src)
    catch
        # The snippet does not parse. A string still renders and still runs.
        PrimitiveString(src)
    end
end

# ═══════════════════════════════════════════════════════════════════════
# The tools exposed to the model
# ═══════════════════════════════════════════════════════════════════════

# The tools the model may call are simply the editor's — `list_tools(editor.tools)`.
# There is nothing to render here: an `LlmRequest` carries `Tool`s, and the provider
# adapter turns them into its own schema (`render_tool_schema`).
#
# `list_resources` and `read_resource` are ordinary registered tools, so they
# arrive through `list_tools` and dispatch through `call_tool` like every other
# tool. Neither needs a provider schema written here or a dispatcher of its own.

# ═══════════════════════════════════════════════════════════════════════
# Conversation → LlmMessages
# ═══════════════════════════════════════════════════════════════════════

"""
    build_messages(conversation::ConversationConversation) -> Vector{Dict}

Walk the conversation and produce the `LlmMessage`s the provider seam takes.

A code execution is an `EvaluatorForm` part, and the role of the turn that
holds it says who ran it:

  * a `:user` turn      (ALT+ENTER) → serialised as a single `user` text turn
    ("I ran the following Julia code: …  Result: …"). Claude sees this
    as the human reporting an execution they did themselves.

  * an `:assistant` turn (Claude calling `execute_julia_code`) → reassembled into
    the tool-use shape: appended to the preceding
    assistant message as a `tool_use` block (using `tool_use_id`), and
    followed by a `user` turn whose `tool_result` block carries the
    result. The id pairs the two so the API recognises the call.

Keep the turn's role load-bearing here: collapsing a user call into the
tool-use shape would tell Claude it had asked for a run it never requested.

The walk starts at the first `:user` turn. A conversation may open with an
assistant turn nobody sent — a pane that greets the person on open writes one —
and a payload whose first message is an assistant message is rejected. A
conversation that holds no user turn is serialised whole: there is no first
message to protect.
"""
function build_messages(conversation::ConversationConversation)
    out = LlmMessage[]
    turns = collect(conversation.turns)
    # A payload cannot open with an assistant message. The provider wants the
    # first message to carry the `user` role and answers a leading assistant
    # message with a 400, so the walk starts at the first thing a person said. A
    # pane that greets the person on open puts an assistant turn in front of it,
    # and nothing is lost by dropping that turn: the model never wrote it.
    #
    # A conversation with no user turn is left whole. There is no first message
    # to protect, and this function is also how a turn is serialised on its own.
    first_user = findfirst(t -> t.role === :user, turns)
    i = first_user === nothing ? 1 : first_user
    while i <= length(turns)
        t = turns[i]
        if t.role === :user
            push!(out, LlmMessage(:user, LlmContent[LlmText(_make_user_turn_text(t))]))
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

# The text of one user turn: its parts in one block, blank-line separated so a
# heading or a prose part never runs straight into the next fenced source
# (adjacent text blocks of an API concatenate with no separator). An empty turn
# still needs a non-empty block. A user turn never legitimately holds thinking,
# so a thinking part is dropped.
function _make_user_turn_text(t::ConversationTurn)
    texts = String[]
    for part in t.parts
        c = part.content
        if c isa ConversationThinking
            continue
        elseif c isa EvaluatorForm
            push!(texts, "I ran the following Julia code:\n```julia\n" * _eval_code(c) *
                         "\n```\nResult:\n```\n" * _eval_result(c) * "\n```")
        else
            push!(texts, _block_text(c))
        end
    end
    isempty(texts) ? " " : join(texts, "\n\n")
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
            push!(content, _replayed_call(ef))
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
    format_conversation(conversation) -> String

A plain, human-readable rendering of the whole conversation (for logging and as a
non-API fallback): each turn labelled by role, each part rendered with its kind
(prose, fenced code/JSON/XML, or an `EvaluatorForm` as `> code` / `= result`).
"""
function format_conversation(conversation::ConversationConversation)
    io = IOBuffer()
    for t in conversation.turns
        println(io, uppercasefirst(string(t.role)), ":")
        for part in t.parts
            c = part.content
            if c isa EvaluatorForm
                c.tool_name == "execute_julia_code" || println(io, "# ", get_evaluation_title(c))
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
rendering as `format_conversation`: `Role:` headers, prose / fenced source
blocks, `> code` / `= result` for tool calls, `∴` for thinking). Accepts a
`Assistant` (uses its `.conversation`) or a `ConversationConversation`
directly. Returns `path`.
"""
write_conversation(a::Assistant, path::AbstractString) =
    write_conversation(a.conversation, path)

function write_conversation(conversation::ConversationConversation, path::AbstractString)
    write(path, format_conversation(conversation))
    path
end

# ═══════════════════════════════════════════════════════════════════════
# Streaming agent loop
# ═══════════════════════════════════════════════════════════════════════

# Resource reads (`list_resources` / `read_resource`) collapse by default —
# they are lookup chatter, secondary to the answer, like thinking. Evaluations
# (`execute_julia_code`) and other tool calls stay expanded. Keyed off
# `get_evaluation_kind_label` so the resource/eval/tool classification stays single-sourced.
_collapse_tool_default(tool_name::AbstractString) = get_evaluation_kind_label(tool_name) == "resource"

# Build the backend this assistant names. Every real backend lives in an opt-in
# package that the core stack does not depend on, so no type can be named here —
# `make_llm(:ollama; …)` is how one is asked for, and the method that answers it
# exists exactly while its package is loaded.
#
# The backend is built per turn rather than cached on the document, because the
# key and the model are the backend's own configuration: caching it would freeze
# whatever model was selected the first time, and editing `assistant.model` would
# stop taking effect. `invokelatest` because the package can be loaded after this
# code was compiled.
#
# An empty `model` means "the backend's own default", which is the only sound
# answer: a model name belongs to a provider, and a Claude id means nothing to a
# local server. A `context` of 0 means the same for the size of the window.
#
# The three keywords are what a caller can hold without knowing which provider
# will answer, and a backend uses the ones that apply to it.
function _build_llm(backend::Symbol, api_key::AbstractString, model::AbstractString,
                    context::Integer)
    Base.invokelatest(make_llm, backend;
                      api_key = api_key, model = model, context = context)
end

# The backends whose packages are loaded, for an error message. "none" is the
# honest answer when the person loaded no adapter at all: the fix then is to load
# one, not to name one.
function _backend_list()
    names = Base.invokelatest(get_llm_backend_names)
    isempty(names) && return "none (load ProjecturedAnthropic or ProjecturedOllama)"
    join(map(n -> ":" * String(n), names), ", ")
end

# `observe`, when given, sees every event of the turn before the conversation
# does: each `LlmEvent` as it streams, and each `AgentToolResult`. A measurement
# counts the rounds, the tool calls and the tokens there, and the conversation is
# not made to carry them.
function _run_agent_loop!(editor, a::Assistant; observe::Union{Nothing,Function} = nothing)
    set = editor.tools
    # Resolve the backend now, not at construction. Reading ENV here — rather than
    # baking it into the precompiled document — is what lets a key exported before
    # launch take effect. A backend's own `stream_turn` reports a missing or wrong
    # key with the provider's message, so no key is validated here.
    #
    # A LOCAL MODEL IS THE DEFAULT, and `:ollama` is what an assistant names
    # when nobody names another. A person who wants Claude says `:anthropic` and
    # exports a key. `:none` names no backend at all, and a submit then says so
    # rather than guessing one. Tests and examples that want offline behaviour
    # pass an explicit `llm` (a `FakeLlm`/`ScriptedLlm` from
    # `ProjecturedKernelExample`), and production never fabricates one.
    key = isempty(a.api_key) ? get(ENV, "ANTHROPIC_API_KEY", "") : a.api_key
    llm = a.llm
    if llm === nothing
        a.backend === :none && error(
            "Assistant: no LLM backend was named. Set `assistant.backend` to one " *
            "of " * _backend_list() * ", or construct the assistant with an " *
            "explicit `llm` (e.g. a FakeLlm from ProjecturedKernelExample in " *
            "tests/examples).")
        llm = _build_llm(a.backend, key, a.model, a.context)
    end
    # A backend that has a meaning model ranks the searches of this turn by the
    # meaning of a description. One that has none leaves the tool set as it is.
    Base.invokelatest(bind_meaning_model!, set, llm)
    turn_t0 = time()
    @info "[assistant] turn start" llm=nameof(typeof(llm)) backend=a.backend model=a.model

    # One assistant turn for the whole response. The event handler appends thinking/
    # text parts as deltas arrive, and each tool call appends an EvaluatorForm part
    # below — so the conversation stays strictly alternating user/assistant, with
    # this single turn holding every part in order. `build_messages` re-expands it
    # into the tool_use/tool_result message shape.
    turn = ConversationTurn(:assistant)
    run_on_editor_task!(() -> push!(a.conversation.turns, turn), editor; wait = false)

    # The blocks currently being streamed into (one text part, one thinking part).
    state = Dict{Symbol,Any}(:current_block => nothing, :current_thinking => nothing)

    # The loop itself is the kernel's. What is left here is the two things that are
    # genuinely this domain's: how a conversation becomes messages, and how an event
    # becomes a part of it.
    #
    # `messages` is re-derived from the conversation at the start of every round —
    # the tool results the previous round appended to it are exactly the continuation
    # prompt — so the conversation stays the single source of truth rather than a
    # view of some message list held elsewhere. It is read on the editor's task,
    # after every part this turn posted before it.
    #
    # An event changes the conversation, so its part is posted to the editor's
    # task and not waited for: a stream of many small parts is applied in few
    # frames. The posts of this task keep their order.
    agent = Agent(llm, set; system = a.system, thinking = true)
    stop_reason = run_turn!(agent, editor;
        messages = () -> run_on_editor_task!(() -> build_messages(a.conversation), editor),
        on_event = ev -> begin
            observe === nothing || observe(ev)
            run_on_editor_task!(editor; wait = false) do
                _handle_agent_event!(ev, a, turn, state, set)
            end
        end)

    @info "[assistant] turn done" elapsed_s=round(time() - turn_t0; digits=2)

    run_on_editor_task!(() -> _finish_turn!(a, turn, stop_reason), editor; wait = false)
    nothing
end

# A turn ends with its stop reason. A turn that produced nothing (an immediate
# stop, or an error before any content) is dropped, so it does not render as a
# bare "assistant:" line.
function _finish_turn!(a::Assistant, turn::ConversationTurn, stop_reason::Symbol)
    turn.stop_reason = stop_reason
    if isempty(turn.parts)
        elems = getfield(a.conversation.turns, :elements)[]
        if !isempty(elems) && elems[end][] === turn
            deleteat!(a.conversation.turns, length(elems))
        end
    end
    nothing
end

# The natural format of the media type a tool declares for its result, or
# `nothing` for a text that is only text.
_find_result_format(mime_type::AbstractString) = mime_type == "text/markdown" ? :md : nothing

# The document a tool's text becomes: a document of the format the tool declares,
# when the session can read that format, and else the text. An error is a stack
# trace and stays text, and so does a text the parser refuses.
function _make_tool_result_document(tool, output::AbstractString, is_error::Bool)
    format = tool === nothing || is_error ? nothing : _find_result_format(tool.result_mime_type)
    if format !== nothing && has_natural_parser(format)
        document = try
            parse_natural_text(format, output)
        catch
            nothing
        end
        document === nothing || return document
    end
    make_evaluator_result_text(output)
end

# A tool the model asked for has run. Its code and result live together in one
# `EvaluatorForm` part, and `tool_use_id` is what pairs the call with its
# tool_use/tool_result blocks when `build_messages` re-serialises the conversation.
function _handle_agent_event!(ev::AgentToolResult, a, turn, state, set)
    call = ev.call
    is_evaluation = call.name == "execute_julia_code"
    code = is_evaluation ? String(get(call.input, "code", "")) : ""
    # For `execute_julia_code`, a `Document` return value is embedded as the live
    # result and renders in place. Any other result is made from the text of the
    # tool, in the format the tool declares, and `output` keeps that text: it is
    # the tool_result `build_messages` sends the model in each later round.
    val = is_evaluation ? get_last_evaluated_value(set) : nothing
    is_live = val isa Document
    result = is_live ? val :
             _make_tool_result_document(find_tool(set, call.name), ev.output, ev.is_error)
    push!(turn.parts, Cell(ConversationPart(
        EvaluatorForm(_eval_form_doc(call);
                      source      = code,
                      result      = result,
                      output      = is_live ? "" : ev.output,
                      is_error    = ev.is_error,
                      tool_use_id = call.id,
                      tool_name   = call.name,
                      input       = call.input);
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
        part = make_conversation_thinking_part(""; collapsed = a.collapse_thinking)
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
        push!(turn.parts, Cell(make_conversation_thinking_part(""; redacted = true, data = ev.data)))
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
    kind = _fence_extension(lang)
    if has_natural_parser(kind)
        doc = try
            parse_natural_text(kind, body)
        catch
            nothing
        end
        doc === nothing || return ConversationPart(doc)
    end
    ConversationPart("```" * lang * "\n" * body * "\n```")
end

# A run of prose → one real markdown part, so headings / lists / **bold** /
# `code` / links become a genuine projectured document instead of flat text. It
# needs the markdown domain: with none loaded the seam has no method for `:md`
# and the prose stays a plain-text part, which is what it already degraded to
# when the parse failed.
function _prose_part(s::AbstractString)
    has_natural_parser(:md) || return ConversationPart(String(s))
    doc = try
        parse_natural_text(:md, s)
    catch
        nothing
    end
    doc === nothing ? ConversationPart(String(s)) : ConversationPart(doc)
end

"""
    parse_markdown_blocks(text::AbstractString) -> Vector{ConversationPart}

Split a completed assistant text block into conversation parts. Top-level fenced
code blocks are peeled out at the source level and handed to the natural-format
seam, so a ```julia / ```json / ```xml / ```yaml block becomes a live document of
that domain; every run of prose between and around the fences (headings, lists,
**bold**, `code`, links, …) goes the same way as markdown. So the assistant's
answer becomes a genuine projectured document rather than flat text.

**Each of those needs its domain loaded.** The seam answers for a language only
when the domain that owns it has registered a parser, and a language it cannot
place falls back to fenced text — the same fallback a block that fails to parse
already took. This module names no domain, so what an answer renders as is the
caller's choice of packages.

Nothing here throws: a malformed block never breaks the turn.
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
# A key reaches the draft (`assistant.draft`, the message being composed) the way
# any key reaches a document: the split pane routes it to the pane the assistant's
# selection names, and the composer's chain answers it there. The panel only
# intercepts the composer's `ComposerSubmitOperation` (ENTER on a text typein) —
# which merely normalizes the draft — and turns it into a
# `SubmitDraftTurnOperation`, which pushes the draft into the conversation and
# launches a streaming turn.
function read_intent(::AssistantToWidgetSplitPane,
                          iomap, op::ComposerSubmitOperation)
    iomap.input isa Assistant || return op
    SubmitDraftTurnOperation(iomap.input::Assistant)
end

# ── the card ────────────────────────────────────────────────────────────
#
# A key that nothing below took reaches the card's reader as the raw event. While
# the assistant's selection is in its draft, the card hands the key to the
# composer's own table, which answers the composer's keys (`Return`, `Tab`,
# `Escape`); the text keys reach the draft through the containers. A card that
# is selected as a whole takes no key.

_is_draft_selected(a::Assistant) =
    (path = a.selection; path isa ConcreteReference && path.head == FieldReferenceStep("draft"))

read_intent(::AssistantToWidgetCard, iomap, evt::KeyPress) =
    (a = iomap.input; a isa Assistant && _is_draft_selected(a) ?
        resolve_composer_host_operation(a, read_composer_gesture(a.draft, evt)) : nothing)

# Escape stops the turn of an external agent while it runs. The composer's own
# Escape, which reverts the draft, answers at any other time.
function read_intent(::AssistantToWidgetCard, iomap, evt::KeyDown)
    a = iomap.input
    a isa Assistant || return nothing
    evt.key === :escape && is_external_agent_turn_running(a) && return CancelAssistantTurnOperation(a)
    _is_draft_selected(a) ? resolve_composer_host_operation(a, read_composer_gesture(a.draft, evt)) : nothing
end

# An operation made below, said onward. `resolve_composer_host_operation` turns
# the two the assistant owns into its own. An operation that carries a path — the
# text layer's edit of the draft, say — takes the kernel's default reader, which
# maps the path back through this card's `map_reference_backward`. One that
# carries none passes as it is.
function read_intent(p::AssistantToWidgetCard, iomap, op::Operation)
    a = iomap.input
    a isa Assistant || return op
    resolved = resolve_composer_host_operation(a, op)
    resolved === op || return resolved
    mapped = invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, op)
    (mapped === nothing && OperationModule.operation_reference(op) === nothing) ? op : mapped
end
