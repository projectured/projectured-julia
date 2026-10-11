# The check of a release as a new user. Each way of the front page of
# Projectured.jl runs in a new environment of Pkg, with an empty depot, a new
# HOME and no git credentials. A way adds its packages, loads them, and shows a
# data frame in an offscreen window. The way of the setting "manual" checks that
# ProjecturedDataFrames stays out of the session. See
# documentation/guide/release-guide.md.
#
#     julia tool/check-release-as-new-user.jl <work folder> [<registry>]
#
# <registry> is the URL or the folder of the registry. Without it, the check
# adds the published ProjecturedRegistry. The script starts itself again with
# the same Julia and with no variable of the caller: HOME and TMPDIR are in the
# work folder, so the depot is `<work folder>/home/.julia` and empty. Give the
# command a memory cap and a timeout, because the first `using` compiles for
# minutes. The exit status is 0 when every way passes.

using Pkg

const PUBLISHED_REGISTRY = "https://github.com/projectured/ProjecturedRegistry"

# The packages that a session reports as loaded.
const REPORTED_PACKAGES = r"^(Projectured\w*|AutoIntegration)$"

# The data frame of the front page.
const FRAME = "DataFrame(n = 1:100_000, square = (1:100_000) .^ 2)"

# The seconds that one session can take, with the compile of its first `using`.
const SESSION_TIMEOUT = 1500

# Runs this script again with HOME and TMPDIR in `work` and no other variable of
# the caller, and answers its exit status.
function run_as_new_user(work::String, registry::String)
    variables = Dict("HOME" => mkpath(joinpath(work, "home")),
                     "TMPDIR" => mkpath(joinpath(work, "tmp")),
                     "PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8",
                     "GIT_TERMINAL_PROMPT" => "0", "JULIA_NUM_PRECOMPILE_TASKS" => "4")
    julia = first(Base.julia_cmd().exec)
    command = `$julia --startup-file=no $(@__FILE__) $work $registry`
    run(ignorestatus(setenv(command, variables))).exitcode
end

# Runs `code` in a new session of `environment`, and prints the lines that report
# a result. Answers the names of the loaded packages, or `nothing` when the
# session failed.
function run_session(environment::String, code::String)
    report = code * "\n" * """
        println("LOADED ", join(sort([p.name for p in keys(Base.loaded_modules)
                                      if occursin($(repr(REPORTED_PACKAGES)), p.name)]), " "))
        """
    julia = first(Base.julia_cmd().exec)
    command = addenv(`timeout $SESSION_TIMEOUT $julia --startup-file=no --project=$environment -e $report`,
                     "SDL_VIDEODRIVER" => "offscreen")
    output = IOBuffer()
    started = time()
    passed = success(pipeline(ignorestatus(command); stdout = output, stderr = output))
    text = String(take!(output))
    lines = split(text, "\n")
    foreach(line -> occursin(r"^(LOADED|FIRST FRAME)", line) && println("  ", line), lines)
    errors = filter(line -> occursin(r"Error|ERROR|fault|Fault", line), lines)
    println("  SESSION ", passed ? "ok" : "FAILED", " in ", round(Int, time() - started),
            " s, error lines ", length(errors))
    foreach(line -> println("    ", first(line, 240)), first(errors, 8))
    passed || println(last(text, 2500))
    loaded = findfirst(line -> startswith(line, "LOADED "), lines)
    passed && loaded !== nothing ? split(chopprefix(lines[loaded], "LOADED ")) : nothing
end

# The code of a session that loads with `load` and shows the data frame. It
# prints the seconds from the call of `display_in_editor` until the editor has
# drawn its first frame.
make_display_code(load::String) = """
    $load
    const Kernel = Base.root_module(Base.PkgId(Base.UUID("a3e3499a-684d-4df9-a0d6-de2d1797b1f3"), "ProjecturedKernel"))
    const Platform = Base.root_module(Base.PkgId(Base.UUID("b21cb890-5227-4e91-ae0e-8ab4d844f9f7"), "ProjecturedPlatform"))
    function measure_first_frame()
        started = time()
        display_in_editor($FRAME)
        editor = Platform.DisplayModule._SESSION[].editor
        while Kernel.PerformanceModule.get_frame_count(editor.frame_measurements) < 1 &&
              time() < started + 600
            sleep(0.005)
        end
        seconds = time() - started
        close_display_editor!()
        seconds
    end
    println("FIRST FRAME ", round(measure_first_frame(); digits = 2), " s")
    """

# Adds the packages of the Pkg command `line` to `environment`, and answers
# whether the add passed.
function add_packages(environment::String, line::String)
    Pkg.activate(environment)
    try
        Pkg.REPLMode.pkgstr(line)
        println("  ADD ok: ", line)
        true
    catch exception
        println("  ADD FAILED: ", line, "\n    ", first(sprint(showerror, exception), 600))
        false
    end
end

# Whether a session passed and loaded `ProjecturedDataFrames` as `expected` says.
is_loaded_as_expected(loaded, expected::Bool) =
    loaded !== nothing && ("ProjecturedDataFrames" in loaded) == expected

# Runs each way of the front page in `work`, with General and `registry`, and
# answers the exit status: 0 when every way passed.
function check_ways(work::String, registry::String)
    Pkg.Registry.add("General")
    Pkg.Registry.add(Pkg.RegistrySpec(url = registry))
    passed = Bool[]

    println("WAY 1, let Projectured load the integrations")
    automatic = joinpath(work, "environment-automatic")
    push!(passed, add_packages(automatic, "add Projectured ProjecturedSDL ProjecturedDataFrames DataFrames SimpleDirectMediaLayer") &&
                  is_loaded_as_expected(run_session(automatic, make_display_code("using Projectured, DataFrames, SimpleDirectMediaLayer")), true))

    println("WAY 2, name each package")
    manual = joinpath(work, "environment-manual")
    push!(passed, add_packages(manual, "add ProjecturedSDL ProjecturedDataFrames DataFrames") &&
                  is_loaded_as_expected(run_session(manual, make_display_code("using DataFrames, ProjecturedSDL, ProjecturedDataFrames")), true))

    println("WAY 3, choose for each package")
    push!(passed, add_packages(automatic, "add AutoIntegration") &&
                  run_session(automatic, """using AutoIntegration; set_auto_integration!("ProjecturedDataFrames", :manual)""") !== nothing &&
                  is_loaded_as_expected(run_session(automatic, "using Projectured, DataFrames, SimpleDirectMediaLayer"), false))

    println("WAY 4, load all integrations")
    integrations = joinpath(work, "environment-integrations")
    push!(passed, add_packages(integrations, "add ProjecturedIntegrations DataFrames SimpleDirectMediaLayer") &&
                  is_loaded_as_expected(run_session(integrations, make_display_code("using ProjecturedIntegrations, DataFrames, SimpleDirectMediaLayer")), true))

    println("RESULT ", join([(p ? "pass" : "FAIL") for p in passed], " "))
    all(passed) ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    if !(length(ARGS) in (1, 2))
        println(stderr, "usage: julia tool/check-release-as-new-user.jl <work folder> [<registry>]")
        exit(2)
    end
    work = abspath(ARGS[1])
    registry = length(ARGS) == 2 ? ARGS[2] : PUBLISHED_REGISTRY
    isdir(registry) && (registry = "file://" * abspath(registry))
    exit(get(ENV, "HOME", "") == joinpath(work, "home") ? check_ways(work, registry) :
         run_as_new_user(work, registry))
end
