export AnthropicLlm

const _ANTHROPIC_URL     = "https://api.anthropic.com/v1/messages"
const _ANTHROPIC_VERSION = "2023-06-01"
const _DEFAULT_MODEL     = "claude-opus-4-5-20251101"

"""
    AnthropicLlm(; api_key, model, base_url, max_tokens)

The real Claude backend. It carries its own configuration: the API key and the
model are *this backend's identity*, not parameters of "have a conversation",
which is why they live here and not in `LlmRequest`.

`api_key` defaults to `ENV["ANTHROPIC_API_KEY"]`, read at construction, so a key
exported before launch takes effect without being baked into a document.
"""
struct AnthropicLlm <: Llm
    api_key::String
    model::String
    base_url::String
    max_tokens::Int
end

AnthropicLlm(; api_key::AbstractString = get(ENV, "ANTHROPIC_API_KEY", ""),
               model::AbstractString = _DEFAULT_MODEL,
               base_url::AbstractString = _ANTHROPIC_URL,
               max_tokens::Integer = 4096) =
    AnthropicLlm(String(api_key), String(model), String(base_url), Int(max_tokens))

# ═══════════════════════════════════════════════════════════════════════
# Request → Anthropic JSON
# ═══════════════════════════════════════════════════════════════════════

"""
    tool_schema(llm::AnthropicLlm, tools) -> Vector{Dict}

Render `Tool`s into the JSON-Schema-shaped vector the Messages API wants for its
`tools` parameter. `ProjecturedMcp` does the same job for MCP's wire format; a
`Tool` itself knows neither.
"""
function tool_schema(::AnthropicLlm, tools::AbstractVector{Tool})
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
            "name"         => t.name,
            "description"  => t.description,
            "input_schema" => Dict("type"       => "object",
                                   "properties" => properties,
                                   "required"   => required),
        ))
    end
    out
end

# One content block in Anthropic's shape. A thinking block carries its signature
# back unchanged, or a tool-use continuation is rejected.
_wire(c::LlmText)             = Dict("type" => "text", "text" => c.text)
_wire(c::LlmThinking)         = Dict("type"      => "thinking",
                                     "thinking"  => c.text,
                                     "signature" => c.signature)
_wire(c::LlmRedactedThinking) = Dict("type" => "redacted_thinking", "data" => c.data)
_wire(c::LlmToolUse)          = Dict("type"  => "tool_use",
                                     "id"    => c.id,
                                     "name"  => c.name,
                                     "input" => c.input)
_wire(c::LlmToolResult)       = Dict("type"        => "tool_result",
                                     "tool_use_id" => c.tool_use_id,
                                     "content"     => c.content,
                                     "is_error"    => c.is_error)

_wire(m::LlmMessage) = Dict("role"    => String(m.role),
                            "content" => Any[_wire(c) for c in m.content])

# Extended thinking. Opus 4.x / Sonnet thinking models accept
# `{"type":"adaptive","display":"summarized"}` — `display: "summarized"` is what
# yields readable reasoning text (the default is `"omitted"`), while
# `budget_tokens` / `{"type":"enabled"}` are rejected on these models. Which models
# support it, and what the parameter looks like, is Anthropic's business: the
# kernel's `LlmRequest` says only whether thinking was *asked for*.
function _thinking_param(model::AbstractString)
    m = lowercase(String(model))
    (occursin("opus", m) || occursin("sonnet", m)) || return nothing
    Dict("type" => "adaptive", "display" => "summarized")
end

# ═══════════════════════════════════════════════════════════════════════
# Anthropic SSE → LlmEvent
# ═══════════════════════════════════════════════════════════════════════

# Translate one Anthropic SSE event and hand the result to `emit`. This function is
# the whole of what the rest of the system is spared: above `stream_turn`,
# `content_block_delta` and `input_json_delta` do not exist.
#
# `emit(nothing)` signals a `content_block_stop`: Anthropic closes every kind of
# block with the same event, so which block is closing is not in the event — the
# caller tracks the open block and turns it into the right typed stop.
function _translate_sse!(emit::Function, type::Symbol, data)
    if type === :content_block_start
        block = get(data, :content_block, nothing)
        block === nothing && return
        bt = get(block, :type, "")
        if bt == "text"
            emit(LlmTextStart())
        elseif bt == "thinking"
            emit(LlmThinkingStart())
        elseif bt == "redacted_thinking"
            emit(LlmRedactedThinkingBlock(String(get(block, :data, ""))))
        elseif bt == "tool_use"
            emit(LlmToolUseStart(String(get(block, :id, "")),
                                 String(get(block, :name, ""))))
        end
    elseif type === :content_block_delta
        delta = get(data, :delta, nothing)
        delta === nothing && return
        dt = get(delta, :type, "")
        if dt == "text_delta"
            emit(LlmTextDelta(String(get(delta, :text, ""))))
        elseif dt == "thinking_delta"
            emit(LlmThinkingDelta(String(get(delta, :thinking, ""))))
        elseif dt == "signature_delta"
            emit(LlmThinkingSignature(String(get(delta, :signature, ""))))
        elseif dt == "input_json_delta"
            emit(LlmToolInputDelta(String(get(delta, :partial_json, ""))))
        end
    elseif type === :content_block_stop
        emit(nothing)
    elseif type === :message_delta
        delta = get(data, :delta, nothing)
        delta === nothing && return
        sr = get(delta, :stop_reason, nothing)
        sr === nothing || emit(LlmTurnEnd(Symbol(sr)))
    elseif type === :error
        err = get(data, :error, nothing)
        msg = err === nothing ? "unknown streaming error" :
              String(get(err, :message, "unknown streaming error"))
        emit(LlmFailure(msg))
    end
    nothing
end

"""
    stream_turn(llm::AnthropicLlm, request::LlmRequest; on_event)

POST a streaming Messages request and translate the SSE stream into `LlmEvent`s. An
HTTP failure throws; an error reported *inside* the stream arrives as an
`LlmFailure`.
"""
function stream_turn(llm::AnthropicLlm, request::LlmRequest; on_event::Function)
    body = Dict{String,Any}(
        "model"      => llm.model,
        "max_tokens" => llm.max_tokens,
        "stream"     => true,
        "messages"   => Any[_wire(m) for m in request.messages],
    )
    isempty(request.system) || (body["system"] = request.system)
    isempty(request.tools)  || (body["tools"]  = tool_schema(llm, request.tools))
    if request.thinking
        t = _thinking_param(llm.model)
        t === nothing || (body["thinking"] = t)
    end

    headers = [
        "x-api-key"         => llm.api_key,
        "anthropic-version" => _ANTHROPIC_VERSION,
        "content-type"      => "application/json",
        "accept"            => "text/event-stream",
    ]

    # Which block is open, so the shared `content_block_stop` becomes the right typed
    # stop event — and, for a tool call, so its streamed argument fragments can be
    # assembled and parsed here, where the JSON parser is.
    open_block = Ref(:none)
    tool_id    = Ref("")
    tool_name  = Ref("")
    tool_input = Ref(IOBuffer())
    emit = function (ev)
        if ev === nothing                            # a content_block_stop
            b = open_block[]
            if b === :text
                on_event(LlmTextStop())
            elseif b === :thinking
                on_event(LlmThinkingStop())
            elseif b === :tool
                raw = String(take!(tool_input[]))
                on_event(LlmToolUseStop(
                    LlmToolUse(tool_id[], tool_name[], _parse_tool_input(raw))))
            end
            open_block[] = :none
            return nothing
        end
        if ev isa LlmTextStart
            open_block[] = :text
        elseif ev isa LlmThinkingStart
            open_block[] = :thinking
        elseif ev isa LlmToolUseStart
            open_block[] = :tool
            tool_id[]    = ev.id
            tool_name[]  = ev.name
            tool_input[] = IOBuffer()
        elseif ev isa LlmToolInputDelta
            print(tool_input[], ev.json)
        end
        on_event(ev)
        nothing
    end

    HTTP.open("POST", llm.base_url, headers;
              status_exception = false,
              decompress       = false) do io
        write(io, JSON3.write(body))
        HTTP.closewrite(io)

        HTTP.startread(io)
        if io.message.status >= 400
            err_body = String(read(io))
            HTTP.closeread(io)
            error("Anthropic API error: HTTP $(io.message.status): $err_body")
        end

        # SSE parser. Read in chunks via `readavailable` (not `readline`, which
        # warns about byte-by-byte reads on an HTTP.Stream) and split on the event
        # boundary "\n\n"; a buffer carries an incomplete event across chunks.
        buf = IOBuffer()
        while !eof(io)
            chunk = try
                readavailable(io)
            catch e
                # SSE streams can close abruptly after the last event; treat EOF as
                # a clean end-of-stream, the final message_stop having been seen.
                e isa EOFError ? UInt8[] : rethrow()
            end
            isempty(chunk) && continue
            write(buf, chunk)
            _drain_sse_events!(buf, emit)
        end
        _drain_sse_events!(buf, emit; final = true)
        HTTP.closeread(io)
    end
    nothing
end

# A tool call's arguments arrive as JSON fragments; only the concatenation is valid
# JSON. Parsing it is the adapter's job — this package speaks a JSON protocol and so
# has a parser, while the kernel has no dependencies at all and has none. A malformed
# or empty payload yields no arguments rather than throwing: the model can be asked
# to try again, but a broken turn cannot be recovered.
_native(v::JSON3.Object) = Dict{String,Any}(String(k) => _native(x) for (k, x) in pairs(v))
_native(v::JSON3.Array)  = Any[_native(x) for x in v]
_native(v)               = v

function _parse_tool_input(raw::AbstractString)
    isempty(strip(raw)) && return Dict{String,Any}()
    parsed = try
        JSON3.read(raw)
    catch
        return Dict{String,Any}()
    end
    parsed isa JSON3.Object || return Dict{String,Any}()
    _native(parsed)
end

# Pull complete SSE events ("event: …\ndata: …\n\n") out of `buf` and translate each.
function _drain_sse_events!(buf::IOBuffer, emit::Function; final::Bool = false)
    s = String(take!(buf))
    isempty(s) && return
    parts = split(s, "\n\n")
    n = final ? length(parts) : length(parts) - 1     # the tail is incomplete
    for i in 1:n
        raw = parts[i]
        isempty(raw) && continue
        event_name = ""
        data_lines = String[]
        for line in split(raw, '\n')
            if startswith(line, "event:")
                event_name = strip(SubString(line, 7))
            elseif startswith(line, "data:")
                push!(data_lines, String(strip(SubString(line, 6))))
            end
        end
        isempty(data_lines) && continue
        parsed = try
            JSON3.read(join(data_lines, "\n"))
        catch
            nothing
        end
        parsed === nothing && continue
        type = Symbol(isempty(event_name) ? get(parsed, :type, "") : event_name)
        _translate_sse!(emit, type, parsed)
    end
    # Put the incomplete tail back for the next read.
    if !final && length(parts) > n
        write(buf, parts[end])
    end
end
