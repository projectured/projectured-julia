# Fragment of `TaskModule` — a process that a function of Julia imitates in place
# of a program, so that a compile workload runs the gestures of a task and starts
# no program.

"""
    ImitatedProcess

A process that a function imitates in place of a program. [`start_process_task!`](@ref)
starts one in place of the command when [`run_with_process_imitation`](@ref) gives
the function. The function writes the lines of the program into the two streams
on a task of its own, and its return value is the exit code.

It answers what a task asks of a process: `wait`, `process_running`,
`process_exited`, `process_signaled`, `success`, `kill`, and the fields
`exitcode` and `termsignal`. It has no process identifier. A function runs to
its end: `kill` records the signal, and the end reports it as the signal that
ended the process.
"""
mutable struct ImitatedProcess
    command::Base.AbstractCmd
    exitcode::Int
    termsignal::Int
    task::Task
    ImitatedProcess(command::Base.AbstractCmd) = new(command, -1, 0)
end

Base.process_running(process::ImitatedProcess) = !istaskdone(process.task)
Base.process_exited(process::ImitatedProcess) = istaskdone(process.task)
Base.process_signaled(process::ImitatedProcess) = process.termsignal != 0
Base.success(process::ImitatedProcess) =
    (wait(process); process.exitcode == 0 && process.termsignal == 0)

function Base.wait(process::ImitatedProcess)
    wait(process.task)
    nothing
end

function Base.kill(process::ImitatedProcess, signal::Integer = Base.SIGTERM)
    istaskdone(process.task) || (process.termsignal = signal)
    nothing
end

# The function that imitates each command that a task starts, or `nothing` for
# the programs themselves.
const _PROCESS_IMITATION = ScopedValue{Union{Function,Nothing}}(nothing)

"""
    run_with_process_imitation(f, imitation) -> the value of f()

Run `f()`, and in it imitate each process that a task starts:
[`start_process_task!`](@ref) calls `imitation(command, output, error_output)`
on a task of its own in place of the program, and gives the task an
[`ImitatedProcess`](@ref). `imitation` writes the lines of the program into the
streams `output` and `error_output` and answers the exit code; an exception
that it throws is written into `error_output` and ends it with the code 1. A
task that starts inside `f`, such as the loop of an editor, imitates too.

A compile workload uses it, so that the gestures of a task, its progress and its
end compile and no program starts while a package image builds.
"""
run_with_process_imitation(f, imitation::Function) = with(f, _PROCESS_IMITATION => imitation)

# Start the imitation of `command`. The streams are the pipes of the readers of
# the task; the imitation writes into their ends and closes them at its end.
function _start_imitated_process(imitation::Function, command::Base.AbstractCmd,
                                 output::Pipe, error_output::Pipe)
    Base.link_pipe!(output; reader_supports_async = true, writer_supports_async = true)
    Base.link_pipe!(error_output; reader_supports_async = true, writer_supports_async = true)
    process = ImitatedProcess(command)
    process.task = Threads.@spawn :default begin
        code = try
            Int(imitation(command, output.in, error_output.in))
        catch exception
            showerror(error_output.in, exception)
            println(error_output.in)
            1
        finally
            close(output.in)
            close(error_output.in)
        end
        process.exitcode = code
    end
    process
end
