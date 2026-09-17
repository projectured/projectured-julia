# Fragment of `ProjecturedBuilder` — the package a build writes, and then
# compiles.
#
# **Written and not committed.** What a binary holds is a choice the build
# makes, and a choice cannot live in a `Project.toml` that was written once. It
# is a build artefact, like an object file: under `build/app/`, rewritten by
# every build, and never read by a person except when something went wrong.

# Stable across builds of one name, so a rebuild reuses the same package rather
# than resolving a stranger every time.
_app_uuid(name) = Base.UUID(bytes2hex(sha256(name))[1:32] |>
                            s -> string(s[1:8], "-", s[9:12], "-", s[13:16], "-",
                                        s[17:20], "-", s[21:32]))

# A name is a word per `_`, and a `-` counts as one too, because `--name` takes
# whatever a person types.
_module_name(name::AbstractString) =
    replace(titlecase(replace(String(name), "-" => " ", "_" => " ")), " " => "") * "App"

"""
    LOG_LEVEL_NAMES

The levels a binary logs from, least first.

`none` is `AboveMaxLevel`, so it silences `@error` as well. A binary that must
say nothing is a binary driven by a script that reads its exit code, and that is
a real answer to want.
"""
const LOG_LEVEL_NAMES = ("debug", "info", "warn", "error", "none")

"""
    write_app_package(context; name, packages, imports, init, main, workload,
                       info, usage, log_level) -> String

Write the package this build compiles, and answer its directory.

- `packages` — the names of what goes in. They become `[deps]`, `[sources]` and
  the `using` list, in that one place, so the three cannot disagree.
- `imports` — packages the generated module imports and does not use: a
  dependency of the build's own generated code (`init`, below) rather than of a
  program in `packages`. They join `[deps]` and `[sources]` beside `packages`,
  but they are written with `import` and not `using`, so their names stay
  qualified in a module a program's `main` is pasted into.
- `init` — Julia code run at module scope, after the log-level code and before
  `julia_main`: `nothing`, an `Expr`, or a `String`. A caller that must pin
  something once, at the end of a build, writes it here.
- `main` — an `Expr` whose value is the exit code. It becomes the body of
  `julia_main`. An `Expr` and not a string, so Julia's parser checks it while the
  build function is still running rather than minutes later.
- `workload` — an `Expr` run under `@compile_workload`, or `nothing`.
- `info` — what went in, as text. It becomes a constant read at module scope, so
  it is compiled into the image and cannot be separated from the binary.
- `usage` — a [`Usage`](@ref), and then this module answers `--help` and
  `--version` as well; or `nothing`, and then `main` owns the command line.
- `log_level` — the level the binary logs from when nobody says another. It is
  interpolated into the module rather than written as a preference, because the
  module that reads it is the module this writes.
"""
function write_app_package(context::BuildContext; name::AbstractString, packages,
                            imports = String[],
                            init::Union{Nothing,Expr,AbstractString} = nothing,
                            main::Expr,
                            workload::Union{Expr,Nothing} = nothing,
                            info::AbstractString = "",
                            usage::Union{Usage,Nothing} = nothing,
                            log_level::Symbol = :warn)
    String(log_level) in LOG_LEVEL_NAMES ||
        error("write_app_package: `log_level` is one of " *
              join(LOG_LEVEL_NAMES, ", ") * ", not :$log_level")
    # A build function writes an expression, and an expression carries the line
    # numbers of the file that wrote it. They would land in the generated source
    # as comments pointing at the builder, which is where a reader of a build
    # artefact should not be sent.
    main = Base.remove_linenums!(copy(main))
    workload = workload === nothing ? nothing : Base.remove_linenums!(copy(workload))
    init isa Expr && (init = Base.remove_linenums!(copy(init)))
    directory = joinpath(context.root, "build", "app", String(name))
    mkpath(joinpath(directory, "src"))
    module_name = _module_name(name)

    deps = Dict{String,Any}("PrecompileTools" => "aea7be01-6a6a-4083-8856-8a6e6704d82a")
    sources = Dict{String,Any}()
    for package in (packages..., imports...)
        package_dir = get_package_directory(context, package)
        deps[String(package)] = get_package_uuid(package_dir)
        sources[String(package)] = Dict("path" => relpath(package_dir, directory))
    end
    # Sorted, so that two builds of the same binary write the same bytes. A
    # `Dict` iterates in whatever order it likes, and an environment that changes
    # shape for no reason is an environment Julia resolves again.
    write_if_changed(joinpath(directory, "Project.toml"),
                     sprint(io -> TOML.print(io, Dict("name" => module_name,
                                                      "uuid" => string(_app_uuid(module_name)),
                                                      "version" => "0.1.0",
                                                      "deps" => deps,
                                                      "sources" => sources);
                                             sorted = true)))

    source = sprint() do io
        println(io, "# Written by `ProjecturedBuilder.build_executable`. A build that would ")
        println(io, "# write the same thing again leaves it alone, so that its cache holds.")
        println(io, "module ", module_name)
        println(io)
        println(io, "using PrecompileTools")
        for package in imports
            println(io, "import ", package)
        end
        for package in packages
            println(io, "using ", package)
        end
        println(io)
        println(io, "const BUILD_INFO = \"\"\"\n", info, "\"\"\"")
        println(io)
        print(io, """
        # Every binary logs from this level and up. `--log-level=<level>` on the
        # command line says another, $(context.log_variable) in the environment says
        # another, and the flag wins over the environment.
        #
        # THE BUILD OWNS THE FLAG, so `_apply_log_level!` takes it out of `ARGS`. A
        # program that parses its own command line would refuse a flag it does not
        # know, and it never sees this one.
        const DEFAULT_LOG_LEVEL = $(repr(String(log_level)))
        const LOG_LEVELS = Dict("debug" => Base.CoreLogging.Debug,
                                "info"  => Base.CoreLogging.Info,
                                "warn"  => Base.CoreLogging.Warn,
                                "error" => Base.CoreLogging.Error,
                                "none"  => Base.CoreLogging.AboveMaxLevel)

        function _apply_log_level!()::Cint
            name = get(ENV, $(repr(context.log_variable)), DEFAULT_LOG_LEVEL)
            found = findall(argument -> startswith(argument, "--log-level="), ARGS)
            isempty(found) ||
                (name = String(SubString(ARGS[last(found)], ncodeunits("--log-level=") + 1)))
            deleteat!(ARGS, found)
            level = get(LOG_LEVELS, lowercase(name), nothing)
            if level === nothing
                println(stderr, $(repr(String(name) * ": --log-level is one of " *
                                       join(LOG_LEVEL_NAMES, ", ") * ", not '")), name, "'")
                return Cint(1)
            end
            # A new logger and not a changed one: the level of a `ConsoleLogger`
            # is a field of an immutable struct.
            Base.CoreLogging.global_logger(Base.CoreLogging.ConsoleLogger(stderr, level))
            Cint(0)
        end
        """)
        if init !== nothing
            println(io)
            println(io, init isa AbstractString ? init : string(init))
        end
        if usage !== nothing
            println(io)
            println(io, "const USAGE = \"\"\"\n", format_usage(name, usage), "\"\"\"")
            println(io, "const VERSION_LINE = ", repr(format_version_line(context, name)))
            println(io, "const KNOWN_FLAGS = ", repr(collect_option_flags(usage)))
            # A flag that ends in `=` takes a value, so it matches what follows
            # it; every other flag matches whole.
            println(io, "_known_flag(argument) = any(flag -> endswith(flag, \"=\") ? ",
                        "startswith(argument, flag) : argument == flag, KNOWN_FLAGS)")
        end
        println(io)
        # Every binary answers `--build-info`, whatever else it answers. It is
        # written here rather than asked of each program, because the constant
        # is this module's and a program cannot know it exists.
        #
        # `--help` and `--version` join it when the build function wrote a usage.
        # A build function that wrote none has a program that owns the command
        # line, and this must not take the flag away from it.
        println(io, "Base.@ccallable function julia_main()::Cint")
        # FIRST, so that the flag is gone before anything else reads `ARGS` and
        # so that every line a binary writes is written at the level asked for.
        println(io, "    _apply_log_level!() == 0 || return 1")
        println(io, "    (\"--build-info\" in ARGS) && (print(BUILD_INFO); return 0)")
        if usage !== nothing
            println(io, "    (\"-h\" in ARGS || \"--help\" in ARGS) && (print(USAGE); return 0)")
            println(io, "    (\"-v\" in ARGS || \"--version\" in ARGS) && (println(VERSION_LINE); return 0)")
            # An unknown flag is refused and not read as something else.
            println(io, "    for argument in ARGS")
            println(io, "        if startswith(argument, \"-\") && !_known_flag(argument)")
            println(io, "            println(stderr, ", repr(String(name) * ": unknown option '"),
                        ", argument, \"'\")")
            println(io, "            println(stderr); print(stderr, USAGE); return 1")
            println(io, "        end")
            println(io, "    end")
        end
        println(io, "    ", string(main))
        println(io, "end")
        if workload !== nothing
            println(io)
            println(io, "@compile_workload begin")
            println(io, "    ", string(workload))
            println(io, "end")
        end
        println(io)
        println(io, "end # module ", module_name)
    end
    write_if_changed(joinpath(directory, "src", module_name * ".jl"), source;
                     ignoring = _BUILD_TIMESTAMP)
    directory
end

# The one line of the module that differs between two builds of the same thing.
const _BUILD_TIMESTAMP = r"built \d{4}-\d{2}-\d{2} \d{2}:\d{2} by ProjecturedBuilder"

"""
    write_if_changed(path, content; ignoring) -> Bool

Write `content` to `path` only when it differs from what is there, and answer
whether it wrote. `ignoring` is a pattern whose matches do not count as a
difference.

**A rewrite is a recompile.** Julia decides a cache is stale from the source
file, so writing the same module again costs its compilation — and the generated
module is the top of the tree, compiled at every build from nothing.

**The build timestamp is what makes every build differ**, and it is what
`ignoring` exists for. A rebuild of a binary that is the same in every way that
matters keeps the record it already had, so the date in `--build-info` says when
this content was first built rather than when it was last copied. That is the
more useful of the two answers, and it is the only one that lets the cache work.
"""
function write_if_changed(path::AbstractString, content::AbstractString;
                          ignoring::Union{Regex,Nothing} = nothing)
    if isfile(path)
        old = read(path, String)
        same = ignoring === nothing ? old == content :
               replace(old, ignoring => "") == replace(content, ignoring => "")
        same && return false
    end
    write(path, content)
    true
end
