# Fragment of `OllamaModule` — `OllamaLlm`, a model that runs on this machine through Ollama, as an `Llm`.

const _OLLAMA_URL    = "http://localhost:11434"
const _DEFAULT_MODEL = "qwen3.8:27b"
const _DEFAULT_MEANING_MODEL = "nomic-embed-text"

"""
    OllamaLlm(; model, base_url, max_tokens, context, thinking, temperature, seed,
                meaning_model)

A model that runs on this machine, served by Ollama. It carries its own
configuration, because that configuration is *this backend's identity* and not a
parameter of "have a conversation".

There is no API key: the server is local, and it asks for none. `base_url` is the
**server**, not one endpoint, because the adapter uses two of them — `/api/chat`
to run a turn and `/api/show` to ask what the model can do.

`context` is how many tokens of the conversation the model may see. `0`, the
default, sends nothing and leaves the size to the server — Ollama sizes it from
the model and its own configuration, and 0.33 gives 32768 unless
`OLLAMA_CONTEXT_LENGTH` says otherwise.

Set it to take control of two things at once. A **smaller** window costs less
memory, because the key-value cache grows with it and a large model's cache is
gigabytes; a **larger** one holds a longer conversation before the server drops
its oldest messages, which on a chat means the system prompt goes first.

`thinking` decides whether the turn may ask for reasoning:

- `nothing` (the default) asks the server. Ollama reports a `capabilities` list
  per model, and the answer is kept on this instance.
- `true` or `false` says so, and no question is asked.

The question matters. Ollama rejects the **whole request** with HTTP 400 when a
model that cannot reason is asked to, so a guess from the model's name — which is
what a hosted provider's adapter can afford — would kill the turn.

`meaning_model` is the model that computes meaning vectors for a search by
description, `nomic-embed-text` unless it is named. It is a second model on the
same server, asked through `/api/embed`, and an empty name means none. The
server answers with an error until the model is pulled, and the error says how
to pull it.
"""
struct OllamaLlm <: Llm
    model::String
    base_url::String
    max_tokens::Int
    context::Int
    thinking::Union{Nothing,Bool}
    # **What a repeatable run needs.** The server samples with its own defaults
    # unless these are said, so two runs of one question are two answers and a
    # test that compares them measures nothing. `nothing` sends neither and
    # leaves the server as it was.
    temperature::Union{Nothing,Float64}
    seed::Union{Nothing,Int}
    meaning_model::String
    # The answer of the capability question, kept per instance. Never a module
    # global: one process runs many editors, and each holds its own backend.
    thinking_answer::Ref{Union{Nothing,Bool}}
end

OllamaLlm(; model::AbstractString = _DEFAULT_MODEL,
            base_url::AbstractString = _OLLAMA_URL,
            max_tokens::Integer = 4096,
            context::Integer = 0,
            thinking::Union{Nothing,Bool} = nothing,
            temperature::Union{Nothing,Real} = nothing,
            seed::Union{Nothing,Integer} = nothing,
            meaning_model::AbstractString = _DEFAULT_MEANING_MODEL) =
    OllamaLlm(String(isempty(model) ? _DEFAULT_MODEL : model),
              String(rstrip(base_url, '/')),
              Int(max_tokens), Int(context), thinking,
              temperature === nothing ? nothing : Float64(temperature),
              seed === nothing ? nothing : Int(seed),
              String(meaning_model),
              Ref{Union{Nothing,Bool}}(nothing))

# This package's registration on the kernel's factory seam. `api_key` is accepted
# and ignored: it is one of the three keywords every backend takes, and a server on
# this machine asks for none.
make_llm(::Val{:ollama}; api_key::AbstractString = "", kwargs...) = OllamaLlm(; kwargs...)

get_default_llm_model(::Val{:ollama}) = _DEFAULT_MODEL

# ═══════════════════════════════════════════════════════════════════════
# Request → Ollama JSON
# ═══════════════════════════════════════════════════════════════════════

"""
    render_tool_schema(llm::OllamaLlm, tools) -> Vector{Dict}

Render `Tool`s into the shape Ollama's `tools` parameter takes: a function
wrapper around a JSON-Schema object. Anthropic's `input_schema` is the same
information in a different envelope, which is why each adapter renders it and a
`Tool` itself knows neither.
"""
function render_tool_schema(::OllamaLlm, tools::AbstractVector{Tool})
    out = Dict[]
    for t in tools
        properties = Dict{String,Any}()
        required   = String[]
        for p in t.parameters
            properties[String(p.name)] = Dict(
                "type"        => String(p.type),
                "description" => String(p.description),
            )
            get(p, :required, false) && push!(required, String(p.name))
        end
        push!(out, Dict(
            "type"     => "function",
            "function" => Dict("name"        => t.name,
                               "description" => t.description,
                               "parameters"  => Dict("type"       => "object",
                                                     "properties" => properties,
                                                     "required"   => required)),
        ))
    end
    out
end

# Render the conversation. Three of Ollama's rules shape this:
#
# - the system prompt is a message, not a field beside the messages;
# - a tool result is a message of its own, with role "tool";
# - that message names the tool, not the call. Our `LlmToolResult` carries the
#   call's id, so the walk keeps an id-to-name map as it passes each `LlmToolUse`,
#   and the result that follows looks its name up there.
function _wire_messages(request::LlmRequest)
    out   = Any[]
    names = Dict{String,String}()
    isempty(request.system) ||
        push!(out, Dict{String,Any}("role" => "system", "content" => request.system))
    for m in request.messages
        _wire_message!(out, names, m)
    end
    out
end

function _wire_message!(out, names::Dict{String,String}, m::LlmMessage)
    if m.role === :assistant
        text     = IOBuffer()
        thinking = IOBuffer()
        calls    = Any[]
        for c in m.content
            if c isa LlmText
                print(text, c.text)
            elseif c isa LlmThinking
                # The reasoning text goes back; the signature does not, because
                # Ollama issues none and expects none.
                print(thinking, c.text)
            elseif c isa LlmToolUse
                names[c.id] = c.name
                push!(calls, Dict("id"       => c.id,
                                  "function" => Dict("name"      => c.name,
                                                     "arguments" => c.input)))
            end
            # `LlmRedactedThinking` has no counterpart here and is dropped.
        end
        msg = Dict{String,Any}("role" => "assistant", "content" => String(take!(text)))
        t = String(take!(thinking))
        isempty(t)     || (msg["thinking"]   = t)
        isempty(calls) || (msg["tool_calls"] = calls)
        push!(out, msg)
    else
        texts = String[]
        for c in m.content
            if c isa LlmToolResult
                name = get(names, c.tool_use_id, "")
                if isempty(name)
                    # A result whose call was never seen. Quoting it in the user
                    # message is worse than a "tool" message, but it is never wrong:
                    # the model still reads what the tool said.
                    push!(texts, "Tool result:\n" * c.content)
                else
                    push!(out, Dict{String,Any}("role"      => "tool",
                                                "tool_name" => name,
                                                "content"   => c.content))
                end
            elseif c isa LlmText
                push!(texts, c.text)
            end
        end
        isempty(texts) ||
            push!(out, Dict{String,Any}("role"    => String(m.role),
                                        "content" => join(texts, "\n\n")))
    end
    nothing
end

# Does this model reason? `nothing` means nobody said, so ask the server once and
# keep the answer on this instance. A server that cannot be reached answers "no",
# which costs a turn its reasoning and never its life.
function _supports_thinking(llm::OllamaLlm)
    llm.thinking === nothing || return llm.thinking
    known = llm.thinking_answer[]
    known === nothing || return known
    answer = try
        r = HTTP.post(llm.base_url * "/api/show",
                      ["content-type" => "application/json"],
                      JSON3.write(Dict("model" => llm.model));
                      status_exception = false)
        r.status == 200 &&
            any(c -> String(c) == "thinking",
                get(JSON3.read(r.body), :capabilities, ()))
    catch
        false
    end
    llm.thinking_answer[] = answer
    answer
end

# ═══════════════════════════════════════════════════════════════════════
# Ollama NDJSON → LlmEvent
# ═══════════════════════════════════════════════════════════════════════

# A tool call's arguments arrive as a JSON object, already parsed by the server —
# unlike Anthropic, which streams them as fragments. Some servers send them as a
# string holding JSON instead, so both are read.
_native(v::JSON3.Object) = Dict{String,Any}(String(k) => _native(x) for (k, x) in pairs(v))
_native(v::JSON3.Array)  = Any[_native(x) for x in v]
_native(v)               = v

function _tool_input(raw)
    raw === nothing && return Dict{String,Any}()
    if raw isa AbstractString
        isempty(strip(raw)) && return Dict{String,Any}()
        parsed = try
            JSON3.read(raw)
        catch
            return Dict{String,Any}()
        end
        return parsed isa JSON3.Object ? _native(parsed) : Dict{String,Any}()
    end
    raw isa JSON3.Object ? _native(raw) : Dict{String,Any}()
end

"""
    _line_handler(on_event) -> Function

The stream reader, as a function of one line. It holds the state a turn needs —
which block is open, and whether any tool call arrived — and turns each parsed
line into events.

It is separate from the transport on purpose. The translation is what is worth
testing, and it is testable here with recorded lines and no server at all.
"""
function _line_handler(on_event::Function)
    # Which block is open, so the deltas that arrive with no framing become the
    # right typed start and stop; and whether any tool call arrived, which decides
    # the stop reason below.
    open_block = Ref(:none)
    saw_tool   = Ref(false)
    call_count = Ref(0)

    close_block! = function ()
        b = open_block[]
        b === :text     && on_event(LlmTextStop())
        b === :thinking && on_event(LlmThinkingStop())
        open_block[] = :none
        nothing
    end
    open_block! = function (kind::Symbol, start_event)
        open_block[] === kind && return nothing
        close_block!()
        on_event(start_event)
        open_block[] = kind
        nothing
    end

    function (obj)
        err = get(obj, :error, nothing)
        if err !== nothing
            close_block!()
            on_event(LlmFailure(String(err)))
            return nothing
        end

        msg = get(obj, :message, nothing)
        if msg !== nothing
            reasoning = String(get(msg, :thinking, ""))
            if !isempty(reasoning)
                open_block!(:thinking, LlmThinkingStart())
                on_event(LlmThinkingDelta(reasoning))
            end
            content = String(get(msg, :content, ""))
            if !isempty(content)
                open_block!(:text, LlmTextStart())
                on_event(LlmTextDelta(content))
            end
            calls = get(msg, :tool_calls, nothing)
            if calls !== nothing
                for call in calls
                    f = get(call, :function, nothing)
                    f === nothing && continue
                    close_block!()
                    saw_tool[] = true
                    call_count[] += 1
                    name = String(get(f, :name, ""))
                    id   = String(get(call, :id, ""))
                    # A server that names no call still needs one id, because the
                    # result that answers it is paired by id.
                    isempty(id) && (id = "ollama_call_" * string(call_count[]))
                    input = _tool_input(get(f, :arguments, nothing))
                    on_event(LlmToolUseStart(id, name))
                    # The whole call arrives at once, so the fragment event carries
                    # the whole argument JSON — a panel that shows arguments as they
                    # stream still has something to show.
                    on_event(LlmToolInputDelta(JSON3.write(input)))
                    on_event(LlmToolUseStop(LlmToolUse(id, name, input)))
                end
            end
        end

        if get(obj, :done, false) === true
            close_block!()
            # **Ollama reports `done_reason: "stop"` on a turn that made tool
            # calls.** The agent loop runs a tool only when the turn ends in
            # `:tool_use`, so the calls this turn made decide the reason, and the
            # server's word decides only the rest.
            reason = String(get(obj, :done_reason, "stop"))
            # The last line carries the counts of the round: the prompt the model
            # read, and what it wrote.
            on_event(LlmTurnEnd(saw_tool[]         ? :tool_use :
                                reason == "length" ? :max_tokens :
                                                     :end_turn,
                                Int(get(obj, :prompt_eval_count, 0)),
                                Int(get(obj, :eval_count, 0))))
        end
        nothing
    end
end

"""
    stream_turn(llm::OllamaLlm, request::LlmRequest; on_event)

POST a streaming chat request and translate the newline-delimited stream into
`LlmEvent`s. An HTTP failure throws; an error reported *inside* the stream arrives
as an `LlmFailure`. A stream that ends before its `done` line throws, as a dead
socket does.

Ollama sends no block framing at all — no start, no stop, only message deltas — so
this function opens and closes the blocks itself, from what each line carries.
"""
function stream_turn(llm::OllamaLlm, request::LlmRequest; on_event::Function)
    options = Dict{String,Any}("num_predict" => llm.max_tokens)
    # Sent only when a caller asked for a size. Ollama's own answer — from the
    # model and its configuration — is the right one until somebody has a reason,
    # and an unasked-for `num_ctx` would take that away.
    llm.context > 0 && (options["num_ctx"] = llm.context)
    llm.temperature === nothing || (options["temperature"] = llm.temperature)
    llm.seed === nothing || (options["seed"] = llm.seed)
    body = Dict{String,Any}(
        "model"    => llm.model,
        "stream"   => true,
        "messages" => _wire_messages(request),
        "options"  => options,
    )
    isempty(request.tools) || (body["tools"] = render_tool_schema(llm, request.tools))
    request.thinking && _supports_thinking(llm) && (body["think"] = true)

    # Whether the stream sent its terminal event, a turn end or a failure.
    ended = Ref(false)
    handle_line = _line_handler(function (ev)
        (ev isa LlmTurnEnd || ev isa LlmFailure) && (ended[] = true)
        on_event(ev)
    end)

    HTTP.open("POST", llm.base_url * "/api/chat",
              ["content-type" => "application/json",
               "accept"       => "application/x-ndjson"];
              status_exception = false,
              decompress       = false) do io
        write(io, JSON3.write(body))
        HTTP.closewrite(io)

        HTTP.startread(io)
        if io.message.status >= 400
            err_body = String(read(io))
            HTTP.closeread(io)
            error(_describe_chat_refusal(llm, io.message.status, err_body))
        end

        # One JSON object per line. Read in chunks with `readavailable` (not
        # `readline`, which warns about byte-by-byte reads on an HTTP.Stream) and
        # split on the newline; a buffer carries an incomplete line across chunks.
        buf = IOBuffer()
        try
            while !eof(io)
                chunk = try
                    readavailable(io)
                catch e
                    # An EOF ends the read. The check after the read throws when
                    # the stream sent no terminal event.
                    e isa EOFError ? UInt8[] : rethrow()
                end
                isempty(chunk) && continue
                write(buf, chunk)
                _drain_lines!(buf, handle_line)
            end
            _drain_lines!(buf, handle_line; final = true)
        catch
            # A caller that stops the turn throws from `on_event`. The close of an
            # HTTP stream reads the rest of the answer first, so the connection
            # closes here, and the model stops at once.
            close(io.stream)
            rethrow()
        end
        HTTP.closeread(io)
    end
    ended[] || error("The Ollama stream of $(llm.model) ended before its `done` line.")
    nothing
end

# Pull complete lines out of `buf` and translate each. The tail is incomplete until
# `final`, when what is left is the last line.
function _drain_lines!(buf::IOBuffer, handle::Function; final::Bool = false)
    s = String(take!(buf))
    isempty(s) && return nothing
    parts = split(s, '\n')
    n = final ? length(parts) : length(parts) - 1
    for i in 1:n
        line = strip(parts[i])
        isempty(line) && continue
        parsed = try
            JSON3.read(line)
        catch
            nothing
        end
        parsed === nothing && continue
        handle(parsed)
    end
    if !final && length(parts) > n
        write(buf, parts[end])
    end
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Meaning vectors — /api/embed
# ═══════════════════════════════════════════════════════════════════════

has_meaning_model(llm::OllamaLlm) = !isempty(llm.meaning_model)

get_meaning_model_name(llm::OllamaLlm) =
    has_meaning_model(llm) ? "ollama/" * llm.meaning_model :
                             error("This Ollama backend has no meaning model.")

# How many texts go to the server in one request.
const _MEANING_BATCH_SIZE = 64

# The words a model wants in front of a text, by what the text is for. Each was
# trained with them, and its vectors are worse without them. A model that is not
# listed gets the text as it is.
const _MEANING_PREFIXES = Dict(
    "nomic-embed-text" => (query = "search_query: ", document = "search_document: "),
    "mxbai-embed-large" =>
        (query = "Represent this sentence for searching relevant passages: ", document = ""),
)

# The family is the name without its tag and its namespace:
# `library/nomic-embed-text:latest` is `nomic-embed-text`.
function _get_meaning_prefix(model::AbstractString, purpose::Symbol)
    family = last(split(first(split(model, ':')), '/'))
    prefixes = get(_MEANING_PREFIXES, family, nothing)
    prefixes === nothing && return ""
    purpose === :query ? prefixes.query : prefixes.document
end

"""
    compute_meaning_vectors(llm::OllamaLlm, texts; purpose = :document) -> Matrix{Float32}

Ask the server for the meaning vectors of `texts`, in batches of 64, with the
prefix the meaning model wants for `purpose`. A server that does not answer
throws the connection error; a model that is not installed throws a message that
says how to install it.
"""
function compute_meaning_vectors(llm::OllamaLlm, texts; purpose::Symbol = :document)
    has_meaning_model(llm) || error("This Ollama backend has no meaning model.")
    purpose in (:query, :document) ||
        error("A meaning vector is for a :query or a :document, not for $(repr(purpose)).")
    prefix = _get_meaning_prefix(llm.meaning_model, purpose)
    columns = Vector{Float32}[]
    for batch in Iterators.partition(texts, _MEANING_BATCH_SIZE)
        append!(columns, _request_meaning_vectors(llm, String[prefix * text for text in batch]))
    end
    isempty(columns) ? Matrix{Float32}(undef, 0, 0) : reduce(hcat, columns)
end

function _request_meaning_vectors(llm::OllamaLlm, inputs::Vector{String})
    response = HTTP.post(llm.base_url * "/api/embed",
                         ["content-type" => "application/json"],
                         JSON3.write(Dict("model" => llm.meaning_model, "input" => inputs));
                         status_exception = false, retry = false,
                         connect_timeout = 5, readtimeout = 300)
    response.status == 200 || error(_describe_meaning_refusal(llm, response))
    vectors = [Vector{Float32}(vector) for vector in JSON3.read(response.body).embeddings]
    length(vectors) == length(inputs) ||
        error("Ollama answered $(length(vectors)) meaning vectors for $(length(inputs)) texts.")
    vectors
end

"""
    _describe_chat_refusal(llm, status, body) -> String

What a refused chat request means, for the person who submitted the turn.

A model that is not pulled is the usual reason, so the answer names the server,
the models that server has, and the command that installs the missing one.
"""
function _describe_chat_refusal(llm::OllamaLlm, status::Integer, body::AbstractString)
    message = try
        String(get(JSON3.read(body), :error, body))
    catch
        String(body)
    end
    if status == 404 || occursin("not found", lowercase(message))
        pulled = get_ollama_models(llm)
        having = isempty(pulled) ? "It has no model at all." :
                 "It has " * join(pulled, ", ") * "."
        return "Ollama at $(llm.base_url) has no model $(llm.model). " * having *
               " Run `ollama pull $(llm.model)` to install it."
    end
    "Ollama at $(llm.base_url) refused the turn (HTTP $status): " * message
end

"""
    get_ollama_models(llm) -> Vector{String}

The models the server has, or an empty list when it does not answer. It is for
an error message, so a server that is down must not raise a second error here.
"""
function get_ollama_models(llm::OllamaLlm)
    try
        response = HTTP.get(llm.base_url * "/api/tags"; status_exception = false,
                            readtimeout = 5)
        response.status == 200 || return String[]
        [String(model.name) for model in JSON3.read(response.body).models]
    catch
        String[]
    end
end

# What a refused request means. A model that is not pulled is the usual reason,
# and the answer says how to pull it.
function _describe_meaning_refusal(llm::OllamaLlm, response)
    message = try
        String(get(JSON3.read(response.body), :error, ""))
    catch
        String(response.body)
    end
    (response.status == 404 || occursin("not found", message)) &&
        return "Ollama has no model $(llm.meaning_model). " *
               "Run `ollama pull $(llm.meaning_model)` to install it."
    "Ollama refused to compute meaning vectors (HTTP $(response.status)): " * message
end
