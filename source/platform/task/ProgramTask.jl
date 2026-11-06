# A program as a task: one command that a person or a model starts in a folder, with
# the variables it adds to the environment of the editor, a log, an exit status and a
# stop. Unlike a step of a build it has no input files and no output files, and it
# always runs.

"""
    ProgramTask(command; working_directory, environment = Dict{String,String}(),
                time_limit = nothing, name = <the file name of the program>)

One program that runs as a task: `command`, a `Cmd` or a vector of strings, runs in
`working_directory`. `environment` adds its variables to the environment of the
editor process, and a variable of the same name replaces the one of the editor, so
the program keeps `PATH` and `HOME`. A `Cmd` that carries a folder or an
environment of its own throws an `ArgumentError`: give them with the keywords.

`time_limit` is a number of seconds, or `nothing`. At the limit the task stops its
process as a stop does, and ends `ERROR` with the reason `Time limit of 1800 s`, so
a program that hangs does not hold a group without end. `name` is what the row of
the task says, such as `"checkout"`.

The task ends `DONE` on exit code 0, `CANCEL` after a stop, and else `ERROR`
with the reason `Non-zero exit code: 3` or `Ended by signal 15`. A folder that does
not exist makes the start throw, and the group ends the task as a
[`TaskStartFailure`](@ref). Each line that holds `error:` or `fatal:` is marked
`:error`, and each that holds `warning:` is marked `:warning`.

# Example

    ProgramTask(`git checkout --detach 3fa2c1d`; working_directory = "/work/inet",
                name = "checkout")
"""
struct ProgramTask <: AbstractTask
    arguments::Vector{String}
    working_directory::String
    environment::Dict{String,String}
    time_limit::Union{Float64,Nothing}
    name::String
end

function ProgramTask(command::Union{Cmd,AbstractVector{<:AbstractString}};
                     working_directory::AbstractString,
                     environment::AbstractDict = Dict{String,String}(),
                     time_limit::Union{Real,Nothing} = nothing,
                     name::Union{AbstractString,Nothing} = nothing)
    if command isa Cmd && (!isempty(command.dir) || command.env !== nothing)
        throw(ArgumentError("a Cmd with a folder or an environment of its own does not run as " *
                            "a ProgramTask: give them with `working_directory` and `environment`"))
    end
    arguments = String.(command isa Cmd ? command.exec : command)
    isempty(arguments) && throw(ArgumentError("a ProgramTask needs a program to run"))
    ProgramTask(arguments, String(working_directory),
                Dict{String,String}(String(key) => String(value) for (key, value) in environment),
                time_limit === nothing ? nothing : Float64(time_limit),
                name === nothing ? basename(first(arguments)) : String(name))
end

"""
    ProgramResult

What a program ended with: the five fields of a result, and the exit code of its
process, or `nothing` when a signal or the time limit ended it.
"""
struct ProgramResult <: TaskResult
    task::ProgramTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
    exit_code::Union{Int,Nothing}
end

get_result_codes(::ProgramTask) = RUN_RESULT_CODES
format_task_parameters(task::ProgramTask) = task.name

# ── The start ────────────────────────────────────────────────────────────────

# The command of the task: its words, in its folder, with its variables added.
_make_program_command(task::ProgramTask) =
    addenv(Cmd(Cmd(task.arguments); dir = task.working_directory), task.environment)

_format_time_limit(seconds::Real) = string("Time limit of ", round(Int, seconds), " s")

"""
    start_task(task::ProgramTask; on_finish = nothing) -> TaskExecution

Start the program as a process task and answer at once. It throws when the folder
does not exist. With a `time_limit`, a timer stops the process at the limit, and
the end of the process closes the timer.
"""
function start_task(task::ProgramTask; on_finish = nothing)
    execution = TaskExecution(task)
    timed_out = Threads.Atomic{Bool}(false)
    timer = Ref{Union{Timer,Nothing}}(nothing)
    finish = function (process, cancelled, elapsed)
        timer[] === nothing || close(timer[])
        code = process.termsignal == 0 ? process.exitcode : nothing
        (result, reason) =
            timed_out[] ? ("ERROR", _format_time_limit(task.time_limit)) :
            cancelled ? ("CANCEL", "Cancel by user") :
            process.termsignal != 0 ? ("ERROR", "Ended by signal " * string(process.termsignal)) :
            process.exitcode == 0 ? ("DONE", nothing) :
            ("ERROR", "Non-zero exit code: " * string(process.exitcode))
        finish_task_execution!(execution,
            ProgramResult(task, result, "DONE", reason, elapsed, code); finish = on_finish)
    end
    start_process_task!(execution, _make_program_command(task); finish, on_finish)
    if task.time_limit !== nothing
        timer[] = Timer(task.time_limit) do _
            timed_out[] = true
            stop_task_execution!(execution)
        end
        # A process that ended before the timer was kept leaves no timer open.
        is_task_running(execution) || close(timer[])
    end
    execution
end

# ── What a program adds to the views ─────────────────────────────────────────

get_task_columns(::ProgramTask) = ["name" => 2, "command" => 4]

format_task_column(task::ProgramTask, column::AbstractString) =
    column == "name" ? task.name : column == "command" ? join(task.arguments, " ") : ""

function find_task_output_mark(::ProgramTask, ::Symbol, line::AbstractString)
    lowered = lowercase(line)
    occursin("error:", lowered) || occursin("fatal:", lowered) ? :error :
    occursin("warning:", lowered) ? :warning : nothing
end

function format_task_details(task::ProgramTask, result)
    lines = String["command: " * join(task.arguments, " "), "folder: " * task.working_directory]
    isempty(task.environment) ||
        push!(lines, "environment: " * join(("$key=$value" for (key, value) in sort!(collect(task.environment))), " "))
    result isa ProgramResult && result.exit_code !== nothing &&
        push!(lines, "exit code: " * string(result.exit_code))
    lines
end
