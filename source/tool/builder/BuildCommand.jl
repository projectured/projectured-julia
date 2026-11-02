# Fragment of `BuilderModule` — the command line of the builder: the binary that
# its first argument names, and the options that go to the build function of that
# binary. `tool/build-binary.jl` runs it from a shell, and a script in `bin/` runs
# that with one binary fixed. The options of the reactive build and the actions
# on its store are shared: the build command of a repository that builds its
# binaries with this builder reads them with the same functions.

"""
    get_fixed_build_binary() -> String

The binary that a script in `bin/` fixes, from `PROJECTURED_BUILD_WHAT`; empty
when the command line names the binary. A script fixes it, and names itself in
`PROJECTURED_BUILD_COMMAND`, so that its `--help` names the command that a person
typed and offers no choice of binary.
"""
get_fixed_build_binary() = get(ENV, "PROJECTURED_BUILD_WHAT", "")

"""
    get_build_invocation() -> String

The command that the help text names, from `PROJECTURED_BUILD_COMMAND`.
"""
get_build_invocation() = get(ENV, "PROJECTURED_BUILD_COMMAND",
                             "julia --project=environment/build tool/build-binary.jl")

"""
    BUILD_BINARIES

The binaries that the command line builds, as `name => description`.
"""
const BUILD_BINARIES = ["projectured" =>
    "the application: files in a window, a Files\n" *
    "pane and an AI assistant"]

"""
    REACTIVE_BUILD_OPTIONS

The options of the reactive build and of its store, as `(key, label,
description)`: what every build command of this builder takes, here and in a
repository that builds its binaries with it. A key that ends in `=` takes a
value. [`apply_reactive_build_option!`](@ref) reads them, and
[`run_reactive_build_action!`](@ref) runs the action that one asks for.
"""
const REACTIVE_BUILD_OPTIONS = [
    ("--reactive", "--reactive",
     "found a store or rebuild it, as a build does by\n" *
     "default with the reactive Julia, and stop when this\n" *
     "Julia has no reactive compiler"),
    ("--no-reactive", "--no-reactive",
     "compile the whole program, and found no store. A\n" *
     "store under the output goes with the old output"),
    ("--found", "--found",
     "found the store again now: a whole build, and the\n" *
     "chain starts over"),
    ("--dev", "--dev",
     "the loop of a developer: --reactive, with the\n" *
     "rebuilt code at -O1 (--delta-optimization=1), and\n" *
     "--debug-info=1"),
    ("--watch", "--watch",
     "build now, then rebuild at every change of a tracked\n" *
     "file, until Ctrl-C, which stops the watch and the\n" *
     "compiler server"),
    ("--refresh-trace", "--refresh-trace",
     "before a rebuild, run the workload from the current\n" *
     "binary and add what it compiles to the trace of the\n" *
     "store, so that the binary compiles no new code at\n" *
     "its start"),
    ("--no-server", "--no-server",
     "rebuild in a child process, not in the compiler\n" *
     "server that stays between builds"),
    ("--image=", "--image=<mode>",
     "how a rebuild writes the image: overlay, a file\n" *
     "beside the base with the patches of the edit\n" *
     "(default); pages, the pages of the base that the\n" *
     "process wrote; whole, the whole image"),
    ("--delta-optimization=", "--delta-optimization=N",
     "the -O level of the code of a rebuild, 0 to 3\n" *
     "(default: the --optimization of the build)"),
    ("--compact=", "--compact=N,F",
     "found again after a growth of F of the image since\n" *
     "the founding, or after N rebuilds when a rebuild\n" *
     "writes pages or a whole image (default: 50,0.25)"),
    ("--trim", "--trim",
     "write the trimmed product beside the bundle, under\n" *
     "<output>/trimmed; an edit that makes a call site\n" *
     "dynamic is then refused"),
    ("--status", "--status",
     "print what the store of the output holds: the\n" *
     "snapshots, the chain, the server and the growth;\n" *
     "and exit"),
    ("--stop-server", "--stop-server",
     "stop the compiler server of the store of the\n" *
     "output, and exit"),
]

"""
    BUILD_OPTIONS

The options of the command line, as `(key, label, description)`: the options of
the application, and [`REACTIVE_BUILD_OPTIONS`](@ref). A key that ends in `=`
takes a value. The help text lists the table, and the parser refuses an option
that the table does not name.
"""
const BUILD_OPTIONS = [
    ("--distribution", "--distribution",
     "build for other machines: a fresh image for many\n" *
     "processor families, a test that a copy runs outside\n" *
     "this checkout, and an archive"),
    ("--backends=", "--backends=<list>",
     "the backends the binary holds, comma-separated\n" *
     "(default: sdl,web). The first one is the default of\n" *
     "the binary"),
    ("--precompile-calls=", "--precompile-calls=<value>",
     "what each package compiles ahead of time: recorded,\n" *
     "the recorded calls (default), live, a run of each\n" *
     "workload, or none: a faster build, a slower binary"),
    ("--no-incremental", "--no-incremental",
     "compile a fresh system image, not one on top of the\n" *
     "image of this Julia"),
    ("--filter-stdlibs", "--filter-stdlibs",
     "hold only the standard libraries that the program\n" *
     "uses. Needs --no-incremental"),
    ("--name=", "--name=<name>",
     "the name of the executable and of its directory\n" *
     "under build/"),
    ("--output=", "--output=<dir>", "where the bundle goes (default: build/<name>)"),
    ("--optimization=", "--optimization=N", "the -O level of the image, 0 to 3 (default: 3)"),
    ("--debug-info=", "--debug-info=N", "the -g level of the image, 0 to 2 (default: 1)"),
    ("--strip-metadata", "--strip-metadata",
     "remove docstrings and source locations from the\n" *
     "image"),
    ("--cpu-target=", "--cpu-target=<target>",
     "the processors the binary runs on (default: native,\n" *
     "the processor of this machine)"),
    ("--log=", "--log=<file>", "write the output of the compiler to a file"),
    ("--log-level=", "--log-level=<level>",
     "the level the binary logs from: debug, info, warn,\n" *
     "error, none (default: warn). The binary also takes\n" *
     "--log-level"),
    ("--no-compile", "--no-compile",
     "write the package of the binary under build/app/,\n" *
     "and compile nothing"),
    ("--no-prelink", "--no-prelink",
     "leave the restore of the image to every start. By\n" *
     "default a build does it once and writes it into\n" *
     "the program, which needs a Julia whose runtime can\n" *
     "write the restored image back"),
    REACTIVE_BUILD_OPTIONS...,
    ("-h", "-h, --help", "print this text and exit"),
]

"""
    format_build_usage(; fixed = get_fixed_build_binary(), invocation = get_build_invocation()) -> String

The help text of the command line: the binaries it builds, or the one that
`fixed` names, and every option of [`BUILD_OPTIONS`](@ref).
"""
function format_build_usage(; fixed::AbstractString = get_fixed_build_binary(),
                            invocation::AbstractString = get_build_invocation())
    column = 26
    indent(text) = replace(text, "\n" => "\n" * " "^column)
    if isempty(fixed)
        lines = ["Usage: $invocation <binary> [options]", "",
                 "Build a native binary of this repository.", "", "Binaries:", ""]
        for (name, description) in BUILD_BINARIES
            push!(lines, "  " * rpad(name, column - 2) * indent(description))
        end
    else
        lines = ["Usage: $invocation [options]", "",
                 "Build the `$fixed` binary of this repository."]
    end
    append!(lines, ["", "Options:", ""])
    for (_, label, description) in BUILD_OPTIONS
        push!(lines, "  " * rpad(label, column - 2) * indent(description))
    end
    append!(lines, ["", "Rebuilds:", "",
                    "  With the reactive Julia, the first build founds a store under the",
                    "  output: a whole build that keeps what it compiled. Every later build",
                    "  of the output reads the sources from disk, applies what changed to a",
                    "  compiler server that keeps the image in memory, and compiles the edit",
                    "  and no more, in seconds. The binary keeps what its founding build",
                    "  holds: a change of the backends or of the options of the package",
                    "  needs --found. With another Julia, a build compiles the whole program",
                    "  and says how to get the reactive one. --distribution always compiles",
                    "  the whole program.", "",
                    "  --dev compiles the code of a rebuild at -O1: a third off a rebuild, for",
                    "  a slower edited function. --watch builds once, then rebuilds at every",
                    "  save of a tracked file, in one process that pays the start of the tool",
                    "  once."])
    append!(lines, ["", "Environment:", "",
                    "  PROJECTURED_PERFORMANCE_COUNTERS=true",
                    " "^column * indent("compile the performance counters of the editor\n" *
                                        "in, so the frame statistics show the cell counts\n" *
                                        "of each part of a frame; --build-info says it")])
    join(lines, "\n") * "\n"
end

function _find_build_option(argument)
    argument == "--help" && return "-h"
    for (key, _, _) in BUILD_OPTIONS
        (endswith(key, "=") ? startswith(argument, key) : argument == key) && return key
    end
    nothing
end

_get_build_option_value(argument, key) = String(argument[ncodeunits(key)+1:end])

function _parse_integer_build_option(argument, key)
    value = tryparse(Int, _get_build_option_value(argument, key))
    value === nothing && error("$(key[1:end-1]) takes a number, not $(repr(argument))")
    value
end

"""
    apply_reactive_build_option!(keywords, argument) -> Union{Symbol,Nothing}

Read `argument` when it is one of [`REACTIVE_BUILD_OPTIONS`](@ref): set its
keywords of `build_executable` in `keywords`, and answer what the command does:
`:build`, or the action `:status`, `:stop_server` or `:watch`. Answer `nothing`
for another argument. A value that the option does not take raises an error.
"""
function apply_reactive_build_option!(keywords::AbstractDict{Symbol}, argument::AbstractString)
    if argument == "--reactive"
        keywords[:reactive] = true
    elseif argument == "--no-reactive"
        keywords[:reactive] = false
    elseif argument == "--found"
        keywords[:found] = true
    elseif argument == "--dev"
        keywords[:reactive] = true
        keywords[:delta_optimization] = 1
        keywords[:debug_info] = 1
    elseif argument == "--refresh-trace"
        keywords[:refresh_trace] = true
    elseif argument == "--no-server"
        keywords[:server] = false
    elseif startswith(argument, "--image=")
        keywords[:image] = Symbol(_get_build_option_value(argument, "--image="))
    elseif startswith(argument, "--delta-optimization=")
        keywords[:delta_optimization] = _parse_integer_build_option(argument, "--delta-optimization=")
    elseif startswith(argument, "--compact=")
        parts = split(_get_build_option_value(argument, "--compact="), ',')
        rebuilds = length(parts) == 2 ? tryparse(Int, parts[1]) : nothing
        growth = length(parts) == 2 ? tryparse(Float64, parts[2]) : nothing
        (rebuilds === nothing || growth === nothing) &&
            error("--compact takes N,F: the rebuilds and the growth, such as " *
                  "--compact=50,0.25, not $(repr(argument))")
        keywords[:compact] = (rebuilds, growth)
    elseif argument == "--trim"
        keywords[:trimmed] = true
    elseif argument == "--status"
        return :status
    elseif argument == "--stop-server"
        return :stop_server
    elseif argument == "--watch"
        return :watch
    else
        return nothing
    end
    :build
end

"""
    run_reactive_build_action!(build, action, output, keywords) -> Cint

Run an action of a build command on the reactive store under `output`, and
answer the exit code. `:status` prints what the store holds, and answers 1 when
there is none. `:stop_server` stops the compiler server of the store. `:watch`
builds once, which founds the store when there is none, and then rebuilds at
every change of a tracked file until Ctrl-C. `build` is the build function of
the command, called with `keywords`.
"""
function run_reactive_build_action!(build, action::Symbol, output::AbstractString,
                                    keywords::AbstractDict{Symbol})::Cint
    if action === :status
        return print_reactive_status!(output) ? 0 : 1
    elseif action === :stop_server
        println(stop_reactive_server(output) ? "the compiler server of $output was stopped" :
                                               "no compiler server runs for $output")
        return 0
    elseif action === :watch
        if !get(keywords, :compile, true)
            println(stderr, "--watch rebuilds a binary, and --no-compile builds none")
            return 1
        end
        # The first build founds the store when there is none, and the rest go
        # through it, resolved once.
        keywords[:reactive] = true
        build(keywords)
        keywords[:resolve] = false
        watch_reactive_store!(output, () -> build(keywords))
        return 0
    end
    error("run_reactive_build_action!: $(repr(action)) is not an action on a store")
end

"""
    parse_build_arguments(arguments; fixed = get_fixed_build_binary()) -> (binary, action, keywords)

The binary a command line names, what it asks for, and the keywords of the
build function. The action is `:executable`, `:distribution`, `:status`,
`:stop_server` or `:watch`, and a command line asks for one. `fixed` is the
binary that a `bin/` script chose, and then the command line names none. A
wrong command line raises an error.
"""
function parse_build_arguments(arguments; fixed::AbstractString = get_fixed_build_binary())
    binary = isempty(fixed) ? nothing : fixed
    action = :executable
    action_option = ""
    keywords = Dict{Symbol,Any}()
    for argument in arguments
        if !startswith(argument, "-")
            isempty(fixed) ||
                error("this command builds $(repr(fixed)) and takes no other binary")
            binary === nothing || error("name one binary, not $(repr(binary)) and $(repr(argument))")
            any(==(argument) ∘ first, BUILD_BINARIES) ||
                error("the binaries are $(join(first.(BUILD_BINARIES), ", ")), not $(repr(argument))")
            binary = argument
            continue
        end
        key = _find_build_option(argument)
        key === nothing && error("unknown option $(repr(argument))")
        asked = key == "--distribution" ? :distribution :
                apply_reactive_build_option!(keywords, argument)
        if asked !== nothing
            if asked !== :build
                action === :executable || action === asked ||
                    error("$action_option and $argument ask for two actions; name one")
                action, action_option = asked, argument
            end
            continue
        end
        if key == "--no-prelink"
            keywords[:prelink] = false
        elseif key == "--backends="
            keywords[:backends] = Tuple(Symbol.(split(_get_build_option_value(argument, key), ',')))
        elseif key == "--precompile-calls="
            keywords[:precompile_calls] = _get_build_option_value(argument, key)
        elseif key == "--no-incremental"
            keywords[:incremental] = false
        elseif key == "--filter-stdlibs"
            keywords[:filter_stdlibs] = true
        elseif key == "--name="
            keywords[:name] = _get_build_option_value(argument, key)
        elseif key == "--output="
            keywords[:output] = abspath(_get_build_option_value(argument, key))
        elseif key == "--optimization="
            keywords[:optimization] = _parse_integer_build_option(argument, key)
        elseif key == "--debug-info="
            keywords[:debug_info] = _parse_integer_build_option(argument, key)
        elseif key == "--strip-metadata"
            keywords[:strip_metadata] = true
        elseif key == "--cpu-target="
            keywords[:cpu_target] = _get_build_option_value(argument, key)
        elseif key == "--log="
            keywords[:logfile] = abspath(_get_build_option_value(argument, key))
        elseif key == "--log-level="
            keywords[:log_level] = Symbol(_get_build_option_value(argument, key))
        elseif key == "--no-compile"
            keywords[:compile] = false
        end
    end
    if get(keywords, :filter_stdlibs, false) && get(keywords, :incremental, true) &&
       action !== :distribution
        error("--filter-stdlibs needs --no-incremental")
    end
    if action === :distribution
        get(keywords, :compile, true) || error("--distribution needs a compiled bundle, not --no-compile")
        haskey(keywords, :incremental) && error("--distribution always compiles a fresh image")
        haskey(keywords, :cpu_target) && error("--distribution sets the processors itself")
        haskey(keywords, :found) && error("--distribution compiles the whole program, and founds no store")
    end
    (binary, action, keywords)
end

"""
    run_build_command(arguments) -> Cint

Build what the command line `arguments` asks for, and answer the exit code: 0
when the build ends, 1 for a wrong command line. The bundle goes to
`build/<name>/`: the executable in `bin/`, the system image and the libraries in
`lib/`, and the fonts in `share/`. With `--distribution`, the build also checks
that a copy of the bundle runs outside this checkout, and writes the bundle as an
archive under `build/`. With `--status`, `--stop-server` and `--watch`, it runs
[`run_reactive_build_action!`](@ref) on the reactive store of the output. A
build is a Julia function, and this only reads a
command line and calls that function, so a decision about a build belongs in the
function, where a test can reach it.
"""
function run_build_command(arguments)::Cint
    if any(argument -> _find_build_option(argument) == "-h", arguments)
        print(format_build_usage())
        return 0
    end
    binary, action, keywords = try
        parse_build_arguments(arguments)
    catch err
        err isa ErrorException || rethrow()
        println(stderr, "build-binary: ", err.msg)
        println(stderr, "Run `$(get_build_invocation()) --help` for the options.")
        return 1
    end
    if binary === nothing
        print(stderr, format_build_usage())
        return 1
    end
    try
        if action === :distribution
            println(build_projectured_distribution(; pairs(keywords)...))
        elseif action === :executable
            println(build_projectured_executable(; pairs(keywords)...))
        else
            return run_reactive_build_action!(action, _get_build_output(keywords),
                                              keywords) do keywords
                println(build_projectured_executable(; pairs(keywords)...))
            end
        end
    catch err
        is_build_refusal(err) || rethrow()
        println(stderr, err.msg)
        return 1
    end
    0
end

"""
    is_build_refusal(err) -> Bool

Whether `err` is a refusal of [`build_executable`](@ref): an option or a state
that the build does not take, which it refuses before it compiles. Its message
starts with `build_executable: ` and says all that a person needs, so a command
line prints the message and no stack trace.
"""
is_build_refusal(err) = err isa ErrorException && startswith(err.msg, "build_executable: ")

# The output of the build that a command line names, for an action on its store.
_get_build_output(keywords) =
    get(keywords, :output,
        joinpath(make_projectured_build_context().root, "build", get(keywords, :name, "projectured")))
