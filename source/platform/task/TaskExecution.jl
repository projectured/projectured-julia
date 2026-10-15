# ══════════════════════════════════════════════════════════════════════════════
# What a task says while it runs: one execution for each start of a task, which
# the readers of its process write and a reader of the screen copies. The
# execution holds its own lock, because the two can run on two threads.
# ══════════════════════════════════════════════════════════════════════════════

# ── The lines of one stream ──────────────────────────────────────────────────

"""
    TaskOutput(; head = 100, tail = 1000)

The lines that one stream of a task printed, kept within a bound: the first
`head` lines, the last `tail` lines, and the count of every line, so that the
lines between the two are counted though they are not kept. A process that
prints without end cannot fill the memory.

- `path` is the file that holds every line of the stream, which the execution of
  a process writes ([`start_process_task!`](@ref)), or `nothing` when the stream
  has no file.
- `mark_counts` holds the count of the lines of each mark, and `first_mark_lines`
  the number of the first line of each mark, as the kind of the task marks them
  ([`find_task_output_mark`](@ref)).
"""
mutable struct TaskOutput
    head::Vector{String}
    tail::Vector{String}
    head_limit::Int
    tail_limit::Int
    count::Int
    path::Union{String,Nothing}
    mark_counts::Dict{Symbol,Int}
    first_mark_lines::Dict{Symbol,Int}
end

TaskOutput(; head::Integer = 100, tail::Integer = 1000) =
    TaskOutput(String[], String[], Int(head), Int(tail), 0, nothing, Dict{Symbol,Int}(), Dict{Symbol,Int}())

"""Add one line to `lines`, with its `mark` or `nothing`. The line goes to the head
while the head has room, and to the tail after that; the tail lets its oldest line
go when it is full."""
function append_output_line!(lines::TaskOutput, line::AbstractString; mark::Union{Symbol,Nothing} = nothing)
    lines.count += 1
    if length(lines.head) < lines.head_limit
        push!(lines.head, String(line))
    else
        push!(lines.tail, String(line))
        length(lines.tail) > lines.tail_limit && popfirst!(lines.tail)
    end
    if mark !== nothing
        lines.mark_counts[mark] = get(lines.mark_counts, mark, 0) + 1
        get!(lines.first_mark_lines, mark, lines.count)
    end
    lines
end

"""How many lines were printed between the head and the tail and are not kept."""
get_left_out_line_count(lines::TaskOutput) = lines.count - length(lines.head) - length(lines.tail)

"""
    collect_output_lines(lines) -> Vector{String}

The lines that are kept, in the order they came: the head, one line that says
how many were left out when some were, and the tail.
"""
function collect_output_lines(lines::TaskOutput)
    left_out = get_left_out_line_count(lines)
    left_out == 0 ? vcat(lines.head, lines.tail) :
        vcat(lines.head, ["⋯ " * string(left_out) * " lines left out ⋯"], lines.tail)
end

"""The last line the stream printed, or `nothing` when it printed none."""
find_last_output_line(lines::TaskOutput) =
    !isempty(lines.tail) ? last(lines.tail) : !isempty(lines.head) ? last(lines.head) : nothing

"""The kept lines as one text, each line ended by a newline."""
function format_output_text(lines::TaskOutput)
    collected = collect_output_lines(lines)
    isempty(collected) ? "" : join(collected, "\n") * "\n"
end

"""A copy of the kept lines, the count and the marks, which no later line changes."""
Base.copy(lines::TaskOutput) =
    TaskOutput(copy(lines.head), copy(lines.tail), lines.head_limit, lines.tail_limit, lines.count,
               lines.path, copy(lines.mark_counts), copy(lines.first_mark_lines))

# ── The files of the streams ─────────────────────────────────────────────────

const _SESSION_OUTPUT_FOLDER = Ref{Union{String,Nothing}}(nothing)
const _OUTPUT_FILE_COUNT = Threads.Atomic{Int}(0)

"""
    get_session_output_folder!() -> String

The folder of this process where the streams of the executions are written: a
folder for each process under the state folder of the user
(`XDG_STATE_HOME`, or `~/.local/state`), at `projectured/task-output/<process>`. It
is made at the first call, which also removes the folders of processes that no
longer run, and it goes when the process ends. It is never in the temporary
folder, which can be a disk in memory.
"""
function get_session_output_folder!()
    folder = _SESSION_OUTPUT_FOLDER[]
    folder === nothing || return folder
    state = get(ENV, "XDG_STATE_HOME", joinpath(homedir(), ".local", "state"))
    root = joinpath(state, "projectured", "task-output")
    mkpath(root)
    _remove_ended_output_folders!(root)
    folder = joinpath(root, string(getpid()))
    mkpath(folder)
    atexit(() -> rm(folder; force = true, recursive = true))
    _SESSION_OUTPUT_FOLDER[] = folder
end

# The folders of processes that no longer run, which ended before they could
# remove their own.
function _remove_ended_output_folders!(root::AbstractString)
    Sys.islinux() || return
    for name in readdir(root)
        process_id = tryparse(Int, name)
        process_id === nothing || process_id == getpid() || isdir("/proc/$(process_id)") ||
            rm(joinpath(root, name); force = true, recursive = true)
    end
end

# The file of one stream of a new execution of `task`: `<n>.stdout` or
# `<n>.stderr`, with the same `n` for both streams of one execution; `nothing`
# when the folder can not be made, and the stream then keeps its bounded lines
# alone.
function _make_output_path!(task, number::Int, field::Symbol)
    try
        folder = something(get_task_output_folder(task), get_session_output_folder!())
        mkpath(folder)
        joinpath(folder, string(number, field === :output ? ".stdout" : ".stderr"))
    catch exception
        @warn "the folder of the output of a task could not be made" exception
        nothing
    end
end

"""
    remove_task_output_files!(lines) -> lines

Remove the file of a stream, when it has one; the kept lines stay.
"""
function remove_task_output_files!(lines::TaskOutput)
    lines.path === nothing || rm(lines.path; force = true)
    lines
end

# ── The execution ────────────────────────────────────────────────────────────

"""
    TaskRuntime()

What an execution needs while its process runs, and which no view shows: the
lock that its writers and its readers take, the process, the task that reads
the streams of the process, the count of the writes, the last sample of the
processor time, and the functions that each write calls, such as the one of the
store of a feed that keeps the executions that changed. The shadow of an
execution does not hold it.
"""
mutable struct TaskRuntime
    lock::ReentrantLock
    process::Union{Base.Process,Nothing}
    reader::Union{Task,Nothing}
    # Counts every write, so a reader knows whether anything changed since it
    # last looked.
    version::Int
    # The processor time of the process at the last sample, in clock ticks, and
    # when that sample was taken.
    processor_ticks::Union{Int,Nothing}
    sampled_at::Union{Float64,Nothing}
    listeners::Vector{Any}
end

TaskRuntime() = TaskRuntime(ReentrantLock(), nothing, nothing, 0, nothing, nothing, Any[])

"""
    TaskExecution(task)

What one start of a task says while it runs, and what it ended with: a live
state (P3 of the catalog). The bare name is the native layout, which the readers
of its process write, and only through [`update_task_execution!`](@ref), which
holds the lock of its runtime. The editor task shows it through a shadow in the
cell layout ([`make_task_execution_shadow`](@ref)), which `sync_document!`
brings up to date.

# Fields
- `task` — the task that runs.
- `status` — `:pending`, `:running`, `:cancelling`, `:done`, `:error`,
  `:cancelled` or `:skipped`.
- `process_id` — the identifier of the process, once it started.
- `start_time`, `end_time` — the wall-clock times of the start and of the end.
- `progress` — a fraction while the task reports one, or `nothing`.
- `position` — where the task is, in a short text that its kind writes, such as
  the event and the time of a simulation that reports no fraction; or `nothing`.
- `output`, `error_output` — what the process printed on stdout and on stderr,
  as [`TaskOutput`](@ref). A shadow holds a copy, made when a line came.
- `processor_load` — the processor time the process used since the last sample,
  in percent of one processor; `resident_memory` — its resident memory, in
  bytes. [`sample_task_usage!`](@ref) reads both.
- `result` — the [`TaskResult`](@ref) once the task ended.
- `runtime` — the [`TaskRuntime`](@ref) of the native layout; `nothing` in a
  shadow.
- `stdout_page`, `stderr_page` — the page of each stream, a [`TaskStream`](@ref),
  which a shadow holds and the native layout does not: every line of the stream,
  with the state of its view, which stays while the shadow follows the
  execution.
"""
@document [M, C] struct TaskExecution
    task::AbstractTask
    status::Symbol
    process_id::Union{Int,Nothing}
    start_time::Union{Float64,Nothing}
    end_time::Union{Float64,Nothing}
    progress::Union{Float64,Nothing}
    position::Union{String,Nothing}
    output::TaskOutput
    error_output::TaskOutput
    processor_load::Union{Float64,Nothing}
    resident_memory::Union{Int,Nothing}
    result::Union{TaskResult,Nothing}
    runtime::Union{TaskRuntime,Nothing}
    stdout_page::Any
    stderr_page::Any
end

TaskExecution(task::AbstractTask) =
    TaskExecution(task, :pending, nothing, nothing, nothing, nothing, nothing,
                  TaskOutput(), TaskOutput(), nothing, nothing, nothing, TaskRuntime(), nothing, nothing)

Base.show(io::IO, execution::TaskExecution) =
    print(io, "TaskExecution(", execution.task, ", ", execution.status, ")")

"""
    update_task_execution!(f, execution) -> execution

Write `execution` with `f(execution)`, under the lock of its runtime, and count
the write. Then call each listener of the execution
([`attach_task_execution_listener!`](@ref)), with no lock held.
"""
function update_task_execution!(f, execution::TaskExecution)
    runtime = execution.runtime
    listeners = lock(runtime.lock) do
        f(execution)
        runtime.version += 1
        isempty(runtime.listeners) ? runtime.listeners : copy(runtime.listeners)
    end
    for listener in listeners
        listener()
    end
    execution
end

"""
    attach_task_execution_listener!(execution, listener) -> execution

Call `listener()` after each write of `execution`, on the task that writes, with
no lock held. A listener only notes the change: it reads no document, and it
does not wait.
"""
function attach_task_execution_listener!(execution::TaskExecution, listener)
    lock(() -> push!(execution.runtime.listeners, listener), execution.runtime.lock)
    execution
end

"""The count of the writes of `execution`, read under its lock."""
get_task_execution_version(execution::TaskExecution) =
    lock(() -> execution.runtime.version, execution.runtime.lock)

# The fields that a shadow takes as they are; the two streams are copied, and the
# runtime stays with the native layout.
const _SHADOW_FIELDS = (:task, :status, :process_id, :start_time, :end_time, :progress,
                        :position, :processor_load, :resident_memory, :result)

"""
    make_task_execution_shadow(execution) -> shadow

The shadow of `execution` in the cell layout, which a view reads: its fields as
they are now, a copy of the lines of each stream, read under the lock, and the
page of each stream. The shadow holds no runtime. Make it on the editor task.
"""
function make_task_execution_shadow(execution::TaskExecution)
    shadow = lock(execution.runtime.lock) do
        ACTaskExecution(execution.task, execution.status, execution.process_id,
                        execution.start_time, execution.end_time, execution.progress,
                        execution.position, copy(execution.output), copy(execution.error_output),
                        execution.processor_load, execution.resident_memory, execution.result,
                        nothing, nothing, nothing)
    end
    shadow.stdout_page = make_task_stream(shadow, :output)
    shadow.stderr_page = make_task_stream(shadow, :error_output)
    shadow
end

# An execution is called by the time it started.
get_document_title(shadow::ACTaskExecution) =
    shadow.start_time === nothing ? "not started" : "execution " * Libc.strftime("%H:%M:%S", shadow.start_time)

"""
    sync_document!(shadow, execution) -> shadow

Bring the shadow of an execution up to date, under the lock of the execution,
on the editor task. A field is written only when its value changed, and a stream
only when lines came since the last sync or it got its file, as a copy that no
later line changes.
"""
function sync_document!(shadow::ACTaskExecution, execution::TaskExecution, policy, depth::Int)
    lock(execution.runtime.lock) do
        for name in _SHADOW_FIELDS
            value = getfield(execution, name)
            isequal(getproperty(shadow, name), value) || setproperty!(shadow, name, value)
        end
        for name in (:output, :error_output)
            lines = getfield(execution, name)
            shown = getproperty(shadow, name)
            (lines.count == shown.count && lines.path == shown.path) || setproperty!(shadow, name, copy(lines))
        end
    end
    shadow
end

"""
    describe_task_execution(shadow) -> (text, result)

One execution in words: when it started and what it ended with, such as
`started 18:40:01 — ERROR (unexpected) in 1.2 s`, and the `TaskResult` it ended
with, or `nothing` while it has not ended. It reads the shadow of the execution.
"""
function describe_task_execution(shadow::ACTaskExecution)
    (status, start_time, result) = (shadow.status, shadow.start_time, shadow.result)
    started = start_time === nothing ? "not started" :
              "started " * Libc.strftime("%H:%M:%S", start_time)
    (started * " — " * (result === nothing ? String(status) : format_task_result(result)), result)
end

"""Whether the process of the task is alive."""
function is_task_running(execution::TaskExecution)
    process = execution.runtime.process
    process !== nothing && process_running(process)
end

"""Block until the task has ended and its result is set."""
function wait_task_execution(execution::TaskExecution)
    reader = execution.runtime.reader
    reader === nothing || wait(reader)
    execution
end

"""
    stop_task_execution!(execution) -> execution

Ask the task to stop: its process and the programs that the process started are
sent `SIGINT`, so a program that catches it can still finish its work, and the
status says `:cancelling` until the process ends. A task that has ended answers
nothing.
"""
function stop_task_execution!(execution::TaskExecution)
    if is_task_running(execution)
        update_task_execution!(e -> (e.status = :cancelling), execution)
        _interrupt_process_group(execution.runtime.process)
    end
    execution
end

# The process leads a group of its own (`start_process_task!`), so the interrupt
# goes to the group, and the programs that the process started, such as the
# compilers of `make`, stop with it. A process that leads no group gets the
# interrupt alone.
function _interrupt_process_group(process::Base.Process)
    if Sys.isunix()
        process_id = try
            Int(getpid(process))
        catch
            nothing
        end
        process_id === nothing ||
            ccall(:kill, Cint, (Cint, Cint), -process_id, Base.SIGINT) == 0 || kill(process, Base.SIGINT)
    else
        kill(process, Base.SIGINT)
    end
end

"""
    get_task_status(code) -> Symbol

The status that a result code leaves a task in. A code that says the work was
done — a run, a test that passed, an update — is `:done`; `CANCEL` is
`:cancelled`, `SKIP` is `:skipped`, and every other code is `:error`.
"""
get_task_status(code::AbstractString) =
    code in ("DONE", "PASS", "KEEP", "INSERT", "UPDATE") ? :done :
    code == "CANCEL" ? :cancelled : code == "SKIP" ? :skipped : :error

"""
    finish_task_execution!(execution, result; finish = nothing) -> execution

End `execution` with `result`: write the result, the status of its code and the
time of the end, and then call `finish(result)`. A kind of task calls it when
its process ended, and also when it ends without a process, such as a task that
is skipped.
"""
function finish_task_execution!(execution::TaskExecution, result::TaskResult; finish = nothing)
    update_task_execution!(execution) do e
        e.result = result
        e.status = get_task_status(result.result)
        e.end_time = time()
    end
    finish === nothing || finish(result)
    execution
end

"""
    TaskFinishFailure

What a task ended with when the end of its kind threw before it wrote a result:
`ERROR`, with the exception in its `reason`. [`start_process_task!`](@ref) writes
it, so the task ends and a group that waits for it goes on.
"""
struct TaskFinishFailure <: TaskResult
    task::AbstractTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

"""
    start_process_task!(execution, command; read_line = nothing, finish, on_finish = nothing) -> execution

Start `command` for the task of `execution`, and answer at once. Two readers
append what the process prints to `output` and to `error_output`, line by line;
`read_line(execution, line)` sees each line of stdout under the lock, so a kind
of task can write `progress` and `position` from it. When the process has ended
and both streams are read, `finish(process, cancelled, elapsed)` makes the
result, with `cancelled` true when [`stop_task_execution!`](@ref) asked for the
end, and calls [`finish_task_execution!`](@ref) with `on_finish`.

`finish` runs on the task that reads the process, which nobody waits for. When
it throws before it wrote a result, the error is logged and the execution ends
with a [`TaskFinishFailure`](@ref), which goes to `on_finish`: without it the
task would never end, and a group that waits for it would wait forever.

A `Cmd` starts in a process group of its own, so a stop reaches the programs
that it starts, and a Ctrl+C at the REPL does not reach the task.
"""
function start_process_task!(execution::TaskExecution, command::Base.AbstractCmd;
                             read_line = nothing, finish, on_finish = nothing)
    command isa Cmd && (command = Cmd(command; detach = true))
    output = Pipe()
    error_output = Pipe()
    started = time()
    process = run(pipeline(command; stdout = output, stderr = error_output); wait = false)
    close(output.in)
    close(error_output.in)
    # A process that ends at once has no identifier left to ask for.
    process_id = try
        Int(getpid(process))
    catch
        nothing
    end
    # Each stream keeps every line in a file of its own, beside the bounded lines.
    number = Threads.atomic_add!(_OUTPUT_FILE_COUNT, 1) + 1
    paths = (output = _make_output_path!(execution.task, number, :output),
             error_output = _make_output_path!(execution.task, number, :error_output))
    update_task_execution!(execution) do e
        e.runtime.process = process
        e.process_id = process_id
        e.status = :running
        e.start_time = started
        e.output.path = paths.output
        e.error_output.path = paths.error_output
    end
    # The readers and the sampler run on the default pool, never on the thread of
    # the loop that started the task.
    errormonitor(Threads.@spawn :default _sample_task_usage_while_running(execution))
    execution.runtime.reader = errormonitor(Threads.@spawn :default begin
        error_reader = Threads.@spawn :default _read_task_stream(error_output, execution, :error_output, nothing)
        _read_task_stream(output, execution, :output, read_line)
        wait(error_reader)
        wait(process)
        cancelled = lock(() -> execution.status === :cancelling, execution.runtime.lock)
        try
            finish(process, cancelled, time() - started)
        catch exception
            @error "the end of a task failed" task = execution.task exception = (exception, catch_backtrace())
            lock(() -> execution.result, execution.runtime.lock) === nothing &&
                finish_task_execution!(execution,
                    TaskFinishFailure(execution.task, "ERROR",
                                      get_result_codes(execution.task).expected,
                                      "The end failed: " * sprint(showerror, exception),
                                      time() - started);
                    finish = on_finish)
        end
    end)
    execution
end

# Read one stream of a process into `field` of its execution, one line at a time,
# with the mark that the kind of the task gives each line, and write each line to
# the file of the stream. The file is flushed at most five times a second while
# lines come, so a page that reads it while the process runs is at most that far
# behind, and once more at the end.
function _read_task_stream(stream, execution::TaskExecution, field::Symbol, read_line)
    path = lock(() -> getfield(execution, field).path, execution.runtime.lock)
    file = path === nothing ? nothing : _open_output_file!(path)
    flushed = time()
    try
        for line in eachline(stream)
            if file !== nothing
                println(file, line)
                now = time()
                now - flushed > 0.2 && (flush(file); flushed = now)
            end
            update_task_execution!(execution) do e
                mark = find_task_output_mark(e.task, field, line)
                append_output_line!(getfield(e, field), line; mark)
                read_line === nothing || read_line(e, line)
            end
        end
    catch exception
        @warn "a reader of the output of a task failed" exception
    finally
        file === nothing || close(file)
    end
end

# The file of a stream, open to write; `nothing` when it can not be made, and the
# stream then keeps its bounded lines alone.
function _open_output_file!(path::AbstractString)
    try
        open(path, "w")
    catch exception
        @warn "the file of the output of a task could not be made" path exception
        nothing
    end
end

# ── The use of the processor and of the memory ───────────────────────────────

"""
    sample_task_usage!(execution; now = time()) -> execution

Read the processor time and the resident memory of the process of a task that
runs, from `/proc`, and write into `execution` its resident memory and its
processor load since the last sample. The first sample gives no load, because a
load is a difference of two samples. A task that does not run, and a system with
no `/proc`, write nothing.
"""
function sample_task_usage!(execution::TaskExecution; now::Real = time())
    process_id = execution.process_id
    (process_id === nothing || execution.status !== :running) && return execution
    usage = read_system_process_usage(process_id)
    usage === nothing && return execution
    ticks, resident = usage
    update_task_execution!(execution) do e
        runtime = e.runtime
        if runtime.processor_ticks !== nothing && runtime.sampled_at !== nothing &&
           now > runtime.sampled_at
            e.processor_load = 100 * (ticks - runtime.processor_ticks) /
                               get_clock_ticks_per_second() / (now - runtime.sampled_at)
        end
        runtime.processor_ticks = ticks
        runtime.sampled_at = Float64(now)
        e.resident_memory = resident
    end
end

# How often the sampler of a process that runs reads `/proc`, in seconds.
const TASK_USAGE_SAMPLE_INTERVAL = 0.25

# Sample the use of the processor and of the memory of the process of
# `execution` while it runs, off the loop, so a drain only syncs the samples.
function _sample_task_usage_while_running(execution::TaskExecution)
    while lock(() -> execution.result === nothing, execution.runtime.lock)
        sample_task_usage!(execution)
        sleep(TASK_USAGE_SAMPLE_INTERVAL)
    end
end

