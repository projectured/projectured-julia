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
"""
mutable struct TaskOutput
    head::Vector{String}
    tail::Vector{String}
    head_limit::Int
    tail_limit::Int
    count::Int
end

TaskOutput(; head::Integer = 100, tail::Integer = 1000) =
    TaskOutput(String[], String[], Int(head), Int(tail), 0)

"""Add one line to `lines`. The line goes to the head while the head has room,
and to the tail after that; the tail lets its oldest line go when it is full."""
function append_output_line!(lines::TaskOutput, line::AbstractString)
    lines.count += 1
    if length(lines.head) < lines.head_limit
        push!(lines.head, String(line))
    else
        push!(lines.tail, String(line))
        length(lines.tail) > lines.tail_limit && popfirst!(lines.tail)
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

"""A copy of the kept lines and the count, which no later line changes."""
Base.copy(lines::TaskOutput) =
    TaskOutput(copy(lines.head), copy(lines.tail), lines.head_limit, lines.tail_limit, lines.count)

# ── The execution ────────────────────────────────────────────────────────────

"""
    TaskRuntime()

What an execution needs while its process runs, and which no view shows: the
lock that its writers and its readers take, the process, the task that reads
the streams of the process, the count of the writes, and the last sample of the
processor time. The shadow of an execution does not hold it.
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
end

TaskRuntime() = TaskRuntime(ReentrantLock(), nothing, nothing, 0, nothing, nothing)

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
end

TaskExecution(task::AbstractTask) =
    TaskExecution(task, :pending, nothing, nothing, nothing, nothing, nothing,
                  TaskOutput(), TaskOutput(), nothing, nothing, nothing, TaskRuntime())

Base.show(io::IO, execution::TaskExecution) =
    print(io, "TaskExecution(", execution.task, ", ", execution.status, ")")

"""
    update_task_execution!(f, execution) -> execution

Write `execution` with `f(execution)`, under the lock of its runtime, and count
the write.
"""
function update_task_execution!(f, execution::TaskExecution)
    runtime = execution.runtime
    lock(runtime.lock) do
        f(execution)
        runtime.version += 1
    end
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
they are now, and a copy of the lines of each stream, read under the lock. The
shadow holds no runtime. Make it on the editor task.
"""
function make_task_execution_shadow(execution::TaskExecution)
    lock(execution.runtime.lock) do
        ACTaskExecution(execution.task, execution.status, execution.process_id,
                        execution.start_time, execution.end_time, execution.progress,
                        execution.position, copy(execution.output), copy(execution.error_output),
                        execution.processor_load, execution.resident_memory, execution.result,
                        nothing)
    end
end

"""
    sync_document!(shadow, execution) -> shadow

Bring the shadow of an execution up to date, under the lock of the execution,
on the editor task. A field is written only when its value changed, and a stream
only when lines came since the last sync, as a copy that no later line changes.
"""
function sync_document!(shadow::ACTaskExecution, execution::TaskExecution, policy, depth::Int)
    lock(execution.runtime.lock) do
        for name in _SHADOW_FIELDS
            value = getfield(execution, name)
            isequal(getproperty(shadow, name), value) || setproperty!(shadow, name, value)
        end
        for name in (:output, :error_output)
            lines = getfield(execution, name)
            lines.count == getproperty(shadow, name).count || setproperty!(shadow, name, copy(lines))
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
    start_process_task!(execution, command; read_line = nothing, finish) -> execution

Start `command` for the task of `execution`, and answer at once. Two readers
append what the process prints to `output` and to `error_output`, line by line;
`read_line(execution, line)` sees each line of stdout under the lock, so a kind
of task can write `progress` and `position` from it. When the process has ended
and both streams are read, `finish(process, cancelled, elapsed)` makes the
result, with `cancelled` true when [`stop_task_execution!`](@ref) asked for the
end, and calls [`finish_task_execution!`](@ref).

A `Cmd` starts in a process group of its own, so a stop reaches the programs
that it starts, and a Ctrl+C at the REPL does not reach the task.
"""
function start_process_task!(execution::TaskExecution, command::Base.AbstractCmd;
                             read_line = nothing, finish)
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
    update_task_execution!(execution) do e
        e.runtime.process = process
        e.process_id = process_id
        e.status = :running
        e.start_time = started
    end
    execution.runtime.reader = @async begin
        error_reader = @async _read_task_stream(error_output, execution, :error_output, nothing)
        _read_task_stream(output, execution, :output, read_line)
        wait(error_reader)
        wait(process)
        cancelled = lock(() -> execution.status === :cancelling, execution.runtime.lock)
        finish(process, cancelled, time() - started)
    end
    execution
end

# Read one stream of a process into `field` of its execution, one line at a time.
function _read_task_stream(stream, execution::TaskExecution, field::Symbol, read_line)
    try
        for line in eachline(stream)
            update_task_execution!(execution) do e
                append_output_line!(getfield(e, field), line)
                read_line === nothing || read_line(e, line)
            end
        end
    catch exception
        @warn "a reader of the output of a task failed" exception
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
    usage = _read_process_usage(process_id)
    usage === nothing && return execution
    ticks, resident = usage
    update_task_execution!(execution) do e
        runtime = e.runtime
        if runtime.processor_ticks !== nothing && runtime.sampled_at !== nothing &&
           now > runtime.sampled_at
            e.processor_load = 100 * (ticks - runtime.processor_ticks) /
                               _get_clock_ticks_per_second() / (now - runtime.sampled_at)
        end
        runtime.processor_ticks = ticks
        runtime.sampled_at = Float64(now)
        e.resident_memory = resident
    end
end

# The processor time of a process, in clock ticks, and its resident memory, in
# bytes; `nothing` when the process is gone or the system has no `/proc`.
function _read_process_usage(process_id::Integer)
    stat = try read("/proc/$(process_id)/stat", String) catch; return nothing end
    statm = try read("/proc/$(process_id)/statm", String) catch; return nothing end
    # The name of the command is in parentheses and can hold spaces, so the
    # fields are counted from the last ")": the state is field 3 of the line, and
    # the user and the system time are fields 14 and 15.
    closing = findlast(')', stat)
    closing === nothing && return nothing
    fields = split(stat[closing + 1:end])
    length(fields) >= 13 || return nothing
    ticks = parse(Int, fields[12]) + parse(Int, fields[13])
    pages = split(statm)
    length(pages) >= 2 || return nothing
    (ticks, parse(Int, pages[2]) * _get_page_size())
end

# `sysconf(_SC_CLK_TCK)`, which is 2 on Linux, and the size of a memory page.
_get_clock_ticks_per_second() = Int(ccall(:sysconf, Clong, (Cint,), 2))
_get_page_size() = Int(ccall(:getpagesize, Cint, ()))
