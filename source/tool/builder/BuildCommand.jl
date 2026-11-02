# Fragment of `BuilderModule` — the command line of the builder: the binary that
# its first argument names, and the options that go to the build function of that
# binary. `tool/build-binary.jl` runs it from a shell, and a script in `bin/` runs
# that with one binary fixed.

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
    BUILD_OPTIONS

The options of the command line, as `(key, label, description)`. A key that ends in
`=` takes a value. The help text lists the table, and the parser refuses an
option that the table does not name.
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
    ("--no-reactive", "--no-reactive",
     "compile the whole program, and found no store. A\n" *
     "store under the output goes with the old output"),
    ("--found", "--found",
     "found the store again now: a whole build"),
    ("--refresh-trace", "--refresh-trace",
     "before a rebuild, run the workload from the current\n" *
     "binary and add what it compiles to the trace of the\n" *
     "store, so that the binary compiles no new code at\n" *
     "its start"),
    ("--status", "--status",
     "print what the store of the output holds, and exit"),
    ("--stop-server", "--stop-server",
     "stop the compiler server of the store of the\n" *
     "output, and exit"),
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
                    "  the whole program."])
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
    parse_build_arguments(arguments; fixed = get_fixed_build_binary()) -> (binary, action, keywords)

The binary a command line names, what it asks for, and the keywords of the
build function. The action is `:executable`, `:distribution`, `:status` or
`:stop_server`. `fixed` is the binary that a `bin/` script
chose, and then the command line names none. A wrong command line raises an
error.
"""
function parse_build_arguments(arguments; fixed::AbstractString = get_fixed_build_binary())
    binary = isempty(fixed) ? nothing : fixed
    action = :executable
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
        if key == "--distribution"
            action = :distribution
        elseif key == "--status"
            action = :status
        elseif key == "--stop-server"
            action = :stop_server
        elseif key == "--no-reactive"
            keywords[:reactive] = false
        elseif key == "--found"
            keywords[:found] = true
        elseif key == "--refresh-trace"
            keywords[:refresh_trace] = true
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
archive under `build/`. With `--status` and `--stop-server`, it acts on the
reactive store of the output and builds nothing; `--status` answers 1 when the
output holds no store. A build is a Julia function, and this only reads a
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
        elseif action === :status
            return print_reactive_status!(_get_build_output(keywords)) ? 0 : 1
        elseif action === :stop_server
            output = _get_build_output(keywords)
            println(stop_reactive_server(output) ? "the compiler server of $output was stopped" :
                                                   "no compiler server runs for $output")
        else
            println(build_projectured_executable(; pairs(keywords)...))
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
