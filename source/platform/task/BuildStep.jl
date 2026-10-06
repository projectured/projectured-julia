# The steps of a build: one command that makes files from files, or one copy of a
# file — `BuildTask`, `CppCompileTask`, `LinkTask`, `MsgCompileTask` and
# `CopyBinaryTask` of `common/compile.py` of `opp_repl`, with the command line
# that a domain computes. A step whose outputs are newer than all its inputs is
# up to date and answers `SKIP`, as `Task.run` of `opp_repl` answers it.

"""
    BuildStepTask

The supertype of a step of a build: [`BuildCommandTask`](@ref), which runs one
command, [`BuildCopyTask`](@ref), which copies one file, and
[`BuildRemoveTask`](@ref), which removes a file or a folder. A step knows its
input and its output files, relative to its working directory, and
[`is_build_step_up_to_date`](@ref) compares their times.
"""
abstract type BuildStepTask <: AbstractTask end

"""
    BuildCommandTask(; action, subject, working_directory, arguments, input_files,
                     output_files, dependency_file = nothing, dependency_root = nothing,
                     environment = nothing)

One command of a build, such as the compile of one file or a link: `arguments`
run in `working_directory`, with `environment` when it is given. `action` says
what the step does, in the `-ing` form (`"Compiling"`), and `subject` what it
does it to (`"src/inet/common/Foo.cc"`). `dependency_file`, which the command
writes, such as the `.d` file of a compiler, names the inputs of an output once
it exists; until then the inputs are `input_files`. `dependency_root` is a
second folder, relative to the working directory, that the paths of the
dependency file can be relative to: the folder that another engine runs the
same command in, such as `make` in the first C++ folder of a project.

After the command ends `DONE`, the step touches its outputs, so a command that
leaves an output as it was, as `opp_msgc` does when nothing changed, is up to
date the next time.
"""
struct BuildCommandTask <: BuildStepTask
    action::String
    subject::String
    working_directory::String
    arguments::Vector{String}
    input_files::Vector{String}
    output_files::Vector{String}
    dependency_file::Union{String,Nothing}
    dependency_root::Union{String,Nothing}
    environment::Union{Dict{String,String},Nothing}
end

BuildCommandTask(; action::AbstractString, subject::AbstractString,
                 working_directory::AbstractString, arguments::AbstractVector,
                 input_files::AbstractVector, output_files::AbstractVector,
                 dependency_file = nothing, dependency_root = nothing, environment = nothing) =
    BuildCommandTask(String(action), String(subject), String(working_directory),
                     String.(arguments), String.(input_files), String.(output_files),
                     dependency_file === nothing ? nothing : String(dependency_file),
                     dependency_root === nothing ? nothing : String(dependency_root),
                     environment === nothing ? nothing : Dict{String,String}(environment))

"""
    BuildCopyTask(; working_directory, source_file, target_file, postprocess = nothing)

The copy of one file of a build, such as a binary into the folder of the
binaries; `postprocess`, a command, then runs on the copy. A target that is the
same file as the source, a hard link, or that is not older than the source is
up to date.
"""
struct BuildCopyTask <: BuildStepTask
    working_directory::String
    source_file::String
    target_file::String
    postprocess::Union{Vector{String},Nothing}
end

BuildCopyTask(; working_directory::AbstractString, source_file::AbstractString,
              target_file::AbstractString, postprocess = nothing) =
    BuildCopyTask(String(working_directory), String(source_file), String(target_file),
                  postprocess === nothing ? nothing : String.(postprocess))

"""
    BuildRemoveTask(; working_directory, path)

The removal of a file or of a folder of a build, as a clean does it. A path that
is not there is up to date.
"""
struct BuildRemoveTask <: BuildStepTask
    working_directory::String
    path::String
end

BuildRemoveTask(; working_directory::AbstractString, path::AbstractString) =
    BuildRemoveTask(String(working_directory), String(path))

"""
    BuildStepResult

What a step of a build ended with: the five fields of a result, the exit code of
its command, or `nothing`, and `error_message`, what the command printed on
stderr when it failed.
"""
struct BuildStepResult <: TaskResult
    task::BuildStepTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
    exit_code::Union{Int,Nothing}
    error_message::Union{String,Nothing}
end

get_result_codes(::BuildStepTask) = RUN_RESULT_CODES
format_task_parameters(step::BuildCommandTask) = step.subject
format_task_parameters(step::BuildCopyTask) = step.target_file
format_task_parameters(step::BuildRemoveTask) = step.path
get_error_message(result::BuildStepResult) = something(result.error_message, "<No error message>")

_get_build_step_action(step::BuildCommandTask) = step.action
_get_build_step_action(::BuildCopyTask) = "Copying"
_get_build_step_action(::BuildRemoveTask) = "Removing"

# ── Up to date ───────────────────────────────────────────────────────────────

"""
    read_dependency_file(path) -> Dict{String,Vector{String}}

The rules of a dependency file that a compiler writes (`-MF`): each target and
the files that it depends on, as `read_dependency_file` of `opp_repl` reads them.
"""
function read_dependency_file(path::AbstractString)
    text = replace(read(path, String), "\\\n" => "", "//" => "/")
    rules = Dict{String,Vector{String}}()
    for line in split(text, '\n')
        matched = match(r"(.+): (.+)", line)
        matched === nothing && continue
        prerequisites = String[e for e in split(strip(matched.captures[2]), ' ') if !isempty(e)]
        for target in split(strip(matched.captures[1]), ' ')
            isempty(target) || (rules[String(target)] = prerequisites)
        end
    end
    rules
end

_resolve_build_path(step::BuildStepTask, path::AbstractString) =
    isabspath(path) ? String(path) : joinpath(step.working_directory, path)

"""
    find_build_step_input_files(step) -> Vector{String}

The files that a step reads: for a command with a dependency file that exists,
the files that the file names for the first output, or else for its first
target; else the inputs that the step declares. With a `dependency_root`, the
first output is looked up as it is and then relative to that folder, whose
paths are then taken relative to it, and no other target stands in.
"""
function find_build_step_input_files(step::BuildCommandTask)
    if step.dependency_file !== nothing
        path = _resolve_build_path(step, step.dependency_file)
        if isfile(path)
            rules = read_dependency_file(path)
            target = first(step.output_files)
            haskey(rules, target) && return rules[target]
            root = step.dependency_root
            if root === nothing
                isempty(rules) || return first(values(rules))
            else
                key = chopprefix(target, rstrip(root, '/') * "/")
                haskey(rules, key) && return [joinpath(root, p) for p in rules[key]]
            end
        end
    end
    step.input_files
end

find_build_step_input_files(step::BuildCopyTask) = [step.source_file]
find_build_step_input_files(::BuildRemoveTask) = String[]

_get_build_step_output_files(step::BuildCommandTask) = step.output_files
_get_build_step_output_files(step::BuildCopyTask) = [step.target_file]
_get_build_step_output_files(::BuildRemoveTask) = String[]

"""
    is_build_step_up_to_date(step) -> Bool

Whether every output of the step exists and is newer than every input, as
`BuildTask.is_up_to_date` of `opp_repl` decides. A step with no output or no
input is never up to date. A copy is also up to date when its target is the same
file as its source, or not older than it.
"""
function is_build_step_up_to_date(step::BuildStepTask)
    outputs = _get_build_step_output_files(step)
    inputs = find_build_step_input_files(step)
    (isempty(outputs) || isempty(inputs)) && return false
    oldest = Inf
    for output in outputs
        path = _resolve_build_path(step, output)
        isfile(path) || return false
        oldest = min(oldest, mtime(path))
    end
    for input in inputs
        path = _resolve_build_path(step, input)
        (ispath(path) && mtime(path) < oldest) || return false
    end
    true
end

function is_build_step_up_to_date(step::BuildCopyTask)
    source = _resolve_build_path(step, step.source_file)
    target = _resolve_build_path(step, step.target_file)
    if isfile(source) && isfile(target)
        source_status = stat(source)
        target_status = stat(target)
        (source_status.inode == target_status.inode && source_status.device == target_status.device) &&
            return true
        source_status.mtime <= target_status.mtime && return true
    end
    invoke(is_build_step_up_to_date, Tuple{BuildStepTask}, step)
end

is_build_step_up_to_date(step::BuildRemoveTask) = !ispath(_resolve_build_path(step, step.path))

# ── The start ────────────────────────────────────────────────────────────────

function _finish_build_step!(step, execution, result, expected, reason, elapsed, exit_code,
                             error_message, on_finish)
    finish_task_execution!(execution,
        BuildStepResult(step, result, expected, reason, elapsed, exit_code, error_message);
        finish = on_finish)
end

"""
    start_task(step::BuildCommandTask; on_finish = nothing) -> TaskExecution

Run the command of the step as a process task, or answer `SKIP` with
"Up-to-date" when the step is up to date. The folders of its outputs are made
first. It ends `DONE` on exit code 0, `CANCEL` after a stop, and else `ERROR`,
with what the command printed on stderr as its error message.
"""
function start_task(step::BuildCommandTask; on_finish = nothing)
    execution = TaskExecution(step)
    is_build_step_up_to_date(step) &&
        return _finish_build_step!(step, execution, "SKIP", "SKIP", "Up-to-date", 0.0, nothing,
                                   nothing, on_finish)
    for output in step.output_files
        mkpath(dirname(_resolve_build_path(step, output)))
    end
    command = Cmd(Cmd(step.arguments); dir = step.working_directory)
    step.environment === nothing || (command = setenv(command, step.environment))
    finish = function (process, cancelled, elapsed)
        code = process.exitcode
        if cancelled
            _finish_build_step!(step, execution, "CANCEL", "DONE", "Cancel by user", elapsed, code,
                                nothing, on_finish)
        elseif code == 0
            for output in step.output_files
                path = _resolve_build_path(step, output)
                isfile(path) && touch(path)
            end
            _finish_build_step!(step, execution, "DONE", "DONE", nothing, elapsed, code, nothing,
                                on_finish)
        else
            message = lock(() -> strip(format_output_text(execution.error_output)), execution.lock)
            _finish_build_step!(step, execution, "ERROR", "DONE",
                                "Non-zero exit code: " * string(code), elapsed, code,
                                isempty(message) ? nothing : String(message), on_finish)
        end
    end
    start_process_task!(execution, command; finish)
end

"""
    start_task(step::BuildCopyTask; on_finish = nothing) -> TaskExecution

Copy the file of the step, and run its `postprocess` on the copy, or answer
`SKIP` with "Up-to-date". A copy ends at once, with no process.
"""
function start_task(step::BuildCopyTask; on_finish = nothing)
    execution = TaskExecution(step)
    is_build_step_up_to_date(step) &&
        return _finish_build_step!(step, execution, "SKIP", "SKIP", "Up-to-date", 0.0, nothing,
                                   nothing, on_finish)
    started = time()
    target = _resolve_build_path(step, step.target_file)
    try
        mkpath(dirname(target))
        cp(_resolve_build_path(step, step.source_file), target; force = true)
        step.postprocess === nothing ||
            run(Cmd(Cmd([step.postprocess; target]); dir = step.working_directory))
        _finish_build_step!(step, execution, "DONE", "DONE", nothing, time() - started, nothing,
                            nothing, on_finish)
    catch exception
        _finish_build_step!(step, execution, "ERROR", "DONE", sprint(showerror, exception),
                            time() - started, nothing, nothing, on_finish)
    end
end

"""
    start_task(step::BuildRemoveTask; on_finish = nothing) -> TaskExecution

Remove the file or the folder of the step, or answer `SKIP` with "Up-to-date"
when it is not there. A removal ends at once, with no process.
"""
function start_task(step::BuildRemoveTask; on_finish = nothing)
    execution = TaskExecution(step)
    is_build_step_up_to_date(step) &&
        return _finish_build_step!(step, execution, "SKIP", "SKIP", "Up-to-date", 0.0, nothing,
                                   nothing, on_finish)
    started = time()
    try
        rm(_resolve_build_path(step, step.path); recursive = true, force = true)
        _finish_build_step!(step, execution, "DONE", "DONE", nothing, time() - started, nothing,
                            nothing, on_finish)
    catch exception
        _finish_build_step!(step, execution, "ERROR", "DONE", sprint(showerror, exception),
                            time() - started, nothing, nothing, on_finish)
    end
end

# ── What a step adds to the views ────────────────────────────────────────────

get_task_columns(::BuildStepTask) = ["step" => 1, "file" => 4]

format_task_column(step::BuildStepTask, column::AbstractString) =
    column == "step" ? _get_build_step_action(step) :
    column == "file" ? format_task_parameters(step) : ""

# The first line of an error message that names an error, else its first line.
function _find_build_error_line(message::AbstractString)
    lines = split(message, '\n')
    index = findfirst(line -> occursin("error:", line), lines)
    String(strip(lines[something(index, 1)]))
end

function format_task_details(step::BuildStepTask, result)
    lines = step isa BuildCommandTask ? String["command: " * join(step.arguments, " ")] :
            step isa BuildCopyTask ? String["copy: " * step.source_file * " → " * step.target_file] :
            String["remove: " * format_task_parameters(step)]
    result isa BuildStepResult || return lines
    result.exit_code === nothing || push!(lines, "exit code: " * string(result.exit_code))
    result.error_message === nothing ||
        push!(lines, "error: " * _find_build_error_line(result.error_message))
    lines
end
