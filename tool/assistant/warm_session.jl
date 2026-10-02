# tool/assistant/warm_session.jl
#
# Run it as: julia -t 4 --project=environment/all tool/assistant/warm_session.jl <directory>
#
# A warm Julia for a fast loop. It loads the packages of the application once,
# with Revise, and then runs each command file that appears in <directory>/cmd,
# in the order of the names. Before a command it waits one second and lets
# Revise take in the changed source, so a change of a function, a docstring or a
# guide is in the next command without a new load. A command writes what it
# reports itself; the session writes <directory>/out/<name>.done when the
# command ends, with the seconds it took, or the error that ended it. A file
# named `stop` in <directory>/cmd ends the session.

using Revise
using ProjecturedAll, ProjecturedExample, ProjecturedKernelExample, ProjecturedOllama,
      ProjecturedSDL, ProjecturedSDLExample

const SESSION_DIRECTORY = abspath(ARGS[1])
const COMMAND_DIRECTORY = joinpath(SESSION_DIRECTORY, "cmd")
const OUTPUT_DIRECTORY = joinpath(SESSION_DIRECTORY, "out")
mkpath(COMMAND_DIRECTORY)
mkpath(OUTPUT_DIRECTORY)

function run_command!(path)
    name = splitext(basename(path))[1]
    started = time()
    outcome = try
        Base.include(Main, path)
        "ok"
    catch exception
        "failed: " * sprint(showerror, exception, catch_backtrace())
    end
    rm(path; force = true)
    write(joinpath(OUTPUT_DIRECTORY, name * ".done"),
          string(outcome, "\nseconds ", round(time() - started; digits = 1), "\n"))
    println("[session] ", name, ": ", first(outcome, 200))
    flush(stdout)
end

function run_session!()
    println("[session] ready: ", COMMAND_DIRECTORY)
    flush(stdout)
    while true
        names = sort(filter(name -> endswith(name, ".jl") || name == "stop",
                            readdir(COMMAND_DIRECTORY)))
        if isempty(names)
            sleep(0.5)
            continue
        end
        first(names) == "stop" && break
        sleep(1.0)
        revise()
        run_command!(joinpath(COMMAND_DIRECTORY, first(names)))
    end
    println("[session] stopped")
    flush(stdout)
end

run_session!()
