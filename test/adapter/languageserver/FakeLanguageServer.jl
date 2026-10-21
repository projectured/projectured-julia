# A language server in this process, for the tests: it reads the messages of a
# client on one stream and writes its answers on another, with the
# `Content-Length` frame of the protocol. It keeps the text of each file that
# the client opens, and answers the tokens that `tokens(text)` gives.

"""
    FakeLanguageServer

The state of a server in this process: the streams of its client, every message
that it read, the text of each open file by URI, and the task that serves.
"""
mutable struct FakeLanguageServer
    to_server::Base.BufferStream
    to_client::Base.BufferStream
    received::Vector{Dict{String, Any}}
    texts::Dict{String, String}
    task::Union{Task, Nothing}
end

_fake_write(io::IO, message) = (body = JSON3.write(message);
                                write(io, "Content-Length: ", string(sizeof(body)), "\r\n\r\n", body))

function _fake_read(io::IO)
    content_length = nothing
    while true
        eof(io) && return nothing
        line = rstrip(readline(io), '\r')
        isempty(line) && content_length !== nothing && break
        isempty(line) && continue
        name, value = strip.(split(line, ':'; limit = 2))
        lowercase(name) == "content-length" && (content_length = parse(Int, value))
    end
    JSON3.read(String(read(io, content_length)), Dict{String, Any})
end

"""
    start_fake_language_server(; encoding = "utf-32", token_types, tokens, ask = false)
        -> (server, connection)

Start a server in this process and make a connection to it. `encoding` is the
`positionEncoding` that it agrees on, or `nothing` for none. `token_types` is its
legend, and `tokens(text)` the data of its semantic tokens for a text. With `ask`,
it sends the client a request and a notification before it answers `initialize`.
It gives no answer to the method `test/silent`, and ends at `exit`.
"""
function start_fake_language_server(; encoding = "utf-32", token_types = ["variable", "function"],
                                    tokens = text -> Int[], ask::Bool = false)
    server = FakeLanguageServer(Base.BufferStream(), Base.BufferStream(), Dict{String, Any}[],
                                Dict{String, String}(), nothing)
    server.task = Threads.@spawn _serve_fake_language_server(server, encoding, token_types, tokens, ask)
    connection = LanguageServerConnection(["fake"]; streams = (server.to_server, server.to_client))
    (server, connection)
end

function _serve_fake_language_server(server, encoding, token_types, tokens, ask)
    while true
        message = _fake_read(server.to_server)
        message === nothing && break
        push!(server.received, message)
        method = get(message, "method", nothing)
        id = get(message, "id", nothing)
        parameters = get(message, "params", nothing)
        if method == "initialize"
            if ask
                _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => 900,
                                                   "method" => "window/workDoneProgress/create",
                                                   "params" => Dict("token" => "t")))
                _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "method" => "window/logMessage",
                                                   "params" => Dict("type" => 3, "message" => "hello")))
            end
            capabilities = Dict{String, Any}("textDocumentSync" => 1,
                "semanticTokensProvider" => Dict("full" => true,
                    "legend" => Dict("tokenTypes" => token_types, "tokenModifiers" => String[])))
            encoding === nothing || (capabilities["positionEncoding"] = encoding)
            _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => id,
                                               "result" => Dict("capabilities" => capabilities)))
        elseif method == "textDocument/didOpen"
            document = parameters["textDocument"]
            server.texts[document["uri"]] = document["text"]
        elseif method == "textDocument/didChange"
            server.texts[parameters["textDocument"]["uri"]] = last(parameters["contentChanges"])["text"]
        elseif method == "textDocument/didClose"
            delete!(server.texts, parameters["textDocument"]["uri"])
        elseif method == "textDocument/semanticTokens/full"
            text = server.texts[parameters["textDocument"]["uri"]]
            _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => id,
                                               "result" => Dict("data" => tokens(text))))
        elseif method == "test/echo"
            _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => id, "result" => parameters))
        elseif method == "test/fail"
            _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => id,
                                               "error" => Dict("code" => -32000, "message" => "no")))
        elseif method == "shutdown"
            _fake_write(server.to_client, Dict("jsonrpc" => "2.0", "id" => id, "result" => nothing))
        elseif method == "exit"
            break
        end
    end
    close(server.to_client)
    nothing
end

# The messages that the server read with the method `method`.
get_fake_messages(server::FakeLanguageServer, method) =
    [m for m in server.received if get(m, "method", nothing) == method]
