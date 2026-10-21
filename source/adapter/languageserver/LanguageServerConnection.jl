# Fragment of `LanguageServerModule` — `LanguageServerConnection`, the client side
# of one language server: the start of its process and the agreement on the
# protocol, the requests and their answers, the notifications, and the stop.

"""
    LanguageServerException(message)

A language server did not start, did not answer, ended, or answered with an
error. `message` says which, in words for a person.
"""
struct LanguageServerException <: Exception
    message::String
end

Base.showerror(io::IO, exception::LanguageServerException) =
    print(io, "LanguageServerException: ", exception.message)

"""
    LanguageServerConnection(command; directory = pwd(), streams = nothing)

A connection to one language server.

- `command`   — the program of the server and its arguments, as `["clangd"]`.
- `directory` — where the process starts, and the root folder that the server
                gets at the start.
- `streams`   — `(input, output)` to talk on instead of a process: the client
                writes to `input` and reads from `output`. A test gives the two
                streams of a server in this process. `nothing` starts `command`.

The connection starts nothing when it is made. `start_language_server!` starts
the process and agrees on the protocol, at the first use; a start that failed
is not tried again, and each later use throws its `LanguageServerException`.

`lock` is the lock of an exchange with the server, such as a change of a text
and the question that follows it, so that two works do not mix their messages.
The fields after it are the state of the connection, which `state_lock` guards:

- `position_encoding` — how the server counts a column: `"utf-32"` counts
  characters, as the editor does, and `"utf-16"` counts the units of UTF-16.
- `token_types`       — the names of the kinds of the semantic tokens of the
                        server, by index (the legend).
- `documents`         — the version of each file that the server holds, by URI.
- `failure`           — the exception of a start that failed, or `nothing`.
"""
mutable struct LanguageServerConnection
    const command::Vector{String}
    const directory::String
    const streams::Union{Tuple{IO, IO}, Nothing}
    const lock::ReentrantLock
    const state_lock::ReentrantLock
    const write_lock::ReentrantLock
    process::Union{Base.Process, Nothing}
    input::Union{IO, Nothing}
    reader::Union{Task, Nothing}
    running::Bool
    next_id::Int
    waits::Dict{Int, Channel{Any}}
    position_encoding::String
    token_types::Vector{String}
    documents::Dict{String, Int}
    failure::Union{LanguageServerException, Nothing}
end

LanguageServerConnection(command::AbstractVector{<:AbstractString}; directory::AbstractString = pwd(),
                         streams::Union{Tuple{IO, IO}, Nothing} = nothing) =
    LanguageServerConnection(String.(command), String(directory), streams, ReentrantLock(),
                             ReentrantLock(), ReentrantLock(), nothing, nothing, nothing, false, 0,
                             Dict{Int, Channel{Any}}(), "utf-16", String[], Dict{String, Int}(), nothing)

Base.show(io::IO, connection::LanguageServerConnection) =
    print(io, "LanguageServerConnection(", repr(connection.command), ")")

"""
    is_language_server_running(connection) -> Bool

Whether the server of `connection` started, agreed on the protocol, and did not
end.
"""
is_language_server_running(connection::LanguageServerConnection) =
    lock(() -> connection.running, connection.state_lock)

# The time to wait for the answer to `initialize`, `shutdown` and a request.
const LANGUAGE_SERVER_START_TIMEOUT = 30.0
const LANGUAGE_SERVER_STOP_TIMEOUT = 2.0
const LANGUAGE_SERVER_REQUEST_TIMEOUT = 30.0

# The kinds of semantic tokens of the protocol, which the client offers at the start.
const _SEMANTIC_TOKEN_TYPES = ["namespace", "type", "class", "enum", "interface", "struct",
    "typeParameter", "parameter", "variable", "property", "enumMember", "event", "function",
    "method", "macro", "keyword", "modifier", "comment", "string", "number", "regexp",
    "operator", "decorator"]

"""
    start_language_server!(connection) -> LanguageServerConnection

Start the server of `connection`, unless it runs: start its process, or take its
streams, start the task that reads its answers, and agree on the protocol
(`initialize`, then `initialized`). It waits for the answer, so call it off the
loop of the editor, as the work of a background cell is.

Throws a `LanguageServerException` when the command does not start or the
server does not answer, and again at each later call, without a new try.
"""
function start_language_server!(connection::LanguageServerConnection)
    lock(() -> _start_language_server!(connection), connection.lock)
end

function _start_language_server!(connection::LanguageServerConnection)
    lock(connection.state_lock) do
        connection.failure === nothing || throw(connection.failure)
    end
    is_language_server_running(connection) && return connection
    try
        _open_language_server_streams!(connection)
        result = send_language_server_request!(connection, "initialize", _make_initialize_parameters(connection);
                                               timeout = LANGUAGE_SERVER_START_TIMEOUT, started = true)
        capabilities = get(result, "capabilities", Dict{String, Any}())
        provider = get(capabilities, "semanticTokensProvider", nothing)
        lock(connection.state_lock) do
            # A new process holds no file, also after a process that ended, so
            # each file opens again as its first version.
            empty!(connection.documents)
            connection.position_encoding = String(get(capabilities, "positionEncoding", "utf-16"))
            connection.token_types = provider isa AbstractDict ?
                String.(get(get(provider, "legend", Dict{String, Any}()), "tokenTypes", String[])) : String[]
        end
        send_language_server_notification!(connection, "initialized", Dict{String, Any}())
    catch exception
        failure = exception isa LanguageServerException ? exception :
            LanguageServerException("the language server $(join(connection.command, ' ')) did not start: " *
                                    sprint(showerror, exception))
        lock(() -> connection.failure = failure, connection.state_lock)
        # The one line of the message log for this server: a later use throws the
        # same failure and tries nothing.
        @warn "$(failure.message); its files show plain text"
        _close_language_server_streams!(connection)
        throw(failure)
    end
    connection
end

function _make_initialize_parameters(connection::LanguageServerConnection)
    Dict{String, Any}(
        "processId" => getpid(),
        "clientInfo" => Dict("name" => "ProjecturEd"),
        "rootUri" => make_file_uri(connection.directory),
        "capabilities" => Dict{String, Any}(
            "general" => Dict("positionEncodings" => ["utf-32", "utf-16"]),
            "textDocument" => Dict{String, Any}(
                "synchronization" => Dict("didSave" => false),
                "semanticTokens" => Dict{String, Any}(
                    "requests" => Dict("full" => true),
                    "tokenTypes" => _SEMANTIC_TOKEN_TYPES,
                    "tokenModifiers" => String[],
                    "formats" => ["relative"]))))
end

# Start the process, or take the streams, and the tasks that read them.
function _open_language_server_streams!(connection::LanguageServerConnection)
    if connection.streams === nothing
        isempty(connection.command) && throw(LanguageServerException("the command of the language server is empty"))
        Sys.which(first(connection.command)) === nothing &&
            throw(LanguageServerException("the language server $(first(connection.command)) is not installed"))
        errors = Pipe()
        process = open(pipeline(Cmd(Cmd(connection.command); dir = connection.directory, detach = true);
                                stderr = errors), "r+")
        close(errors.in)
        # The server writes its log to its error stream. A pipe that nobody reads
        # fills, and then the server waits, so a task reads it and drops it.
        errormonitor(Threads.@spawn :default _drop_language_server_errors(errors))
        input, output = process, process
    else
        process = nothing
        input, output = connection.streams
    end
    lock(connection.state_lock) do
        connection.process = process
        connection.input = input
        connection.running = true
    end
    # A thread of the default pool, so a work that computes on the thread that
    # started the server does not hold the answers back.
    reader = errormonitor(Threads.@spawn :default _read_language_server_messages(connection, output))
    lock(() -> connection.reader = reader, connection.state_lock)
    nothing
end

function _drop_language_server_errors(errors::Pipe)
    try
        while !eof(errors)
            readline(errors)
        end
    catch exception
        exception isa Base.IOError || rethrow()
    end
    nothing
end

function _close_language_server_streams!(connection::LanguageServerConnection)
    process, input = lock(connection.state_lock) do
        connection.running = false
        (connection.process, connection.input)
    end
    input === nothing || try close(input) catch end
    process === nothing || process_exited(process) || try kill(process) catch end
    _end_language_server_waits!(connection, "the language server ended")
    nothing
end

# Give each request that waits an answer that says why no answer comes.
function _end_language_server_waits!(connection::LanguageServerConnection, reason::AbstractString)
    waits = lock(connection.state_lock) do
        found = collect(values(connection.waits))
        empty!(connection.waits)
        found
    end
    for wait in waits
        put!(wait, LanguageServerException(reason))
    end
end

"""
    send_language_server_request!(connection, method, parameters; timeout) -> Any

Send the request `method` with `parameters` to the server, and wait for its
answer: the `result` of the answer, as dictionaries, vectors and plain values.
It waits, so call it off the loop of the editor.

Throws a `LanguageServerException` when the server answers with an error,
gives no answer in `timeout` seconds, or ends.
"""
function send_language_server_request!(connection::LanguageServerConnection, method::AbstractString,
                                       parameters; timeout::Real = LANGUAGE_SERVER_REQUEST_TIMEOUT,
                                       started::Bool = false)
    started || start_language_server!(connection)
    # Two places can put into the wait: the reader, or the end of the server,
    # which take the wait out of `waits` under the lock, so only one of them does;
    # and the timer. So two places never block.
    wait = Channel{Any}(2)
    id = lock(connection.state_lock) do
        connection.running || throw(LanguageServerException("the language server ended"))
        connection.next_id += 1
        connection.waits[connection.next_id] = wait
        connection.next_id
    end
    timer = Timer(_ -> put!(wait, LanguageServerException(
                      "the language server gave no answer to $method in $timeout s")), timeout)
    answer = try
        _write_language_server_message!(connection, _make_language_server_message("id" => id, "method" => method;
                                                                                  parameters))
        take!(wait)
    finally
        close(timer)
        lock(() -> delete!(connection.waits, id), connection.state_lock)
    end
    answer isa LanguageServerException && throw(answer)
    error = get(answer, "error", nothing)
    error === nothing ||
        throw(LanguageServerException("the language server answered $method with an error: " *
                                      string(get(error, "message", error))))
    get(answer, "result", nothing)
end

"""
    send_language_server_notification!(connection, method, parameters)

Send the notification `method` with `parameters` to the server. A notification
has no answer, so it does not wait.
"""
function send_language_server_notification!(connection::LanguageServerConnection, method::AbstractString,
                                            parameters)
    _write_language_server_message!(connection, _make_language_server_message("method" => method; parameters))
    nothing
end

# A message of the protocol with `fields`, and `params` when there are parameters:
# some servers refuse a `params` of `null`.
function _make_language_server_message(fields::Pair...; parameters = nothing)
    message = Dict{String, Any}("jsonrpc" => "2.0", fields...)
    parameters === nothing || (message["params"] = parameters)
    message
end

"""
    make_file_uri(path) -> String

The `file:` URI of the absolute path `path`, as a language server names a
file: each byte that is not a letter, a digit, `-`, `.`, `_`, `~` or `/` is
written as `%` and two hexadecimal digits.

# Example

    make_file_uri("/home/me/my file.cc")   # "file:///home/me/my%20file.cc"
"""
function make_file_uri(path::AbstractString)
    io = IOBuffer()
    print(io, "file://")
    for byte in codeunits(String(path))
        character = Char(byte)
        if byte < 0x80 && (isletter(character) || isdigit(character) || character in "-._~/")
            print(io, character)
        else
            print(io, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    String(take!(io))
end

function _write_language_server_message!(connection::LanguageServerConnection, message)
    body = JSON3.write(message)
    input = lock(() -> connection.input, connection.state_lock)
    input === nothing && throw(LanguageServerException("the language server ended"))
    lock(connection.write_lock) do
        try
            write(input, "Content-Length: ", string(sizeof(body)), "\r\n\r\n", body)
            flush(input)
        catch exception
            exception isa Base.IOError || rethrow()
            throw(LanguageServerException("the language server ended"))
        end
    end
    nothing
end

# The task that reads the messages of the server until its output ends: it gives
# each answer to the request that waits for it, answers a request of the server
# with "method not found", and drops a notification.
function _read_language_server_messages(connection::LanguageServerConnection, output::IO)
    try
        while true
            message = _read_language_server_message(output)
            message === nothing && break
            _receive_language_server_message!(connection, message)
        end
    catch exception
        exception isa Base.IOError || exception isa EOFError || rethrow()
    finally
        lock(() -> connection.running = false, connection.state_lock)
        _end_language_server_waits!(connection, "the language server ended")
    end
    nothing
end

# One message: the headers up to an empty line, then as many bytes as
# `Content-Length` says. `nothing` at the end of the stream.
function _read_language_server_message(output::IO)
    content_length = nothing
    while true
        eof(output) && return nothing
        line = rstrip(readline(output), '\r')
        isempty(line) && content_length !== nothing && break
        isempty(line) && continue
        name, value = strip.(split(line, ':'; limit = 2))
        lowercase(name) == "content-length" && (content_length = parse(Int, value))
    end
    JSON3.read(String(read(output, content_length)), Dict{String, Any})
end

function _receive_language_server_message!(connection::LanguageServerConnection, message::AbstractDict)
    id = get(message, "id", nothing)
    if haskey(message, "method")
        # A request of the server: no method of the server is one that this client
        # serves, so the answer is an error. A notification gets no answer.
        id === nothing || _write_language_server_message!(connection, _make_language_server_message(
            "id" => id, "error" => Dict("code" => -32601, "message" => "method not found")))
    elseif id isa Integer
        wait = lock(() -> pop!(connection.waits, Int(id), nothing), connection.state_lock)
        wait === nothing || put!(wait, message)
    end
    nothing
end

"""
    stop_language_server!(connection)

Stop the server of `connection`: ask it to shut down, tell it to exit, and kill
its process when it does not end in a short wait. A connection whose server
never started stops at once. The connection does not start again.
"""
function stop_language_server!(connection::LanguageServerConnection)
    if is_language_server_running(connection)
        try
            send_language_server_request!(connection, "shutdown", nothing;
                                          timeout = LANGUAGE_SERVER_STOP_TIMEOUT, started = true)
            send_language_server_notification!(connection, "exit", nothing)
        catch exception
            exception isa LanguageServerException || rethrow()
        end
        process = lock(() -> connection.process, connection.state_lock)
        process === nothing ||
            timedwait(() -> process_exited(process), LANGUAGE_SERVER_STOP_TIMEOUT; pollint = 0.01)
    end
    lock(connection.state_lock) do
        connection.failure === nothing &&
            (connection.failure = LanguageServerException("the language server was stopped"))
    end
    _close_language_server_streams!(connection)
end
