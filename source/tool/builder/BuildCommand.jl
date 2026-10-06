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
    ("--no-workload", "--no-workload",
     "compile no start of the application ahead of time.\n" *
     "The build is faster, and the first window of the\n" *
     "binary is slower"),
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
    parse_build_arguments(arguments; fixed = get_fixed_build_binary()) -> (binary, distribution, keywords)

The binary a command line names, whether it asks for a distribution, and the
keywords of the build function. `fixed` is the binary that a `bin/` script
chose, and then the command line names none. A wrong command line raises an
error.
"""
function parse_build_arguments(arguments; fixed::AbstractString = get_fixed_build_binary())
    binary = isempty(fixed) ? nothing : fixed
    distribution = false
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
            distribution = true
        elseif key == "--backends="
            keywords[:backends] = Tuple(Symbol.(split(_get_build_option_value(argument, key), ',')))
        elseif key == "--no-workload"
            keywords[:workload] = false
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
    if get(keywords, :filter_stdlibs, false) && get(keywords, :incremental, true) && !distribution
        error("--filter-stdlibs needs --no-incremental")
    end
    if distribution
        get(keywords, :compile, true) || error("--distribution needs a compiled bundle, not --no-compile")
        haskey(keywords, :incremental) && error("--distribution always compiles a fresh image")
        haskey(keywords, :cpu_target) && error("--distribution sets the processors itself")
    end
    (binary, distribution, keywords)
end

"""
    run_build_command(arguments) -> Cint

Build what the command line `arguments` asks for, and answer the exit code: 0
when the build ends, 1 for a wrong command line. The bundle goes to
`build/<name>/`: the executable in `bin/`, the system image and the libraries in
`lib/`, and the fonts in `share/`. With `--distribution`, the build also checks
that a copy of the bundle runs outside this checkout, and writes the bundle as an
archive under `build/`. A build is a Julia function, and this only reads a
command line and calls that function, so a decision about a build belongs in the
function, where a test can reach it.
"""
function run_build_command(arguments)::Cint
    if any(argument -> _find_build_option(argument) == "-h", arguments)
        print(format_build_usage())
        return 0
    end
    binary, distribution, keywords = try
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
    if distribution
        println(build_projectured_distribution(; pairs(keywords)...))
    else
        println(build_projectured_executable(; pairs(keywords)...))
    end
    0
end
