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

# ── The execution ────────────────────────────────────────────────────────────

"""
    TaskExecution(task)

What one start of a task says while it runs, and what it ended with. The readers
of its process write it, and only through [`update_task_execution!`](@ref),
which holds its lock; a reader on another task takes a copy with
[`get_task_execution_snapshot`](@ref).

# Fields
- `status` — `:pending`, `:running`, `:cancelling`, `:done`, `:error`,
  `:cancelled` or `:skipped`.
- `process`, `process_id` — the process of the task and its identifier, once it
  started.
- `start_time`, `end_time` — the wall-clock times of the start and of the end.
- `progress` — a fraction while the task reports one, or `nothing`.
- `position` — where the task is, in a short text that its kind writes, such as
  the event and the time of a simulation that reports no fraction; or `nothing`.
- `output`, `error_output` — what the process printed on stdout and on stderr,
  as [`TaskOutput`](@ref).
- `processor_load` — the processor time the process used since the last sample,
  in percent of one processor; `resident_memory` — its resident memory, in
  bytes. [`sample_task_usage!`](@ref) reads both.
- `result` — the [`TaskResult`](@ref) once the task ended.
- `version` — counts every write, so a reader knows whether anything changed
  since it last looked.
"""
mutable struct TaskExecution
    lock::ReentrantLock
    task::AbstractTask
    status::Symbol
    process::Union{Base.Process,Nothing}
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
    version::Int
    reader::Union{Task,Nothing}
    # The processor time of the process at the last sample, in clock ticks, and
    # when that sample was taken.
    processor_ticks::Union{Int,Nothing}
    sampled_at::Union{Float64,Nothing}
end

TaskExecution(task::AbstractTask) =
    TaskExecution(ReentrantLock(), task, :pending, nothing, nothing, nothing, nothing,
                  nothing, nothing, TaskOutput(), TaskOutput(), nothing, nothing,
                  nothing, 0, nothing, nothing, nothing)

Base.show(io::IO, execution::TaskExecution) =
    print(io, "TaskExecution(", execution.task, ", ", execution.status, ")")

"""
    update_task_execution!(f, execution) -> execution

Write `execution` with `f(execution)`, under its lock, and count the write in
its `version`.
"""
function update_task_execution!(f, execution::TaskExecution)
    lock(execution.lock) do
        f(execution)
        execution.version += 1
    end
    execution
end

"""
    get_task_execution_snapshot(execution; output_count = -1, error_output_count = -1) -> NamedTuple

A copy of what `execution` holds now, taken under its lock. The lines of a
stream are copied only when the count of its lines differs from the count the
reader gives; otherwise that part is `nothing`. The copy holds `version`,
`status`, `process_id`, `start_time`, `end_time`, `progress`, `position`,
`output`, `output_count`, `error_output`, `error_output_count`,
`processor_load`, `resident_memory` and `result`.
"""
function get_task_execution_snapshot(execution::TaskExecution; output_count::Integer = -1,
                                     error_output_count::Integer = -1)
    lock(execution.lock) do
        (version = execution.version, status = execution.status,
         process_id = execution.process_id, start_time = execution.start_time,
         end_time = execution.end_time, progress = execution.progress,
         position = execution.position,
         output = execution.output.count == output_count ? nothing :
                  collect_output_lines(execution.output),
         output_count = execution.output.count,
         error_output = execution.error_output.count == error_output_count ? nothing :
                        collect_output_lines(execution.error_output),
         error_output_count = execution.error_output.count,
         processor_load = execution.processor_load,
         resident_memory = execution.resident_memory, result = execution.result)
    end
end

"""Whether the process of the task is alive."""
is_task_running(execution::TaskExecution) =
    execution.process !== nothing && process_running(execution.process)

"""Block until the task has ended and its result is set."""
function wait_task_execution(execution::TaskExecution)
    execution.reader === nothing || wait(execution.reader)
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
        _interrupt_process_group(execution.process)
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
        e.process = process
        e.process_id = process_id
        e.status = :running
        e.start_time = started
    end
    execution.reader = @async begin
        error_reader = @async _read_task_stream(error_output, execution, :error_output, nothing)
        _read_task_stream(output, execution, :output, read_line)
        wait(error_reader)
        wait(process)
        cancelled = lock(() -> execution.status === :cancelling, execution.lock)
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
        if e.processor_ticks !== nothing && e.sampled_at !== nothing && now > e.sampled_at
            e.processor_load = 100 * (ticks - e.processor_ticks) /
                               _get_clock_ticks_per_second() / (now - e.sampled_at)
        end
        e.processor_ticks = ticks
        e.sampled_at = Float64(now)
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
