export OllamaLlm

const _OLLAMA_URL    = "http://localhost:11434"
const _DEFAULT_MODEL = "qwen3.8:27b"

"""
    OllamaLlm(; model, base_url, max_tokens, thinking)

A model that runs on this machine, served by Ollama. It carries its own
configuration, because that configuration is *this backend's identity* and not a
parameter of "have a conversation".

There is no API key: the server is local, and it asks for none. `base_url` is the
**server**, not one endpoint, because the adapter uses two of them — `/api/chat`
to run a turn and `/api/show` to ask what the model can do.

`thinking` decides whether the turn may ask for reasoning:

- `nothing` (the default) asks the server. Ollama reports a `capabilities` list
  per model, and the answer is kept on this instance.
- `true` or `false` says so, and no question is asked.

The question matters. Ollama rejects the **whole request** with HTTP 400 when a
model that cannot reason is asked to, so a guess from the model's name — which is
what a hosted provider's adapter can afford — would kill the turn.
"""
struct OllamaLlm <: Llm
    model::String
    base_url::String
    max_tokens::Int
    thinking::Union{Nothing,Bool}
    # The answer of the capability question, kept per instance. Never a module
    # global: one process runs many editors, and each holds its own backend.
    thinking_answer::Ref{Union{Nothing,Bool}}
end

OllamaLlm(; model::AbstractString = _DEFAULT_MODEL,
            base_url::AbstractString = _OLLAMA_URL,
            max_tokens::Integer = 4096,
            thinking::Union{Nothing,Bool} = nothing) =
    OllamaLlm(String(isempty(model) ? _DEFAULT_MODEL : model),
              String(rstrip(base_url, '/')),
              Int(max_tokens), thinking,
              Ref{Union{Nothing,Bool}}(nothing))

# This package's registration on the kernel's factory seam. `api_key` is accepted
# and ignored: it is one of the two keywords every backend takes, and a server on
# this machine asks for none.
make_llm(::Val{:ollama}; api_key::AbstractString = "", kwargs...) = OllamaLlm(; kwargs...)

default_llm_model(::Val{:ollama}) = _DEFAULT_MODEL

# ═══════════════════════════════════════════════════════════════════════
# Request → Ollama JSON
# ═══════════════════════════════════════════════════════════════════════

"""
    tool_schema(llm::OllamaLlm, tools) -> Vector{Dict}

Render `Tool`s into the shape Ollama's `tools` parameter takes: a function
wrapper around a JSON-Schema object. Anthropic's `input_schema` is the same
information in a different envelope, which is why each adapter renders it and a
`Tool` itself knows neither.
"""
function tool_schema(::OllamaLlm, tools::AbstractVector{Tool})
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
    stream_turn(llm::OllamaLlm, request::LlmRequest; on_event)

POST a streaming chat request and translate the newline-delimited stream into
`LlmEvent`s. An HTTP failure throws; an error reported *inside* the stream arrives
as an `LlmFailure`.

Ollama sends no block framing at all — no start, no stop, only message deltas — so
this function opens and closes the blocks itself, from what each line carries.
"""
function stream_turn(llm::OllamaLlm, request::LlmRequest; on_event::Function)
    body = Dict{String,Any}(
        "model"    => llm.model,
        "stream"   => true,
        "messages" => _wire_messages(request),
        "options"  => Dict("num_predict" => llm.max_tokens),
    )
    isempty(request.tools) || (body["tools"] = tool_schema(llm, request.tools))
    request.thinking && _supports_thinking(llm) && (body["think"] = true)

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

    handle_line = function (obj)
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
                    raw   = get(f, :arguments, nothing)
                    input = _tool_input(raw)
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
            on_event(LlmTurnEnd(saw_tool[]        ? :tool_use :
                                reason == "length" ? :max_tokens :
                                                     :end_turn))
        end
        nothing
    end

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
            error("Ollama API error: HTTP $(io.message.status): $err_body")
        end

        # One JSON object per line. Read in chunks with `readavailable` (not
        # `readline`, which warns about byte-by-byte reads on an HTTP.Stream) and
        # split on the newline; a buffer carries an incomplete line across chunks.
        buf = IOBuffer()
        while !eof(io)
            chunk = try
                readavailable(io)
            catch e
                # The stream can close abruptly after the last line; treat EOF as a
                # clean end, the final `done` line having been seen.
                e isa EOFError ? UInt8[] : rethrow()
            end
            isempty(chunk) && continue
            write(buf, chunk)
            _drain_lines!(buf, handle_line)
        end
        _drain_lines!(buf, handle_line; final = true)
        HTTP.closeread(io)
    end
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
