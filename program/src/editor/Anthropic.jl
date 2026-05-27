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

    HTTP.open("POST", base_url, headers; status_exception = false) do io
        write(io, payload)
        HTTP.closewrite(io)

        HTTP.startread(io)
        if io.message.status >= 400
            err_body = String(read(io))
            HTTP.closeread(io)
            error("Anthropic API error: HTTP $(io.message.status): $err_body")
        end

        # Parse SSE: lines of "event: <name>" and "data: <json>",
        # separated by blank lines.
        event_name = ""
        data_lines = String[]
        buf = IOBuffer()
        while !eof(io)
            line = readline(io; keep = false)
            if isempty(line)
                # Dispatch accumulated event
                if !isempty(data_lines)
                    data_str = join(data_lines, "\n")
                    parsed = try
                        JSON3.read(data_str)
                    catch
                        nothing
                    end
                    if parsed !== nothing
                        type_sym = Symbol(isempty(event_name) ?
                                          get(parsed, :type, "") : event_name)
                        on_event((type = type_sym, data = parsed))
                    end
                end
                event_name = ""
                empty!(data_lines)
            elseif startswith(line, "event:")
                event_name = strip(SubString(line, 7))
            elseif startswith(line, "data:")
                push!(data_lines, String(strip(SubString(line, 6))))
            end
        end
        HTTP.closeread(io)
    end
    nothing
end

end # module
