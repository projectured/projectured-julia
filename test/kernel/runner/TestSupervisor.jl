# ============================================================================
# The supervisor of the worker processes of the runner of the suites.
#
# It uses Base only: `tool/run-tests.jl` includes this file and loads no
# package, so the supervisor starts at once and a fault of a part can not end
# it. ProjecturedKernelTest includes the same file, so its tests run it.
#
# Each worker runs `run_test_worker()` (TestWorker.jl) and answers on its
# standard output with lines that start with the prefix below. The supervisor
# gives each part the time limit of its entry or of the run. At the limit it
# asks the worker for its stacks (SIGUSR1), stops it, records `timeout`, and
# starts a new worker for the next part. A worker over its memory gets the
# result `memory`, and a worker that ends during a part the result `crash`.
# ============================================================================

const _SUPERVISOR_PREFIX = "@@test-worker@@\t"

# The seconds between the request for the stacks and the stop of a worker.
const _STACKS_SECONDS = 5.0

"""
    TestRunOptions

The options of a run of [`run_test_supervisor`](@ref), with their defaults:
`project`, the environment of the workers (the active project);
`threads`, the threads of each worker (2); `memory_bytes`, the memory that a
worker may use (6 GiB); `limit`, the seconds of a part that names no limit of its
own (600); `only` and `skip`, the filters in the form of the command line;
`record`, the path of the record file (none); and `suites`, the pairs of a
package and the name of a suite in it.
"""
Base.@kwdef mutable struct TestRunOptions
    project::String = something(Base.active_project(), "")
    threads::Int = 2
    memory_bytes::Int = 6 * 2^30
    limit::Float64 = 600.0
    only::String = ""
    skip::String = ""
    record::String = ""
    suites::Vector{Tuple{String, String}} = Tuple{String, String}[]
end

const _RUN_TESTS_USAGE = """
    usage: julia --project=ENVIRONMENT tool/run-tests.jl [options] PACKAGE SUITE [PACKAGE SUITE ...]

    Run each part of each SUITE of PACKAGE in a worker process, with a time limit
    and a memory limit for each part. A PACKAGE that ends with .jl is a file that
    the worker includes; its module has the name of the file.

    options:
      --project PATH   the environment of the workers (default: the active project)
      --threads N      the threads of each worker (default: 2)
      --memory SIZE    the memory of a worker, such as 6G or 800M (default: 6G)
      --limit SECONDS  the time of a part that names no limit of its own (default: 600)
      --only TEXT      run only the parts whose name holds TEXT; r"…" is a Regex
      --skip TEXT      leave out the parts whose name holds TEXT; r"…" is a Regex
      --record PATH    add one line of tab-separated values for each part to PATH
    """

function _read_size(text::AbstractString)
    m = match(r"^(\d+(?:\.\d+)?)([KMG]?)$", uppercase(text))
    m === nothing && error("no size: $text")
    factor = Dict("" => 1, "K" => 2^10, "M" => 2^20, "G" => 2^30)[m.captures[2]]
    round(Int, parse(Float64, m.captures[1]) * factor)
end

"""
    read_test_run_options(arguments) -> TestRunOptions

The options of the command line of `tool/run-tests.jl`.
"""
function read_test_run_options(arguments::AbstractVector{<:AbstractString})
    options = TestRunOptions()
    words = String.(arguments)
    rest = String[]
    k = 1
    while k <= length(words)
        word = words[k]
        if startswith(word, "--")
            k == length(words) && error("$word needs a value")
            value = words[k + 1]
            word == "--project" ? (options.project = value) :
            word == "--threads" ? (options.threads = parse(Int, value)) :
            word == "--memory" ? (options.memory_bytes = _read_size(value)) :
            word == "--limit" ? (options.limit = parse(Float64, value)) :
            word == "--only" ? (options.only = value) :
            word == "--skip" ? (options.skip = value) :
            word == "--record" ? (options.record = value) :
            error("no option $word")
            k += 2
        else
            push!(rest, word)
            k += 1
        end
    end
    isodd(length(rest)) && error("each PACKAGE needs a SUITE")
    options.suites = [(rest[i], rest[i + 1]) for i in 1:2:length(rest)]
    options
end

# A part that the supervisor gives to a worker.
struct _QueuedPart
    package::String
    suite::String
    index::String
    path::String
    name::String
    limit::Float64
end

_part_place(part::_QueuedPart) = part.path * "/" * part.name

mutable struct _Worker
    number::Int
    process::Base.Process
    loaded::Set{String}
    part::Union{_QueuedPart, Nothing}
    started::Float64            # when the part started to run, or 0 while it loads
    stop::String                # the result of a stop that the supervisor started
    stop_time::Float64
    is_ending::Bool             # stopped: its answers count no more
    is_ended::Bool
end

function _worker_command(options::TestRunOptions)
    script = "redirect_stderr(stdout); using ProjecturedKernelTest; run_test_worker(); " *
             "ccall(:_exit, Cvoid, (Cint,), 0)"
    hint = string(div(options.memory_bytes * 4, 5 * 2^20), "M")
    flags = ["--startup-file=no", "-t", string(options.threads), "--project=$(options.project)",
             "--heap-size-hint=$hint", "-e", script]
    `$(Base.julia_cmd()) $flags`
end

function _start_worker(number::Int, options::TestRunOptions, events::Channel, output::IO,
                       is_prefixed::Bool)
    process = open(_worker_command(options), "r+")
    worker = _Worker(number, process, Set{String}(), nothing, 0.0, "", 0.0, false, false)
    errormonitor(@async begin
        for line in eachline(process)
            if startswith(line, _SUPERVISOR_PREFIX)
                fields = String.(split(line[length(_SUPERVISOR_PREFIX) + 1:end], '\t'))
                put!(events, (number, fields))
            else
                println(output, is_prefixed ? "[w$number] " : "", line)
            end
        end
        wait(process)
        put!(events, (number, ["ended"]))
    end)
    worker
end

_send(worker::_Worker, fields...) =
    (println(worker.process, join(fields, '\t')); flush(worker.process))

# Stop `worker`: its answers from now on count no more, and the loop starts a
# new worker after it ends.
function _stop_worker!(worker::_Worker, signal::Integer = Base.SIGKILL)
    worker.is_ending = true
    process_running(worker.process) && kill(worker.process, signal)
end

# The resident memory of a process in bytes, or 0 where no `/proc` tells it.
function _resident_bytes(process::Base.Process)
    path = "/proc/$(getpid(process))/status"
    isfile(path) || return 0
    for line in eachline(path)
        startswith(line, "VmRSS:") && return parse(Int, split(line)[2]) * 1024
    end
    0
end

"""
    run_test_supervisor(arguments; output = stdout) -> Int

Run the suites that `arguments` name, as `tool/run-tests.jl` reads them, in
worker processes; print the output of the workers and a summary to `output`; and
give the exit code: 0 when each part ended and passed, 1 when not, and 2 when the
run could not start.
"""
function run_test_supervisor(arguments::AbstractVector{<:AbstractString}; output::IO = stdout)
    any(in(("--help", "-h")), arguments) && (println(output, _RUN_TESTS_USAGE); return 0)
    options = try
        read_test_run_options(arguments)
    catch error
        println(output, sprint(showerror, error), "\n", _RUN_TESTS_USAGE)
        return 2
    end
    isempty(options.suites) && (println(output, _RUN_TESTS_USAGE); return 2)
    run_test_supervisor(options; output)
end

function run_test_supervisor(options::TestRunOptions; output::IO = stdout)
    events = Channel{Tuple{Int, Vector{String}}}(Inf)
    ticker = Timer(_ -> put!(events, (0, ["tick"])), 1.0; interval = 1.0)
    workers = _Worker[]
    columns = String[]
    records = Dict{String, String}[]
    try
        push!(workers, _start_worker(1, options, events, output, false))
        queue = _list_queued_parts(first(workers), options, events, columns, output)
        queue === nothing && return 2
        _run_queued_parts!(workers, queue, options, events, columns, records, output)
        _print_summary(output, records)
        all(r -> r["result"] == "done" && r["fail"] == "0" && r["error"] == "0", records) ? 0 : 1
    finally
        close(ticker)
        for worker in workers
            process_running(worker.process) || continue
            try
                _send(worker, "quit")
            catch
            end
            timedwait(() -> !process_running(worker.process), 10.0)
            process_running(worker.process) && kill(worker.process, Base.SIGKILL)
        end
    end
end

# The next answer of `worker` whose first field is in `kinds`, with the
# answers of other kinds given to `seen`; `nothing` when the worker ends first.
function _wait_answer(seen, worker::_Worker, events::Channel, kinds)
    while true
        number, fields = take!(events)
        number == worker.number || continue
        kind = first(fields)
        kind in kinds && return fields
        kind == "ended" && return nothing
        seen(fields)
    end
end

_answer_text(fields) = fields === nothing ? "the worker ended" : join(fields[2:end], " ")

function _list_queued_parts(worker::_Worker, options::TestRunOptions, events::Channel,
                            columns::Vector{String}, output::IO)
    keep_columns(fields) = fields[1] == "columns" && append!(columns, fields[2:end])
    if _wait_answer(keep_columns, worker, events, ("ready",)) === nothing
        println(output, "The first worker ended before it was ready.")
        return nothing
    end
    queue = _QueuedPart[]
    for (package, suite) in options.suites
        if !(package in worker.loaded)
            _send(worker, "load", package)
            fields = _wait_answer(_ -> nothing, worker, events, ("loaded", "failed"))
            if fields === nothing || fields[1] == "failed"
                println(output, "The worker could not load $package: ", _answer_text(fields))
                return nothing
            end
            push!(worker.loaded, package)
            println(output, "Loaded $package in $(fields[3]) s.")
        end
        _send(worker, "list", package, suite, options.only, options.skip)
        while true
            fields = _wait_answer(_ -> nothing, worker, events, ("part", "listed", "failed"))
            if fields === nothing || fields[1] == "failed"
                println(output, "The worker could not list $package.$suite: ", _answer_text(fields))
                return nothing
            end
            fields[1] == "listed" && break
            limit = parse(Float64, fields[5])
            push!(queue, _QueuedPart(package, suite, fields[2], fields[3], fields[4],
                                     limit > 0 ? limit : options.limit))
        end
    end
    println(output, "$(length(queue)) parts to run.")
    queue
end

function _give_part!(worker::_Worker, part::_QueuedPart)
    worker.part = part
    worker.stop = ""
    if part.package in worker.loaded
        worker.started = time()
    else
        worker.started = 0.0
        _send(worker, "load", part.package)
    end
    _send(worker, "run", part.package, part.suite, part.index)
end

function _run_queued_parts!(workers, queue, options, events, columns, records, output)
    next = 1
    is_prefixed = length(workers) > 1
    while true
        for (k, worker) in enumerate(workers)
            if worker.is_ended && next <= length(queue)
                workers[k] = worker = _start_worker(worker.number, options, events, output,
                                                    is_prefixed)
            end
            if !worker.is_ending && worker.part === nothing && next <= length(queue)
                _give_part!(worker, queue[next])
                next += 1
            end
        end
        all(w -> w.part === nothing, workers) && next > length(queue) && return
        number, fields = take!(events)
        kind = first(fields)
        if kind == "tick"
            _check_workers!(workers, options, output)
            continue
        end
        worker = workers[findfirst(w -> w.number == number, workers)]
        if kind == "ended"
            worker.is_ended = true
            worker.is_ending = true
            if worker.part !== nothing
                result = !isempty(worker.stop) ? worker.stop :
                         worker.process.termsignal == Base.SIGKILL ? "memory" : "crash"
                println(output, "The worker ended during $(_part_place(worker.part)): $result.")
                _keep_record!(records, _stopped_record(worker, result, columns), columns, options)
                worker.part = nothing
            end
        elseif worker.is_ending
            continue                                     # the answer of a stopped worker
        elseif kind == "loaded"
            push!(worker.loaded, fields[2])
            worker.part === nothing || (worker.started = time())
        elseif kind == "record" && worker.part !== nothing
            _keep_record!(records, Dict(zip(columns, fields[2:end])), columns, options)
            worker.part = nothing
        elseif kind == "failed" && worker.part !== nothing
            println(output, "The part $(_part_place(worker.part)) did not run: ",
                    join(fields[2:end], " "))
            worker.stop = "crash"
            _stop_worker!(worker)
        end
    end
end

function _check_workers!(workers, options::TestRunOptions, output::IO)
    now = time()
    for worker in workers
        (worker.is_ended || worker.part === nothing || worker.started == 0.0) && continue
        place = _part_place(worker.part)
        if isempty(worker.stop)
            if now - worker.started > worker.part.limit
                seconds = round(Int, worker.part.limit)
                println(output, "The part $place takes more than $seconds s; ",
                        "its stacks follow, then the worker stops.")
                worker.stop = "timeout"
                worker.stop_time = now
                _stop_worker!(worker, 10)                # SIGUSR1: Julia prints its stacks
            elseif _resident_bytes(worker.process) > options.memory_bytes
                println(output, "The part $place uses more than ",
                        "$(div(options.memory_bytes, 2^20)) MiB; the worker stops.")
                worker.stop = "memory"
                worker.stop_time = now
                _stop_worker!(worker)
            end
        elseif now - worker.stop_time >= _STACKS_SECONDS
            _stop_worker!(worker)
        end
    end
end

function _stopped_record(worker::_Worker, result::String, columns::Vector{String})
    part = worker.part
    values = Dict(column => "0" for column in columns)
    for column in ("repository", "commit")
        values[column] = ""
    end
    values["suite"] = part.path
    values["part"] = part.name
    values["result"] = result
    seconds = worker.started == 0.0 ? 0.0 : time() - worker.started
    values["seconds"] = string(round(seconds; digits = 3))
    values
end

function _keep_record!(records, values::Dict, columns::Vector{String}, options::TestRunOptions)
    push!(records, values)
    isempty(options.record) && return
    is_new = !isfile(options.record) || filesize(options.record) == 0
    open(options.record, "a") do io
        is_new && println(io, join(columns, '\t'))
        println(io, join((get(values, column, "") for column in columns), '\t'))
    end
end

function _print_summary(output::IO, records)
    total(kind) = sum((parse(Int, get(r, kind, "0")) for r in records); init = 0)
    results = Dict{String, Int}()
    for r in records
        results[r["result"]] = get(results, r["result"], 0) + 1
    end
    result_text = join(("$n $result" for (result, n) in sort(collect(results))), ", ")
    println(output, "Summary: $(length(records)) parts ($result_text); ",
            "$(total("pass")) pass, $(total("fail")) fail, $(total("error")) error, ",
            "$(total("broken")) broken.")
    bad = [r for r in records if r["result"] != "done" || r["fail"] != "0" || r["error"] != "0"]
    if !isempty(bad)
        println(output, "The parts that did not pass:")
        for r in bad
            what = r["result"] == "done" ? "$(r["fail"]) fail, $(r["error"]) error" : r["result"]
            println(output, "  ", rpad(what, 18), r["suite"], "/", r["part"])
        end
    end
    slowest = first(sort(records; by = r -> parse(Float64, r["seconds"]), rev = true), 10)
    println(output, "The $(length(slowest)) slowest parts:")
    for r in slowest
        seconds = string(round(parse(Float64, r["seconds"]); digits = 1), " s")
        println(output, lpad(seconds, 10), "  ", r["suite"], "/", r["part"])
    end
end
