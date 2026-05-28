"""
    AnthropicModule

Minimal Anthropic Messages API client. One public function:
`stream_message(api_key, model, system, messages, tools; on_event)`.

POSTs to `https://api.anthropic.com/v1/messages` with `stream=true`,
parses the SSE response incrementally, and invokes `on_event(event)`
for every parsed event. Event types follow Anthropic's streaming spec:
`message_start`, `content_block_start`, `content_block_delta`,
`content_block_stop`, `message_delta`, `message_stop`, `ping`, `error`.

This module owns only the wire protocol — it does not touch documents,
cells, or projections.
"""
module AnthropicModule

using HTTP
using JSON3

export stream_message

const _ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
const _ANTHROPIC_VERSION = "2023-06-01"

"""
    stream_message(api_key, model, system, messages, tools; on_event,
                    max_tokens=4096, base_url=_ANTHROPIC_URL)

POST a streaming Messages request to Anthropic. `messages` is the array
of message dicts already shaped for the API; `tools` is a vector of
JSON-Schema tool descriptions (see `ToolRegistryModule.anthropic_tool_schema`).

`on_event(event::NamedTuple)` is called for each SSE event. The named
tuple has at least `:type` (the event type as `Symbol`) and `:data`
(the raw parsed JSON object, as returned by `JSON3.read`).
"""
function stream_message(api_key::AbstractString,
                        model::AbstractString,
                        system::AbstractString,
                        messages::AbstractVector,
                        tools::AbstractVector;
                        on_event::Function,
                        max_tokens::Integer = 4096,
                        base_url::AbstractString = _ANTHROPIC_URL)
    body = Dict{String,Any}(
        "model"      => String(model),
        "max_tokens" => Int(max_tokens),
        "stream"     => true,
        "messages"   => messages,
    )
    if !isempty(system)
        body["system"] = String(system)
    end
    if !isempty(tools)
        body["tools"] = tools
    end
    payload = JSON3.write(body)

    headers = [
        "x-api-key"         => String(api_key),
        "anthropic-version" => _ANTHROPIC_VERSION,
        "content-type"      => "application/json",
        "accept"            => "text/event-stream",
    ]

    HTTP.open("POST", base_url, headers;
              status_exception = false,
              decompress       = false) do io
        write(io, payload)
        HTTP.closewrite(io)

        HTTP.startread(io)
        if io.message.status >= 400
            err_body = String(read(io))
            HTTP.closeread(io)
            error("Anthropic API error: HTTP $(io.message.status): $err_body")
        end

        # SSE parser. Read in chunks via `readavailable` (instead of
        # `readline`, which warns about byte-by-byte reads on HTTP.Stream)
        # and split on the event boundary "\n\n". A buffer carries any
        # incomplete event across chunk boundaries.
        buf = IOBuffer()
        while !eof(io)
            chunk = try
                readavailable(io)
            catch e
                # SSE streams may close abruptly after the last event;
                # treat EOFError as a clean end-of-stream so the final
                # message_stop (already dispatched) is the loop's exit.
                e isa EOFError ? UInt8[] : rethrow()
            end
            isempty(chunk) && continue
            write(buf, chunk)
            _drain_sse_events!(buf, on_event)
        end
        # Flush any trailing partial event.
        _drain_sse_events!(buf, on_event; final = true)
        HTTP.closeread(io)
    end
    nothing
end

# Pull complete SSE events ("event: …\ndata: …\n\n") from `buf` and
# dispatch each via `on_event`. `final=true` flushes the buffer tail
# even if it doesn't end in the double-newline separator.
function _drain_sse_events!(buf::IOBuffer, on_event::Function; final::Bool = false)
    s = String(take!(buf))
    isempty(s) && return
    parts = split(s, "\n\n")
    # The last part is incomplete unless we're flushing.
    n = final ? length(parts) : length(parts) - 1
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
        data_str = join(data_lines, "\n")
        parsed = try
            JSON3.read(data_str)
        catch
            nothing
        end
        parsed === nothing && continue
        type_sym = Symbol(isempty(event_name) ?
                          get(parsed, :type, "") : event_name)
        on_event((type = type_sym, data = parsed))
    end
    # Put the incomplete tail back for the next read.
    if !final && length(parts) > n
        write(buf, parts[end])
    end
end

end # module
