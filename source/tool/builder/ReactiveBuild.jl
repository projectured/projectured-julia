# Fragment of `BuilderModule` — the reactive build: the second build of a binary
# compiles the edit and no more.
#
# `create_app` compiles the program from nothing at every build, minutes for a
# large program. The reactive Julia boots a build from the previous image and
# emits only what an edit changed, and `PackageCompiler.materialize_app` of the
# branch `reactive` of the fork drives it: the first call founds a store beside
# the bundle, and every later call reads the tracked sources from disk,
# evaluates what changed, and links the delta in front of the previous image.
# No build runs the program: the founding traces the workloads of the packages
# in a throwaway process, and a rebuild precompiles the statements of that trace
# after the edit. The part of the builder is to say which files to track and
# what the trace runs.
#
# The store is the switch. By default `build_executable` founds one when the
# output holds none and the Julia is the reactive one, and rebuilds whenever the
# output holds one. Another Julia builds plain and says what the reactive build
# gives. A rebuild goes
# through the compiler server that stays between builds (`server`), writes an
# overlay beside the image (`image = :overlay`), and compiles the edit at the
# `-O` level of the build or a lower one (`delta_optimization`). The store
# founds again on request (`found`) or when the image grew (`compact`).
# `print_reactive_status!` and `stop_reactive_server` act on a store without a
# build, and `watch_reactive_store!` rebuilds at every change of a tracked file.

"""
    REACTIVE_STORE

The directory under the bundle where `materialize_app` keeps its store: the
text objects and the tracked sources of the builds. Its presence is what makes
the next build a rebuild, so a build that must start again removes it.
"""
const REACTIVE_STORE = "reactive-store"

# The line that the record of a reactive build ends with. The record is compiled
# in when the store is founded and a rebuild keeps it, so it names the build that
# founded the store and not the edit.
const REACTIVE_RECORD_LINE =
    "reactive: founded by PackageCompiler.materialize_app; a later build of the " *
    "same output compiled the edit only\n"

"""
    collect_tracked_sources(context, package) -> Vector{Pair{String,String}}

The source files of `package`, each with the dotted name of the module whose
`include` loads it — the `tracked` list that `materialize_app` takes.

Read from the root file of the package: every literal `include("…")` at the
top level of a module is a tracked file, evaluated in that module, and a
`module` block names a deeper module for what it includes. The walk follows
the included files too.

The root file comes first, with the empty module path: its top level is the
`module Pkg … end` block itself, so an `include` or a `using` that joins the
module body is an edit of a tracked file, and the rebuild applies it or
refuses it with a reason. An `include` whose argument is not a string literal,
and one inside a function, are not tracked: the walk names them and tracks
nothing for them.
"""
collect_tracked_sources(context::BuildContext, package::AbstractString) =
    _call_reactive_compiler(:tracked_sources,
                            get_package_directory(context, package))::Vector{Pair{String,String}}

"""
    write_trace_workload(context, project, packages) -> String

Write what the trace of a reactive build runs, and answer the file.

The trace is the set of roots that a rebuild precompiles after the edit, and
that `refresh_trace` traces again from the current binary. A throwaway process
runs it from a file, in `Main`, after the image loaded. It runs the workload of
each package of the build that compiles ahead, which `@compile_ahead` of
`ProjecturedPrecompile` defines as `run_package_workload()`. No build runs the
file.
"""
function write_trace_workload(context::BuildContext, project::AbstractString, packages)
    file = joinpath(project, "trace_workload.jl")
    content = sprint() do io
        println(io, "# Written by `ProjecturedBuilder.build_executable`: what the trace of a")
        println(io, "# reactive build runs, in a throwaway process.")
        println(io, "using ", join(String.(packages), ", "))
        for package in packages
            is_compiling_package(get_package_directory(context, String(package))) &&
                println(io, package, ".run_package_workload()")
        end
    end
    write_if_changed(file, content)
    file
end

# The compiler is loaded the way `_create_app` loads it, and it must be the
# reactive one: the released compiler has no `materialize_app`, and a stock
# Julia refuses a rebuild inside it.
function _get_reactive_compiler_function(name::Symbol)
    compiler = Base.require(PACKAGE_COMPILER)
    isdefined(compiler, name) ||
        error("build_executable: a reactive build needs `PackageCompiler.$name`, and the " *
              "compiler at $(pathof(compiler)) has none. The branch `reactive` of " *
              "https://github.com/projectured/PackageCompiler.jl has it, and the " *
              "`[sources]` of environment/build/Project.toml name the compiler that a " *
              "build loads.")
    getfield(compiler, name)
end

_call_reactive_compiler(name::Symbol, arguments...; keywords...) =
    Base.invokelatest(_get_reactive_compiler_function(name), arguments...; keywords...)

# The default of `compact`: the variable of the compiler, `saves,growth`.
function _get_reactive_compact_default()
    parts = split(get(ENV, "JULIA_REACTIVE_COMPACT", "50,0.25"), ',')
    length(parts) == 2 ||
        error("JULIA_REACTIVE_COMPACT is `saves,growth`, not ", repr(join(parts, ',')))
    return (parse(Int, parts[1]), parse(Float64, parts[2]))
end

"""
    print_reactive_status!(output; io = stdout) -> Bool

Print what the reactive store under `output` holds — the founding, the
snapshots, the chain of overlays of the bundle, the server, the growth — and
answer whether there is one.
"""
print_reactive_status!(output::AbstractString; io::IO = stdout) =
    _call_reactive_compiler(:print_store_status, io, String(output))::Bool

"""
    stop_reactive_server(output) -> Bool

Stop the compiler server of the store under `output`, if one runs, and answer
whether one ran.
"""
stop_reactive_server(output::AbstractString) =
    _call_reactive_compiler(:stop_server, String(output))::Bool

"""
    watch_reactive_store!(output, build; io = stdout, settle = 0.5)

Rebuild at every change of a tracked file of the store under `output`, until
Ctrl-C. `build` is a function of no argument that runs the build. A change is
a new modification time of a tracked file of the list of the store; the watch
waits until the files stayed still for `settle` seconds, then calls `build`
and prints the seconds. A build that fails — a refused edit, a syntax error —
prints its error, and the watch goes on. Ctrl-C stops the watch and the
compiler server.
"""
watch_reactive_store!(output::AbstractString, build; io::IO = stdout, settle::Real = 0.5) =
    _call_reactive_compiler(:watch_app, String(output), build; io, settle)

# The change detector of the watch, for the tests.
_collect_changed_files!(stamps::Dict{String,Float64}) =
    _call_reactive_compiler(:_changed_files!, stamps)::Set{String}

"""
    has_reactive_julia() -> Bool

Whether the running Julia carries the reactive compiler: the stdlib
`ReactiveCompiler` and the options of its compiler server. A reactive build
needs it.
"""
has_reactive_julia() = :reactive_server in fieldnames(Base.JLOptions)

"""
    describe_reactive_build() -> String

The words that tell a person that the reactive build exists, what it gives,
and how to get it. A build and a script that runs from source print them when
the reactive Julia is not there.
"""
describe_reactive_build() = """
    With the reactive Julia, the first build of a binary founds a store under its
    output, and every later build compiles the edit and no more: seconds, where a
    whole build takes minutes. The reactive Julia is the branch `merged` of
    https://github.com/levy/julia, which also writes a pre-relocated image. Build
    it and select it:
        git clone --branch merged https://github.com/levy/julia julia-merged
        make -C julia-merged
        juliaup link merged "\$PWD/julia-merged/usr/bin/julia"
        juliaup default merged
    """

# What is missing for a reactive build, or `nothing`. Only a build that would
# found a store asks, so only it loads the compiler.
function _find_missing_reactive_part()
    has_reactive_julia() || return "this Julia has no reactive compiler"
    compiler = Base.require(PACKAGE_COMPILER)
    isdefined(compiler, :materialize_app) ||
        return "the PackageCompiler at $(pathof(compiler)) has no `materialize_app`; " *
               "the `[sources]` of environment/build/Project.toml name the branch " *
               "`reactive` of https://github.com/projectured/PackageCompiler.jl"
    nothing
end

# What `reactive = :auto` means. A build that compiles founds a store when the
# output holds none and rebuilds when it holds one, unless it asks for what a
# rebuild can not give: a fresh image or the performance counters. Without the
# reactive Julia it builds plain and says what it would give. A store is never
# rebuilt plain by accident, because the store goes with the old output. A run
# from source compiles nothing, and writes the package that the store was
# founded for. The two facts about the Julia are keywords, so that a test does
# not depend on the Julia that runs it.
function _choose_reactive_build(reactive::Union{Bool,Symbol}, output::AbstractString,
                                incremental::Bool, performance_counters::Bool, compile::Bool;
                                reactive_julia::Bool = has_reactive_julia(),
                                find_missing_part = _find_missing_reactive_part)
    reactive === true && compile && !reactive_julia &&
        error("build_executable: `reactive = true` needs the reactive Julia, and this " *
              "Julia has no reactive compiler.\n" * describe_reactive_build())
    reactive === :auto || return reactive
    stored = isdir(joinpath(output, REACTIVE_STORE))
    compile || return stored && incremental && !performance_counters
    if !incremental || performance_counters
        stored && @info "build_executable: $output holds a reactive store, but this build " *
                        "asks for " * (incremental ? "the performance counters" : "a fresh image") *
                        ", which a rebuild can not give, so it builds plain, and the store " *
                        "goes with the old output"
        return false
    end
    if stored
        reactive_julia ||
            error("build_executable: $output holds a reactive store, and this Julia has no " *
                  "reactive compiler, so it can not rebuild it. Start the build with the " *
                  "reactive Julia that founded the store, or build with --no-reactive " *
                  "(reactive = false): a plain build, and the store goes with the old " *
                  "output.\n" * describe_reactive_build())
        @info "build_executable: $output holds a reactive store, so this build compiles " *
              "the edit and no more (--no-reactive builds plain)"
        return true
    end
    missing_part = find_missing_part()
    if missing_part === nothing
        @info "build_executable: $output holds no reactive store, so this build founds " *
              "one: a whole build, and every later build compiles the edit and no more " *
              "(--no-reactive builds plain)"
        return true
    end
    @info "build_executable: $missing_part, so this build compiles the whole program. " *
          "--no-reactive asks for this build and says nothing.\n" * describe_reactive_build()
    false
end

# Every wrong combination of the options of a reactive build is refused before
# anything is written.
function _check_reactive_options(reactive, incremental::Bool, performance_counters::Bool,
                                 tracked, refresh_trace::Bool, image::Symbol,
                                 delta_optimization::Integer, found::Bool, trimmed::Bool)
    reactive isa Bool ||
        error("build_executable: `reactive` is true, false or :auto, not $(repr(reactive))")
    image in (:whole, :pages, :overlay) ||
        error("build_executable: `image` is :overlay, :pages or :whole, not $(repr(image))")
    0 <= delta_optimization <= 3 ||
        error("build_executable: `delta_optimization` is 0 to 3, not $delta_optimization")
    found && !reactive &&
        error("build_executable: `found` founds a reactive store again; it means nothing " *
              "without `reactive`")
    trimmed && !reactive &&
        error("build_executable: `trimmed` is the trimmed product of a reactive store; it " *
              "means nothing without `reactive`")
    tracked === nothing || reactive ||
        error("build_executable: `tracked` names what a reactive rebuild watches; it means " *
              "nothing without `reactive`")
    refresh_trace && !reactive &&
        error("build_executable: `refresh_trace` refreshes the trace of a reactive store; " *
              "it means nothing without `reactive`")
    reactive && !incremental &&
        error("build_executable: a reactive build is an incremental build that goes on " *
              "from its own previous image; it can not also start from a fresh one")
    performance_counters && reactive &&
        error("build_executable: `performance_counters` is compiled into a fresh image, " *
              "and a reactive rebuild keeps the image of its founding build; build with " *
              "`reactive = false`, or without PROJECTURED_PERFORMANCE_COUNTERS=true")
    nothing
end

# The two steps that a reactive build puts in the place of those of a plain one:
# the step after the package is written, and the compile. The modification times
# of the app files are read now, before the builder writes them: a rebuild
# compiles the edit of a tracked file and nothing else, and the app module is not
# tracked, so what a binary holds is fixed when its store is founded. A store
# founded for another package is refused, rather than a rebuild of the old
# program.
function _make_reactive_steps(context::BuildContext, name::AbstractString, packages,
                              output::AbstractString, tracked, found::Bool,
                              refresh_trace::Bool, server::Bool, image::Symbol,
                              delta_optimization::Integer, compact::Tuple{Int,Float64},
                              trimmed::Bool, prelink::Bool)
    store = joinpath(output, REACTIVE_STORE)
    directory = joinpath(context.root, "build", "app", String(name))
    app_files = [joinpath(directory, "Project.toml"),
                 joinpath(directory, "src", get_app_module_name(name) * ".jl")]
    stamps = [isfile(file) ? mtime(file) : 0.0 for file in app_files]
    # The trace workload is written with the package and not when it is
    # compiled, because `compile = false` writes it too: what a rebuild runs is
    # part of what a founding build wrote. The tracked files are read only by a
    # compile, so a run from source loads no compiler.
    trace_workload = ""
    after_write = project -> begin
        !found && isdir(store) &&
            any(isfile(file) && mtime(file) != stamp for (file, stamp) in zip(app_files, stamps)) &&
            error("build_executable: the store $store was founded for another package: " *
                  "what the binary holds, or its workload, changed since. Found the store " *
                  "again with `found = true`, or build without `reactive`")
        trace_workload = write_trace_workload(context, project, packages)
        nothing
    end
    compile_app = (project, out, program; force, optimization, debug_info, strip_metadata,
                   cpu_target, incremental, filter_stdlibs) -> begin
        watched = tracked === nothing ?
            reduce(vcat, [collect_tracked_sources(context, String(package)) for package in packages];
                   init = Pair{String,String}[]) : tracked
        @info "build_executable: a reactive build" tracked = length(watched) trace_workload
        _materialize_app!(project, out, program; force, optimization, debug_info,
                          strip_metadata, cpu_target, tracked = watched,
                          workload = trace_workload, refresh_trace, server, image,
                          delta_optimization, found, compact, trimmed, prelink)
    end
    (after_write, compile_app)
end

# The reactive counterpart of `compile_app!`. The same arguments reach
# `materialize_app`, which founds the store on the first build and rebuilds the
# delta on every later one; on a rebuild it reads the tracked files and the
# workload from the store, so what this passes then is what the founding build
# passed. The store also tracks every path package of the Manifest of `project`
# and walks their includes again at each rebuild, so an edit of one of them
# rebuilds the binary in seconds. With `refresh_trace`, `refresh_trace` of the
# compiler runs the workload from the current binary first and adds what it
# compiles to the trace of the store.
#
# On Linux the program holds the founding image: a founding keeps its object
# archive, and the builder links it with headroom for the overlay, prelinks it,
# and names the chain of the bundle as the chain of the program. A rebuild writes
# only the overlay, and the program applies it at its start. `materialize_app`
# founds again by itself when the overlay grew, so the program is linked again
# whenever the archive is new.
function _materialize_app!(project::AbstractString, output::AbstractString, name::AbstractString;
                           force::Bool, optimization::Integer, debug_info::Integer,
                           strip_metadata::Bool, cpu_target::AbstractString,
                           tracked::Vector{Pair{String,String}}, workload::AbstractString,
                           refresh_trace::Bool, server::Bool, image::Symbol,
                           delta_optimization::Integer, found::Bool,
                           compact::Tuple{Int,Float64}, trimmed::Bool, prelink::Bool)
    arguments = `-O$(optimization) -g$(debug_info)`
    strip_metadata && (arguments = `$arguments --strip-metadata`)
    linked = Sys.islinux()
    prelink = linked && prelink
    prelink && (arguments = `$arguments --sysimage-prelink=yes`)
    archive = get_object_archive(output)
    stamp = isfile(archive) ? mtime(archive) : 0.0
    rebuild = isdir(joinpath(output, REACTIVE_STORE))
    refresh_trace && !rebuild &&
        error("build_executable: `refresh_trace` needs the store of an earlier build under $output")
    if refresh_trace
        @info "Refreshing the trace of $name"
        _call_reactive_compiler(:refresh_trace, output)
    end
    @info (rebuild ? "Rebuilding $name" : "Founding the reactive store of $name") tracked = length(tracked) workload server image
    _call_reactive_compiler(:materialize_app, project, output;
                            tracked = tracked,
                            workload = workload,
                            executables = linked ? Pair{String,String}[] : [String(name) => "julia_main"],
                            (linked ? (; keep_object_archive = archive) : (;))...,
                            track_dependencies = true,
                            force = force,
                            incremental = true,
                            include_lazy_artifacts = true,
                            sysimage_build_args = arguments,
                            server = server,
                            image = image,
                            delta_opt = delta_optimization == optimization ? -1 : Int(delta_optimization),
                            founding = found,
                            compact = compact,
                            trim = trimmed ? :on : :off,
                            (isempty(cpu_target) ? () : (; cpu_target = String(cpu_target)))...)
    if linked && isfile(archive) && mtime(archive) != stamp
        link_executable!(output, name; headroom = true)
        prelink && prelink_executable!(output, name)
        chain = joinpath(output, "bin", String(name) * ".chain")
        rm(chain; force = true)
        symlink(joinpath("..", "lib", "julia", "sys.so.chain"), chain)
    end
    output
end

"""
    prepare_program_start!(build; name, output, script, build_script) -> NamedTuple

Prepare what a script that starts a program runs, and answer it as `(kind,
path, module_name, notice)`.

When `output` holds a reactive store and this Julia is the reactive one, it
rebuilds the binary with `build()`, and the answer is `kind = :binary` and the
executable. Else, and when the rebuild fails, it writes the package of the
binary with `build(; compile = false, resolve = true)`, and the answer is
`kind = :source`, the package and its module, which the script runs from
source. `notice` is what the script prints before the start: why the program
runs from source, and what the reactive build gives. A start never founds a
store, because a founding of a large program takes many minutes:
`build_script` founds it. The output of the rebuild goes to the error output,
so that the standard output carries only the answer.
"""
function prepare_program_start!(build; name::AbstractString, output::AbstractString,
                                script::AbstractString, build_script::AbstractString,
                                reactive_julia::Bool = has_reactive_julia())
    stored = isdir(joinpath(output, REACTIVE_STORE))
    if stored && reactive_julia
        try
            redirect_stdout(build, stderr)
            return (kind = :binary, path = joinpath(output, "bin", String(name)),
                    module_name = "", notice = "")
        catch err
            err isa InterruptException && rethrow()
            notice = "$script: the rebuild of $output failed, so the program runs from " *
                     "source. $build_script --found founds the store again.\n" *
                     first(split(sprint(showerror, err), '\n')) * "\n"
        end
    elseif reactive_julia
        notice = "$script: the program runs from source, and compiles what changed at its " *
                 "start. $build_script founds a reactive store once, a whole build; then " *
                 "this script rebuilds the binary in seconds and starts it.\n"
    else
        notice = "$script: this Julia has no reactive compiler, so the program runs from " *
                 "source, and compiles what changed at its start. With the reactive Julia, " *
                 "$build_script founds a store once, and then this script rebuilds the " *
                 "binary in seconds and starts it" *
                 (stored ? "; the store under $output needs the Julia that founded it" : "") *
                 ".\n" * describe_reactive_build()
    end
    project = build(; compile = false, resolve = true)
    (kind = :source, path = String(project), module_name = get_app_module_name(name), notice)
end
