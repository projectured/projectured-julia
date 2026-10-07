# Fragment of `AcpModule` — JSON-RPC 2.0 over two streams, one message on each
# line: the requests and notifications of the client, the reader task that
# hands each message of the agent to its place, and the end of the process of
# the agent.

"""
    AcpRequestException(code, message)

The error answer of a JSON-RPC request: the agent answered `method` with an
error, or the agent ended before it answered. The client throws it for the
requests it sends, and a handler throws it to answer a request of the agent with
an error.
"""
struct AcpRequestException <: Exception
    code::Int
    message::String
end

Base.showerror(io::IO, exception::AcpRequestException) =
    print(io, "AcpRequestException: ", exception.message, " (code ", exception.code, ")")

# The JSON-RPC codes that this client answers with.
const ACP_METHOD_NOT_FOUND = -32601
const ACP_INTERNAL_ERROR = -32603

"""
    AcpTransport

The two streams to an agent, and the state of the JSON-RPC exchange on them:
the id of the next request, the requests that wait for an answer, and the task
that reads what the agent writes.

`on_notification(method, params)` gets each notification of the agent, on the
reader task and in the order the agent wrote them, so a handler must not wait.
`on_request(method, params)` answers each request of the agent with a result,
or throws an `AcpRequestException`. It runs on a task of its own, so it can
wait for a person.
"""
mutable struct AcpTransport
    input::IO
    output::IO
    process::Union{Nothing,Base.Process}
    on_notification::Function
    on_request::Function
    write_lock::ReentrantLock
    pending_lock::ReentrantLock
    pending::Dict{Int,Channel{Dict{String,Any}}}
    next_id::Int
    is_closed::Bool
    reader::Union{Nothing,Task}
end

"""
    open_acp_transport(input, output; process = nothing, on_notification, on_request)
    open_acp_transport(command::Cmd; on_notification, on_request)

Open a transport on two streams: the client writes to `input` and reads from
`output`. The second method starts `command` as the agent, in a process group of
its own, and opens the transport on its standard input and output. The agent's
standard error goes to the debug log.
"""
function open_acp_transport(input::IO, output::IO;
                            process::Union{Nothing,Base.Process} = nothing,
                            on_notification::Function, on_request::Function)
    transport = AcpTransport(input, output, process, on_notification, on_request,
                             ReentrantLock(), ReentrantLock(),
                             Dict{Int,Channel{Dict{String,Any}}}(), 0, false, nothing)
    transport.reader = errormonitor(@async _read_acp_messages(transport))
    transport
end

function open_acp_transport(command::Cmd; on_notification::Function, on_request::Function)
    errors = Pipe()
    process = open(pipeline(command; stderr = errors), "r+")
    close(errors.in)
    errormonitor(@async _read_agent_errors(errors))
    open_acp_transport(process.in, process.out; process, on_notification, on_request)
end

# The standard error of an agent holds its own log. It goes to the debug log, so
# a person who asks for it sees it, and nobody else does.
function _read_agent_errors(errors::IO)
    for line in eachline(errors)
        @debug "agent" line
    end
end

"""
    send_acp_request(transport, method, params; timeout = Inf) -> result

Send a request and wait for its answer. Answers the `result` of the answer, and
throws an `AcpRequestException` for an `error`, or when the agent ends first. A
finite `timeout`, in seconds, throws an error when the agent does not answer in
time.
"""
function send_acp_request(transport::AcpTransport, method::AbstractString, params;
                          timeout::Real = Inf)
    channel = Channel{Dict{String,Any}}(1)
    id = lock(transport.pending_lock) do
        transport.next_id += 1
        transport.pending[transport.next_id] = channel
        transport.next_id
    end
    try
        _write_acp_message(transport, Dict{String,Any}(
            "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params))
        if isfinite(timeout)
            timedwait(() -> isready(channel), Float64(timeout); pollint = 0.05) === :ok ||
                error("The agent did not answer `$(method)` in $(timeout) s.")
        end
        answer = take!(channel)
        if haskey(answer, "error")
            error_ = answer["error"]
            throw(AcpRequestException(Int(get(error_, "code", ACP_INTERNAL_ERROR)),
                                      string(get(error_, "message", "the agent answered an error"))))
        end
        get(answer, "result", nothing)
    finally
        lock(() -> delete!(transport.pending, id), transport.pending_lock)
    end
end

"""
    send_acp_notification(transport, method, params)

Send a notification, which has no answer.
"""
send_acp_notification(transport::AcpTransport, method::AbstractString, params) =
    _write_acp_message(transport, Dict{String,Any}(
        "jsonrpc" => "2.0", "method" => method, "params" => params))

"""
    close_acp_transport!(transport) -> transport

Close the transport. The input of the agent closes, so an agent ends at the end
of its input. A process that still runs after five seconds gets `SIGTERM`, and
after two more `SIGKILL`, sent to its whole process group, so no child of the
agent lives on. Each request that waits for an answer throws.
"""
function close_acp_transport!(transport::AcpTransport)
    transport.is_closed && return transport
    transport.is_closed = true
    lock(transport.write_lock) do
        try
            close(transport.input)
        catch exception
            exception isa Base.IOError || rethrow()
        end
    end
    process = transport.process
    if process !== nothing && timedwait(() -> process_exited(process), 5.0) !== :ok
        _signal_process_group(process, Base.SIGTERM)
        timedwait(() -> process_exited(process), 2.0) === :ok ||
            _signal_process_group(process, Base.SIGKILL)
    end
    _fail_waiting_requests!(transport)
    transport
end

# The agent starts in a process group of its own, so the group is the agent and
# every process it started.
function _signal_process_group(process::Base.Process, signal::Integer)
    process_exited(process) && return nothing
    if Sys.isunix()
        ccall(:kill, Cint, (Cint, Cint), -getpid(process), signal)
    else
        kill(process, signal)
    end
    nothing
end

# Each request that waits gets an error answer, so its sender throws.
function _fail_waiting_requests!(transport::AcpTransport)
    channels = lock(() -> collect(values(transport.pending)), transport.pending_lock)
    for channel in channels
        isready(channel) || put!(channel, Dict{String,Any}("error" => Dict{String,Any}(
            "code" => ACP_INTERNAL_ERROR, "message" => "The agent ended before it answered.")))
    end
end

function _write_acp_message(transport::AcpTransport, message::Dict{String,Any})
    text = JSON3.write(message)
    lock(transport.write_lock) do
        transport.is_closed && error("The connection to the agent is closed.")
        write(transport.input, text, '\n')
        flush(transport.input)
    end
    nothing
end

# Read one message on each line until the agent closes its output. A line that
# is not JSON is dropped with a warning that does not quote it.
function _read_acp_messages(transport::AcpTransport)
    try
        while true
            line = readline(transport.output)
            if isempty(line)
                eof(transport.output) && break
                continue
            end
            message = try
                _make_plain(JSON3.read(line))
            catch exception
                exception isa ArgumentError || rethrow()
                @warn "An agent wrote a line that is not JSON."
                continue
            end
            message isa Dict{String,Any} && _dispatch_acp_message(transport, message)
        end
    catch exception
        transport.is_closed || @warn "The reader of an agent stopped." exception
    finally
        _fail_waiting_requests!(transport)
    end
end

function _dispatch_acp_message(transport::AcpTransport, message::Dict{String,Any})
    if haskey(message, "method")
        method = string(message["method"])
        params = get(message, "params", nothing)
        params isa Dict{String,Any} || (params = Dict{String,Any}())
        if haskey(message, "id")
            id = message["id"]
            errormonitor(@async _answer_acp_request(transport, id, method, params))
        else
            try
                transport.on_notification(method, params)
            catch exception
                @warn "A notification of an agent failed." method exception
            end
        end
    elseif haskey(message, "id")
        channel = lock(() -> get(transport.pending, message["id"], nothing), transport.pending_lock)
        channel === nothing || isready(channel) || put!(channel, message)
    end
    nothing
end

function _answer_acp_request(transport::AcpTransport, id, method::String, params::Dict{String,Any})
    answer = try
        Dict{String,Any}("jsonrpc" => "2.0", "id" => id,
                         "result" => transport.on_request(method, params))
    catch exception
        failure = exception isa AcpRequestException ? exception :
                  AcpRequestException(ACP_INTERNAL_ERROR, "The client failed to answer `$(method)`.")
        exception isa AcpRequestException ||
            @warn "A request of an agent failed." method exception
        Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "error" => Dict{String,Any}(
            "code" => failure.code, "message" => failure.message))
    end
    transport.is_closed || _write_acp_message(transport, answer)
    nothing
end

# JSON3 reads an object as a `JSON3.Object` with `Symbol` keys. The rest of the
# client works with plain values: a `Dict{String,Any}`, a `Vector{Any}`, a
# string, a number, a `Bool` or `nothing`.
_make_plain(value::JSON3.Object) =
    Dict{String,Any}(String(key) => _make_plain(item) for (key, item) in pairs(value))
_make_plain(value::JSON3.Array) = Any[_make_plain(item) for item in value]
_make_plain(value::AbstractString) = String(value)
_make_plain(value) = value
