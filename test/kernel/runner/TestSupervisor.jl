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

include("GitText.jl")

const _SUPERVISOR_PREFIX = "@@test-worker@@\t"

# The seconds between the request for the stacks and the stop of a worker.
const _STACKS_SECONDS = 5.0

"""
    TestRunOptions

The options of a run of [`run_test_supervisor`](@ref), with their defaults:
`project`, the environment of the workers (the active project);
`threads`, the threads of each worker (2); `workers`, the count of the worker
processes (1); `memory_bytes`, the memory that a
worker may use (6 GiB); `limit`, the seconds of a part that names no limit of its
own (600); `only` and `skip`, the filters in the form of the command line;
`changed`, a base commit whose changes choose the parts (none); `level`, the level
of the parts (`all`, `fast` or `slow`; `all`);
`record`, the path of the record file (none); `stay` and `send`, the folder of
the requests of a session ([`run_test_session`](@ref)), to keep a worker open or to
send it a request (none); `restart`, a request that starts new workers first;
`stop`, a request that ends the session; and `suites`, the pairs of a package
and the name of a suite in it.
"""
Base.@kwdef mutable struct TestRunOptions
    project::String = something(Base.active_project(), "")
    threads::Int = 2
    workers::Int = 1
    memory_bytes::Int = 6 * 2^30
    limit::Float64 = 600.0
    only::String = ""
    skip::String = ""
    changed::String = ""
    level::String = "all"
    record::String = ""
    stay::String = ""
    send::String = ""
    restart::Bool = false
    stop::Bool = false
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
      --workers N      the worker processes that run parts at the same time (default: 1),
                       at most the usable CPUs divided by the threads of a worker
      --memory SIZE    the memory of a worker, such as 6G or 800M (default: 6G)
      --limit SECONDS  the time of a part that names no limit of its own (default: 600)
      --only TEXT      run only the parts whose name holds TEXT; r"…" is a Regex
      --skip TEXT      leave out the parts whose name holds TEXT; r"…" is a Regex
      --changed BASE   run only the parts that the changes since the commit BASE reach
      --level LEVEL    run only the fast parts (fast), only the slow ones (slow), or all (all)
      --record PATH    add one line of tab-separated values for each part to PATH
      --stay FOLDER    keep the workers open, with Revise, and run each request that
                       FOLDER/requests receives, before each one with the changes of the files
      --send FOLDER    send the other arguments to the session of FOLDER as a request,
                       wait for its end, print its output and give its exit code
      --restart        (a request) start new workers before the run
      --stop           (a request) end the session
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
        if word in ("--restart", "--stop")
            word == "--restart" ? (options.restart = true) : (options.stop = true)
            k += 1
        elseif startswith(word, "--")
            k == length(words) && error("$word needs a value")
            value = words[k + 1]
            word == "--project" ? (options.project = value) :
            word == "--threads" ? (options.threads = parse(Int, value)) :
            word == "--workers" ? (options.workers = parse(Int, value)) :
            word == "--memory" ? (options.memory_bytes = _read_size(value)) :
            word == "--limit" ? (options.limit = parse(Float64, value)) :
            word == "--only" ? (options.only = value) :
            word == "--skip" ? (options.skip = value) :
            word == "--changed" ? (options.changed = value) :
            word == "--level" ? (options.level = value) :
            word == "--record" ? (options.record = value) :
            word == "--stay" ? (options.stay = value) :
            word == "--send" ? (options.send = value) :
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
    is_alone::Bool
    is_retry::Bool
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
    # A worker of a session loads Revise first, when the environment has it, so
    # that Revise follows the files of the packages after it.
    revise = isempty(options.stay) ? "" : "try; using Revise; catch; end; "
    script = "redirect_stderr(stdout); $(revise)using ProjecturedKernelTest; run_test_worker(); " *
             "ccall(:_exit, Cvoid, (Cint,), 0)"
    hint = string(div(options.memory_bytes * 4, 5 * 2^20), "M")
    flags = ["--startup-file=no", "-t", string(options.threads), "--project=$(options.project)",
             "--heap-size-hint=$hint", "-e", script]
    `$(Base.julia_cmd()) $flags`
end

# Start a worker whose output goes to `sink[]`, the stream of the run at that time.
function _start_worker(number::Int, options::TestRunOptions, events::Channel,
                       sink::Base.RefValue{IO}, is_prefixed::Bool)
    process = open(_worker_command(options), "r+")
    worker = _Worker(number, process, Set{String}(), nothing, 0.0, "", 0.0, false, false)
    errormonitor(@async begin
        for line in eachline(process)
            if startswith(line, _SUPERVISOR_PREFIX)
                fields = String.(split(line[length(_SUPERVISOR_PREFIX) + 1:end], '\t'))
                put!(events, (number, fields))
            else
                println(sink[], is_prefixed ? "[w$number] " : "", line)
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

# The CPUs that this process may use: those of its affinity where `/proc` tells
# them, or else all of the machine.
function _usable_cpus()
    path = "/proc/self/status"
    if isfile(path)
        for line in eachline(path)
            startswith(line, "Cpus_allowed_list:") || continue
            count = 0
            for range in split(strip(split(line, ':')[2]), ',')
                bounds = parse.(Int, split(range, '-'))
                count += last(bounds) - first(bounds) + 1
            end
            return count
        end
    end
    Sys.CPU_THREADS
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
    isempty(options.stay) || return run_test_session(options; output)
    isempty(options.send) || return send_test_request(options.send, arguments; output)
    isempty(options.suites) && (println(output, _RUN_TESTS_USAGE); return 2)
    run_test_supervisor(options; output)
end

function run_test_supervisor(options::TestRunOptions; output::IO = stdout)
    events = Channel{Tuple{Int, Vector{String}}}(Inf)
    ticker = Timer(_ -> put!(events, (0, ["tick"])), 1.0; interval = 1.0)
    sink = Ref{IO}(output)
    workers = _Worker[]
    columns = String[]
    try
        push!(workers, _start_worker(1, options, events, sink, options.workers > 1))
        _wait_ready(first(workers), events, columns) ||
            (println(output, "The first worker ended before it was ready."); return 2)
        _run_request!(workers, options, events, columns, sink, output)
    finally
        close(ticker)
        _end_workers(workers)
    end
end

function _end_workers(workers)
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

# The answers "columns" and "ready" of a new worker; false when it ends first.
_wait_ready(worker::_Worker, events::Channel, columns::Vector{String}) =
    _wait_answer(f -> f[1] == "columns" && isempty(columns) && append!(columns, f[2:end]),
                 worker, events, ("ready",)) !== nothing

# One run with the open `workers`: list the parts with the first, start the other
# workers, run the parts, print the summary, store or compare the records, and
# give the exit code.
function _run_request!(workers, options, events, columns, sink, output)
    records = Dict{String, String}[]
    queue = _list_queued_parts(first(workers), options, events, columns, output)
    queue === nothing && return 2
    most = max(1, div(_usable_cpus(), options.threads))
    if options.workers > most
        println(output, "$(options.workers) workers need more CPUs than the $(_usable_cpus()) ",
                "that this process may use; $most run.")
    end
    count = min(options.workers, most, max(1, length(queue)))
    for number in length(workers) + 1:count
        push!(workers, _start_worker(number, options, events, sink, true))
    end
    _run_queued_parts!(workers, queue, options, events, columns, records, sink, output)
    _print_summary(output, records)
    root = _git_text(pwd(), `rev-parse --show-toplevel`)
    isempty(root) || store_and_compare_records(records, columns, root; output)
    all(r -> r["result"] == "done" && r["fail"] == "0" && r["error"] == "0", records) ? 0 : 1
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
        _send(worker, "list", package, suite, options.only, options.skip, options.changed,
              options.level)
        while true
            fields = _wait_answer(_ -> nothing, worker, events, ("part", "listed", "failed"))
            if fields === nothing || fields[1] == "failed"
                println(output, "The worker could not list $package.$suite: ", _answer_text(fields))
                return nothing
            end
            fields[1] == "listed" && break
            limit = parse(Float64, fields[5])
            push!(queue, _QueuedPart(package, suite, fields[2], fields[3], fields[4],
                                     limit > 0 ? limit : options.limit, fields[6] == "true",
                                     false))
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

# Each worker that runs no part takes the next part of the queue, in its order.
# A part that runs alone waits until no other part runs, and no part starts
# beside it.
function _run_queued_parts!(workers, queue, options, events, columns, records, sink, output)
    next = 1
    is_prefixed = length(workers) > 1
    while true
        for (k, worker) in enumerate(workers)
            if worker.is_ended && next <= length(queue)
                workers[k] = worker = _start_worker(worker.number, options, events, sink,
                                                    is_prefixed)
            end
            next <= length(queue) || continue
            (worker.is_ending || worker.part !== nothing) && continue
            is_alone_running = any(w -> w.part !== nothing && w.part.is_alone, workers)
            is_others_running = any(w -> w.part !== nothing, workers)
            is_alone_running && break
            queue[next].is_alone && is_others_running && break
            _give_part!(worker, queue[next])
            next += 1
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
                part = worker.part
                result = !isempty(worker.stop) ? worker.stop :
                         worker.process.termsignal == Base.SIGKILL ? "memory" : "crash"
                if result == "memory" && !part.is_retry
                    # A worker grows with each part that it runs, so the part that it
                    # ran at the stop is not always the cause: it runs once more, first
                    # in a new worker.
                    println(output, "The worker ended during $(_part_place(part)): memory; ",
                            "the part runs again in a new worker.")
                    retry = _QueuedPart(part.package, part.suite, part.index, part.path,
                                        part.name, part.limit, part.is_alone, true)
                    insert!(queue, next, retry)
                else
                    println(output, "The worker ended during $(_part_place(part)): $result.")
                    _keep_record!(records, _stopped_record(worker, result, columns), columns,
                                  options)
                end
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

"""
    test_record_store() -> String

The folder of the stored records of the commits of `main`: the value of
`PROJECTURED_TEST_RECORDS` when it is set, or else
`~/.cache/projectured-test-records`. The record of a commit is the file
`<repository>/<commit>.tsv` in it.
"""
test_record_store() =
    get(ENV, "PROJECTURED_TEST_RECORDS", joinpath(homedir(), ".cache", "projectured-test-records"))

# The columns and the rows of a record file.
function _read_record_rows(path::AbstractString)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return (String[], Dict{String, String}[])
    columns = String.(split(first(lines), '\t'))
    (columns, [Dict(zip(columns, String.(split(line, '\t')))) for line in lines[2:end]])
end

_record_key(row) = get(row, "suite", "") * "/" * get(row, "part", "")
_record_counts(row) =
    Tuple(get(row, column, "") for column in ("result", "pass", "fail", "error", "broken"))
_counts_text(row) = "$(row["result"]): $(row["pass"]) pass, $(row["fail"]) fail, " *
                    "$(row["error"]) error, $(row["broken"]) broken"

# Print each row of `rows` whose result or counts differ from the row of the same
# part in `base_rows`, or that `base_rows` has not; give their count.
function _compare_rows(base_rows, rows, output::IO)
    known = Dict(_record_key(row) => row for row in base_rows)
    differences = 0
    for row in rows
        key = _record_key(row)
        if !haskey(known, key)
            println(output, "  new      $key: $(_counts_text(row))")
            differences += 1
        elseif _record_counts(known[key]) != _record_counts(row)
            println(output, "  changed  $key: $(_counts_text(known[key])) -> $(_counts_text(row))")
            differences += 1
        end
    end
    differences
end

"""
    compare_records(base, other; output = stdout) -> Int

Print each part of the record file `other` whose result or counts differ from the
part of the same suite and name in the record file `base`, or that `base` has
not, and give the count of these parts.
"""
compare_records(base::AbstractString, other::AbstractString; output::IO = stdout) =
    _compare_rows(last(_read_record_rows(base)), last(_read_record_rows(other)), output)

_short_commit(root, revision) = _git_text(root, `rev-parse --short=12 $revision`)

"""
    store_and_compare_records(records, columns, root; output = stdout) -> Nothing

After a run in the repository at `root`: when each record is of one commit of
`main` with no change that is not committed, store the records in
[`test_record_store`](@ref), in place of the stored records of the same parts.
Then, for a run of another commit, compare it with the stored record of the
commit where the branch left `main`, or say that no record of it is stored.
"""
function store_and_compare_records(records, columns, root::AbstractString; output::IO = stdout)
    isempty(records) && return nothing
    store = joinpath(test_record_store(), repository_name(root))
    commits = unique(r["commit"] for r in records if !isempty(get(r, "commit", "")))
    commit = length(commits) == 1 ? only(commits) : ""
    is_main = !isempty(commit) && !endswith(commit, "+") &&
              success(pipeline(`git -C $root merge-base --is-ancestor $commit main`;
                               stderr = devnull))
    if is_main
        path = joinpath(store, commit * ".tsv")
        mkpath(store)
        now = Set(_record_key(r) for r in records)
        stored = isfile(path) ? last(_read_record_rows(path)) : Dict{String, String}[]
        kept = [r for r in stored if !(_record_key(r) in now)]
        open(path, "w") do io
            println(io, join(columns, '\t'))
            for row in vcat(kept, records)
                println(io, join((get(row, column, "") for column in columns), '\t'))
            end
        end
        println(output, "Stored the record of commit $commit of main in $path.")
    end
    fork = _short_commit(root, _git_text(root, `merge-base HEAD main`))
    (isempty(fork) || commit == fork) && return nothing
    base = joinpath(store, fork * ".tsv")
    if isfile(base)
        println(output, "Compared with the stored record of main at $fork:")
        _compare_rows(last(_read_record_rows(base)), records, output) == 0 &&
            println(output, "  no part differs.")
    else
        println(output, "No record of main at $fork is stored; a run of the same suites on it ",
                "stores one.")
    end
    nothing
end

"""
    run_test_session(options; output = stdout) -> Int

Keep the workers open, and run each request that the folder `options.stay`
receives in `requests/`, in the order of the names of the request files. A
request is a file of the arguments of `tool/run-tests.jl`, one on each line, as
[`send_test_request`](@ref) writes it; it names the suites, the filters and the
limit, and the session gives the environment, the threads, the memory and the
count of the workers. Before each run, each worker applies the changes of the
files with Revise. When Revise can not apply them, that worker stops and a new
one starts, which loads the files again; the request `--restart` starts new
workers in any case. The output of a request goes to `results/<name>.log`, its
record to `results/<name>.tsv`, and its exit code to `results/<name>.done`. The
request `--stop` ends the session.
"""
function run_test_session(options::TestRunOptions; output::IO = stdout)
    requests = joinpath(options.stay, "requests")
    results = joinpath(options.stay, "results")
    mkpath(requests)
    mkpath(results)
    events = Channel{Tuple{Int, Vector{String}}}(Inf)
    ticker = Timer(_ -> put!(events, (0, ["tick"])), 1.0; interval = 1.0)
    sink = Ref{IO}(output)
    workers = _Worker[]
    columns = String[]
    try
        println(output, "The session waits for requests in $requests.")
        while true
            names = sort(filter(name -> endswith(name, ".request"), readdir(requests)))
            if isempty(names)
                number, fields = take!(events)           # a tick, or the end of a worker
                k = findfirst(w -> w.number == number, workers)
                first(fields) == "ended" && k !== nothing && (workers[k].is_ended = true)
                continue
            end
            stem = first(splitext(first(names)))
            path = joinpath(requests, first(names))
            arguments = filter(!isempty, readlines(path))
            rm(path)
            done(code) = write(joinpath(results, stem * ".done"), "$code\n")
            request = try
                read_test_run_options(arguments)
            catch error
                write(joinpath(results, stem * ".log"), sprint(showerror, error), "\n")
                done(2)
                continue
            end
            request.stop && (done(0); return 0)
            request.project = options.project
            request.threads = options.threads
            request.workers = options.workers
            request.memory_bytes = options.memory_bytes
            request.stay = options.stay
            "--limit" in arguments || (request.limit = options.limit)
            request.record = joinpath(results, stem * ".tsv")
            code = open(joinpath(results, stem * ".log"), "w") do log
                sink[] = log
                try
                    _run_session_request!(workers, request, events, columns, sink, log)
                catch error
                    println(log, "The request failed: ", sprint(showerror, error))
                    2
                finally
                    sink[] = output
                end
            end
            done(code)
            println(output, "Request $stem: exit code $code.")
        end
    finally
        close(ticker)
        _end_workers(workers)
    end
end

# Stop `worker` and wait for its end.
function _stop_and_wait!(worker::_Worker, events::Channel)
    _stop_worker!(worker)
    _wait_answer(_ -> nothing, worker, events, ())
    worker.is_ended = true
end

function _run_session_request!(workers, request, events, columns, sink, log)
    revised = String[]
    for worker in workers
        worker.is_ended && continue
        if request.restart
            _stop_and_wait!(worker, events)
            continue
        end
        _send(worker, "revise")
        fields = _wait_answer(_ -> nothing, worker, events, ("revised", "failed"))
        if fields === nothing
            worker.is_ended = true
        elseif fields[1] == "failed"
            println(log, "Revise could not apply the changes of the files (",
                    join(fields[2:end], " "), "); a new worker starts.")
            _stop_and_wait!(worker, events)
        else
            push!(revised, fields[2])
        end
    end
    if "yes" in revised
        println(log, "The workers applied the changes of the files with Revise.")
    elseif "no" in revised
        println(log, "The workers have no Revise; a change of a file needs --restart.")
    end
    if isempty(workers) || first(workers).is_ended
        worker = _start_worker(1, request, events, sink, request.workers > 1)
        isempty(workers) ? push!(workers, worker) : (workers[1] = worker)
        _wait_ready(worker, events, columns) ||
            (println(log, "The first worker ended before it was ready."); return 2)
    end
    _run_request!(workers, request, events, columns, sink, log)
end

"""
    send_test_request(folder, arguments; output = stdout, wait_seconds = 3600) -> Int

Send `arguments`, without `--send FOLDER`, as a request to the session of
`folder` ([`run_test_session`](@ref)); wait at most `wait_seconds` for its end;
print its output to `output`; and give its exit code, or 2 when no answer comes.
"""
function send_test_request(folder::AbstractString, arguments::AbstractVector{<:AbstractString};
                           output::IO = stdout, wait_seconds::Real = 3600)
    words = String.(arguments)
    k = findfirst(==("--send"), words)
    k === nothing || deleteat!(words, k:k + 1)
    requests = joinpath(folder, "requests")
    mkpath(requests)
    stem = string(round(Int, time() * 1000), "-", getpid())
    # A file with another name first, then the request whole, so the session never
    # reads half of it.
    hidden = joinpath(requests, "." * stem)
    write(hidden, join(words, '\n') * "\n")
    mv(hidden, joinpath(requests, stem * ".request"))
    done = joinpath(folder, "results", stem * ".done")
    if timedwait(() -> isfile(done), Float64(wait_seconds); pollint = 0.5) != :ok
        println(output, "The session of $folder gave no answer in $wait_seconds s.")
        return 2
    end
    log = joinpath(folder, "results", stem * ".log")
    isfile(log) && print(output, read(log, String))
    parse(Int, strip(read(done, String)))
end
