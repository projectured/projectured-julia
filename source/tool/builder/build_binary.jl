# ============================================================================
# The shell front end of the builder. The first argument names a binary, and the
# options go to its build function.
#
#     julia --project=environment/build source/tool/builder/build_binary.jl --help
#     julia --project=environment/build source/tool/builder/build_binary.jl projectured
#     julia --project=environment/build source/tool/builder/build_binary.jl projectured --distribution
#
# A build is a Julia function, and this file only reads a command line and calls
# that function. A decision about a build belongs in the function, where a test
# can reach it.
#
# The bundle goes to `build/<name>/`: the executable in `bin/`, the system image
# and the libraries in `lib/`, and the fonts in `share/`. With `--distribution`,
# the build also checks that a copy of the bundle runs outside this checkout, and
# writes the bundle as an archive under `build/`.
#
# A build uses much memory. Do not start a build beside another build.
#
# A test includes this file to read its functions. Then it neither resolves the
# environment nor starts a build.
# ============================================================================

using Pkg

const IS_COMMAND = abspath(PROGRAM_FILE) == @__FILE__

# The build environment must load `ProjecturedBuilder` before this file can use
# it. `resolve` also finds a dependency that a package of this repository added
# since the last build, which `instantiate` alone does not.
if IS_COMMAND
    Pkg.resolve(; io = devnull)
    Pkg.instantiate(; io = devnull)
end

using ProjecturedBuilder

# A script in `bin/` fixes the binary it builds and names itself, so that its
# `--help` names the command that a person typed and offers no choice of binary.
const FIXED_BINARY = get(ENV, "PROJECTURED_BUILD_WHAT", "")
const INVOCATION = get(ENV, "PROJECTURED_BUILD_COMMAND",
                       "julia --project=environment/build source/tool/builder/build_binary.jl")

const BINARIES = ["projectured" =>
    "the application: files in a window, a file\n" *
    "navigator and an AI assistant"]

"""
    OPTIONS

The options of the front end, as `(key, label, description)`. A key that ends in
`=` takes a value. The help text lists the table, and the parser refuses an
option that the table does not name.
"""
const OPTIONS = [
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

function format_front_end_usage()
    column = 26
    indent(text) = replace(text, "\n" => "\n" * " "^column)
    if isempty(FIXED_BINARY)
        lines = ["Usage: $INVOCATION <binary> [options]", "",
                 "Build a native binary of this repository.", "", "Binaries:", ""]
        for (name, description) in BINARIES
            push!(lines, "  " * rpad(name, column - 2) * indent(description))
        end
    else
        lines = ["Usage: $INVOCATION [options]", "",
                 "Build the `$FIXED_BINARY` binary of this repository."]
    end
    append!(lines, ["", "Options:", ""])
    for (_, label, description) in OPTIONS
        push!(lines, "  " * rpad(label, column - 2) * indent(description))
    end
    join(lines, "\n") * "\n"
end

function find_option(argument)
    argument == "--help" && return "-h"
    for (key, _, _) in OPTIONS
        (endswith(key, "=") ? startswith(argument, key) : argument == key) && return key
    end
    nothing
end

function get_option_value(argument, key)
    String(argument[ncodeunits(key)+1:end])
end

function parse_integer_option(argument, key)
    value = tryparse(Int, get_option_value(argument, key))
    value === nothing && error("$(key[1:end-1]) takes a number, not $(repr(argument))")
    value
end

"""
    parse_front_end_arguments(arguments) -> (binary, distribution, keywords)

The binary a command line names, whether it asks for a distribution, and the
keywords of the build function. `fixed` is the binary that a `bin/` script
chose, and then the command line names none. A wrong command line raises an
error.
"""
function parse_front_end_arguments(arguments, fixed::AbstractString = FIXED_BINARY)
    binary = isempty(fixed) ? nothing : fixed
    distribution = false
    keywords = Dict{Symbol,Any}()
    for argument in arguments
        if !startswith(argument, "-")
            isempty(fixed) ||
                error("this command builds $(repr(fixed)) and takes no other binary")
            binary === nothing || error("name one binary, not $(repr(binary)) and $(repr(argument))")
            any(==(argument) ∘ first, BINARIES) ||
                error("the binaries are $(join(first.(BINARIES), ", ")), not $(repr(argument))")
            binary = argument
            continue
        end
        key = find_option(argument)
        key === nothing && error("unknown option $(repr(argument))")
        if key == "--distribution"
            distribution = true
        elseif key == "--backends="
            keywords[:backends] = Tuple(Symbol.(split(get_option_value(argument, key), ',')))
        elseif key == "--no-workload"
            keywords[:workload] = false
        elseif key == "--no-incremental"
            keywords[:incremental] = false
        elseif key == "--filter-stdlibs"
            keywords[:filter_stdlibs] = true
        elseif key == "--name="
            keywords[:name] = get_option_value(argument, key)
        elseif key == "--output="
            keywords[:output] = abspath(get_option_value(argument, key))
        elseif key == "--optimization="
            keywords[:optimization] = parse_integer_option(argument, key)
        elseif key == "--debug-info="
            keywords[:debug_info] = parse_integer_option(argument, key)
        elseif key == "--strip-metadata"
            keywords[:strip_metadata] = true
        elseif key == "--cpu-target="
            keywords[:cpu_target] = get_option_value(argument, key)
        elseif key == "--log="
            keywords[:logfile] = abspath(get_option_value(argument, key))
        elseif key == "--log-level="
            keywords[:log_level] = Symbol(get_option_value(argument, key))
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

function run_front_end(arguments)::Cint
    if any(argument -> find_option(argument) == "-h", arguments)
        print(format_front_end_usage())
        return 0
    end
    binary, distribution, keywords = try
        parse_front_end_arguments(arguments)
    catch err
        err isa ErrorException || rethrow()
        println(stderr, "build_binary: ", err.msg)
        println(stderr, "Run `$INVOCATION --help` for the options.")
        return 1
    end
    if binary === nothing
        print(stderr, format_front_end_usage())
        return 1
    end
    if distribution
        println(build_projectured_distribution(; pairs(keywords)...))
    else
        println(build_projectured_executable(; pairs(keywords)...))
    end
    0
end

IS_COMMAND && exit(run_front_end(ARGS))
