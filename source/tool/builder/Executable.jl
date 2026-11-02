# Fragment of `BuilderModule` — write the package, compile it, bundle what
# it reads by path, and report.
#
# PackageCompiler is loaded by the one step that compiles, and not at the top of
# this fragment. A build is also described where no compiler is installed — a
# test asserts what a build would write — and that must not drag a compiler in.

# Loaded by its identity rather than with `@eval import`: an import at run time
# creates a binding in a later world than the code that reads it, which a
# recent Julia warns about and a later one will refuse.
const PACKAGE_COMPILER =
    Base.PkgId(Base.UUID("9b87118b-4619-50d2-8e1e-99f35a4d4d9d"), "PackageCompiler")

"""
    INCREMENTAL_MARK

What an incrementally built binary says about itself in its own build record.

**One string, written in one place and read in another.** `build_info` writes it
and `check_relocation` looks for it in what the built binary prints, so a
developer image cannot be archived by accident. A marker rather than a sentence,
because the two ends have to agree exactly.
"""
const INCREMENTAL_MARK = "INCREMENTAL BUILD"

"""
    PORTABLE_CPU_TARGET

The processor to compile for when the binary TRAVELS.

It is the empty string, and an empty target is the one thing [`compile_app!`](@ref)
does not pass on. `create_app` then picks its own, which is several code variants
for the architecture — on x86_64, `generic`, a `sandybridge` clone of everything,
and a `haswell` one. A binary compiled that way runs on a processor that is not
the one that compiled it, and it generates native code once per variant to do so.

**Only a distribution travels.** A distribution build asks for this constant
explicitly, and nothing else does; every other build compiles for `native`.
"""
const PORTABLE_CPU_TARGET = ""

_create_app(args...; kwargs...) =
    Base.invokelatest(getfield(Base.require(PACKAGE_COMPILER), :create_app),
                      args...; kwargs...)

"""
    _drop_stale_manifest(project) -> Bool

Delete the manifest beside `project` when a path it names is wrong. A path is
wrong in two cases: no package is at that path, or the project holds another
source path for that package. Answer whether the manifest went.

**A manifest that disagrees is not resolved, it is an assertion.** `Pkg.resolve`
walks the `[sources]` of the project against the entries of the manifest and
asserts `normpath(entry.path) == normpath(path)`; a package that was renamed or
split between two builds fails there, with no line naming the file to delete.
The manifest is a build artefact and the project beside it is the truth, so the
one that disagrees goes.

**A package that leaves the tree leaves its entry behind.** The manifest names
by path every package the build resolved, direct and indirect alike, and the
project names only the direct ones. A package that is deleted therefore stays in
the manifest and in no `[sources]` table, and `Pkg.resolve` throws `expected
package X to exist at path`. That path is gone, so the manifest is older than
the tree, and it goes.
"""
function _drop_stale_manifest(project::AbstractString)
    manifest = joinpath(project, "Manifest.toml")
    isfile(manifest) || return false
    held = get(TOML.parsefile(manifest), "deps", Dict{String,Any}())
    # A manifest holds one entry per name here, but the format is a list.
    for (name, entries) in held, entry in entries
        entry_path = get(entry, "path", nothing)
        entry_path === nothing && continue
        isdir(joinpath(project, entry_path)) && continue
        @info "Removing $manifest: no package for $name is at the path it names" entry_path
        rm(manifest)
        return true
    end
    sources = get(TOML.parsefile(joinpath(project, "Project.toml")), "sources", nothing)
    sources isa AbstractDict || return false
    for (name, source) in sources
        path = get(source, "path", nothing)
        path === nothing && continue
        for entry in get(held, name, ())
            entry_path = get(entry, "path", nothing)
            entry_path === nothing && continue
            normpath(entry_path) == normpath(path) && continue
            @info "Removing $manifest: it names another path for $name than the " *
                  "project beside it" entry_path path
            rm(manifest)
            return true
        end
    end
    false
end

"""
    resolve_app_project(project; precompile = true) -> project

Make the package a build wrote loadable: resolve it, then instantiate it.

**RESOLVE, and not `instantiate` alone.** `instantiate` keeps a manifest that
exists, and this one is a build artefact that outlives a change in what a HELD
package depends on. Measured on a build whose manifest went stale this way: it
compiled for minutes and then failed to load, because `instantiate` notices a
DIRECT dependency that appears; it does not notice one that appears inside a
package the manifest already lists.

**It is here so that it is in one place.** A build needs the package resolved
before it compiles, and a run script needs it resolved before it loads — the same
need, and it belongs to whoever wrote the package rather than to each caller.

The caller's active environment is restored on the way out: this has to activate
the package it resolves, and a prompt must not be left in it.

**`precompile = false` when the caller will COMPILE**, because `create_app`
precompiles this same package again and the two caches are not the same cache.
`PackageCompiler.ensurecompiled` runs its `Pkg.precompile()` under
`--pkgimages=no`, so it writes the source-only cache a system image build reads;
`instantiate` here writes the ordinary cache, with the native code beside it,
which nothing in a build ever loads.

A run script wants the ordinary cache — it loads the package rather than
compiling it — so it takes the default and pays once.

**A manifest whose versions do not resolve goes, and the resolve runs once more.**
`Pkg.resolve` holds every version the manifest names and only adds what is
missing. A package that joins the build can need an older version of a package
the manifest holds, and a manifest that holds the newer one fails with
`Unsatisfiable requirements`. A resolve from the project alone picks versions
that agree. A second failure is a real conflict, and it is thrown.
"""
function resolve_app_project(project::AbstractString; precompile::Bool = true)
    @info "Resolving $project" precompile
    _drop_stale_manifest(project)
    let caller_project = Base.active_project(),
        caller_auto = get(ENV, "JULIA_PKG_PRECOMPILE_AUTO", nothing)
        try
            precompile || (ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0")
            Pkg.activate(project)
            try
                Pkg.resolve()
            catch exception
                manifest = joinpath(project, "Manifest.toml")
                (exception isa Pkg.Resolve.ResolverError && isfile(manifest)) || rethrow()
                @info "Removing $manifest: the versions it holds do not resolve " *
                      "against the project beside it"
                rm(manifest)
                Pkg.resolve()
            end
            Pkg.instantiate()
        finally
            caller_auto === nothing ? delete!(ENV, "JULIA_PKG_PRECOMPILE_AUTO") :
                                      (ENV["JULIA_PKG_PRECOMPILE_AUTO"] = caller_auto)
            caller_project === nothing || Pkg.activate(caller_project; io = devnull)
        end
    end
    project
end

"""
    build_executable(context; name, packages, main, precompile_calls, preferences,
                       performance_counters, fonts, assets, usage, log_level, imports,
                       init, stand_ins,
                       incremental, filter_stdlibs, optimization, debug_info,
                       strip_metadata, cpu_target, output, compile, resolve,
                       precompile, force, logfile, extra_info, after_write,
                       compile_app, reactive, tracked, refresh_trace, server, image,
                       delta_optimization, found, compact, trimmed) -> String

Write a package holding `packages`, compile it into `output`, and answer the
output directory.

- `main` — an `Expr` whose value is the exit code, and the body of `julia_main`.
- `precompile_calls` — what each package of the build that compiles ahead
  compiles into the image: `"none"`, `"recorded"` or `"live"`, as the preference
  of the same name of `ProjecturedPrecompile` says. The build writes it for each
  such package, so the image does not depend on the preferences of the person
  who builds.
- `preferences` — what the image carries, from [`make_baked_preference`](@ref)
  and [`make_exposed_preferences`](@ref). Julia reads a preference only for a
  package that the project lists, so the package of each preference joins
  `imports` when `packages` and `imports` do not name it.
- `performance_counters` — compile the performance counters of the editor into
  the image, with the preference `performance_counters` of `ProjecturedKernel`,
  so the frame statistics of a window show the cell counts of each part of a
  frame. A build of packages that do not hold the kernel ignores it. The default
  is [`is_performance_counters_requested`](@ref), the environment variable
  `PROJECTURED_PERFORMANCE_COUNTERS`, so a script that builds, or that runs from
  source, takes the switch from its environment. A reactive rebuild keeps the
  image of its founding build, so a reactive build refuses it.
- `fonts` — bundle the text faces. A binary that draws needs them and a binary
  that draws nothing does not; see [`bundle_fonts!`](@ref) for why they cannot
  travel any other way.
- `assets` — directories to copy into the bundle, as `"demo/catalog" =>
  "share/app/catalog"`: a path under `context.root`, and where it lands under
  the output. Same reason as the fonts; see [`bundle_assets!`](@ref).
- `usage` — a [`Usage`](@ref), and then the binary answers `--help` and
  `--version` too; or `nothing`, and then `main` owns the command line.
- `log_level` — the level the binary logs from when nobody says another:
  `:debug`, `:info`, `:warn`, `:error` or `:none`. Every binary answers
  `--log-level=<level>` over it, so this is the default and not the answer.
- `imports`, `init` and `stand_ins` — passed on to [`write_app_package`](@ref)
  unchanged; the build record names each stand-in.
- `after_write` — a function called with the directory of the written package,
  after the package and its preferences are there and before it is resolved.
  A caller that must put another file into the package, or read what the last
  build wrote there, uses it.
- `resolve` — make the written package loadable, by
  [`resolve_app_project`](@ref). It follows `compile`, because a caller that only
  wants to see what a build would write pays nothing for it; a caller that will
  RUN the package rather than compile it asks for it.
- `precompile` — whether that resolve also precompiles. By default it does not
  when this build compiles, because `create_app` precompiles the same package
  again. A caller whose own `compile_app` does not precompile asks for it.
- `incremental` — build one system image on top of the base one instead of two
  from nothing. **On by default here where `create_app` defaults it to `false`**,
  because a non-incremental build compiles a fresh image from nothing and then,
  because that image holds no stdlibs, compiles every stdlib into it as well; an
  incremental build starts from the running Julia's image, which has them
  already. A distribution build — one a person is handed — asks for
  `incremental = false`, so what they get is the image that holds what it needs
  and no more; the record inside a binary says which it is.
- `cpu_target` — which machines the binary RUNS on, a separate question from
  `incremental`, which asks which image it is built ON. It defaults to
  `native`, on its own terms and whatever `incremental` says. A distribution
  build asks for [`PORTABLE_CPU_TARGET`](@ref) instead.
- `extra_info` — text [`build_info`](@ref) appends after everything it records
  itself, for a caller whose build does something this core does not know
  about.
- `compile_app` — the function that turns the written package into a bundle:
  `compile_app(project, output, name; force, optimization, debug_info,
  strip_metadata, cpu_target, incremental, filter_stdlibs)`. The
  default, [`compile_app!`](@ref), is the plain path with the launcher of
  PackageCompiler. A caller that links its own launcher or trims passes one of
  its own. A reactive build does not call it.
- `reactive` — compile through `PackageCompiler.materialize_app` in place of
  `compile_app`. `true` founds a store under the output on the first build, and
  every later build of the same output reads the tracked sources from disk and
  compiles the edit and no more. `:auto`, the default, rebuilds when the output
  holds a store and builds plain when it does not. `false` builds plain
  although a store exists, and the store goes with the old output. It needs the
  reactive Julia and the branch `reactive` of the fork of PackageCompiler, and
  it builds on the image of the running Julia like `incremental`. See
  `ReactiveBuild.jl`.
- `server` — rebuild through the compiler server that stays between builds
  (the default), or in a child process. The first rebuild starts the server.
  The defaults of this keyword and of `image`, `delta_optimization`, `found`,
  `compact` and `trimmed` are the variables of the reactive compiler
  (`JULIA_REACTIVE_SERVER`, `_IMAGE_WRITE`, `_DELTA_OPT`, `_FOUNDING`,
  `_COMPACT`, `_TRIM`), so a gate of the compiler drives a build through the
  environment and a flag of the command line overrides it.
- `image` — how a rebuild writes the image: `:overlay` (the default), a shared
  object beside the base with the patches and the new objects of the edit, and
  no link of the whole image; `:pages`, the pages of the base that the process
  wrote; `:whole`, the whole image.
- `delta_optimization` — the `-O` level of the code of a rebuild, 0 to 3; by
  default the `optimization` of the build.
- `found` — found the store again now: a whole build. `compact = (saves,
  growth)` does the same by itself after that growth of the image since the
  founding, or, for a store that writes pages or whole images, after that many
  rebuilds.
- `trimmed` — write the trimmed product of the image beside the bundle, under
  `<output>/trimmed`; an edit that makes a call site dynamic is then refused.
- `tracked` — the files that a reactive rebuild watches, as `file =>
  "Module"`, the module being the one whose `include` loads the file. By
  default the sources of every package in `packages`, by
  [`collect_tracked_sources`](@ref). The store adds the sources of every path
  package of the Manifest of the build, on the founding and on each rebuild,
  so a file that joins one of them is tracked from that rebuild on.
- `refresh_trace` — before a reactive rebuild, run the workload once more from
  the current binary and add what it compiles to the trace of the store, the
  roots of the image. An edit that calls new code needs it once, or the binary
  compiles the new code at every start. It needs a store; a founding build
  refuses it.

The caller's active environment is restored on the way out: the build has to
activate the package it wrote, and a prompt must not be left in it.
"""
function build_executable(context::BuildContext; name::AbstractString,
                            packages,
                            main::Expr,
                            precompile_calls::AbstractString = "recorded",
                            preferences = Preference[],
                            performance_counters::Bool = is_performance_counters_requested(),
                            fonts::Bool = false,
                            assets = Pair{String,String}[],
                            usage::Union{Usage,Nothing} = nothing,
                            log_level::Symbol = :warn,
                            imports = String[],
                            init::Union{Nothing,Expr,AbstractString} = nothing,
                            stand_ins = StandIn[],
                            after_write = nothing,
                            incremental::Bool = true,
                            filter_stdlibs::Bool = false,
                            optimization::Integer = 3,
                            debug_info::Integer = 1,
                            strip_metadata::Bool = false,
                            cpu_target::AbstractString = get(ENV, "PROJECTURED_CPU_TARGET", "native"),
                            output::AbstractString = joinpath(context.root, "build", String(name)),
                            compile::Bool = true,
                            resolve::Bool = compile,
                            precompile::Bool = !compile,
                            force::Bool = true,
                            logfile::Union{AbstractString,Nothing} = nothing,
                            extra_info::AbstractString = "",
                            compile_app = compile_app!,
                            reactive::Union{Bool,Symbol} = :auto,
                            tracked::Union{Vector{Pair{String,String}},Nothing} = nothing,
                            refresh_trace::Bool = false,
                            server::Bool = get(ENV, "JULIA_REACTIVE_SERVER", "1") == "1",
                            image::Symbol = Symbol(get(ENV, "JULIA_REACTIVE_IMAGE_WRITE", "overlay")),
                            delta_optimization::Integer = parse(Int, get(ENV, "JULIA_REACTIVE_DELTA_OPT", string(optimization))),
                            found::Bool = get(ENV, "JULIA_REACTIVE_FOUNDING", "") == "1",
                            compact::Tuple{Int,Float64} = _get_reactive_compact_default(),
                            trimmed::Bool = get(ENV, "JULIA_REACTIVE_TRIM", "off") != "off")
    0 <= optimization <= 3 ||
        error("build_executable: `optimization` is 0 to 3, not $optimization")
    0 <= debug_info <= 2 ||
        error("build_executable: `debug_info` is 0 to 2, not $debug_info")
    isempty(packages) &&
        error("build_executable: a binary with no package holds nothing")
    precompile_calls in PRECOMPILE_CALLS_VALUES ||
        error("build_executable: `precompile_calls` is one of " *
              join(PRECOMPILE_CALLS_VALUES, ", ") * ", not $(repr(precompile_calls))")
    # Absolute, because the report runs the executable from wherever the caller
    # happens to be, and a relative path does not survive a change of directory.
    output = abspath(output)
    reactive = _choose_reactive_build(reactive, output, incremental)
    _check_reactive_options(reactive, incremental, performance_counters, tracked,
                            refresh_trace, image, delta_optimization, found, trimmed)
    if reactive
        extra_info *= REACTIVE_RECORD_LINE
        caller_after_write = after_write
        reactive_after_write, compile_app =
            _make_reactive_steps(context, name, packages, output, tracked, found,
                                 refresh_trace, server, image, delta_optimization,
                                 compact, trimmed)
        after_write = project -> begin
            caller_after_write === nothing || caller_after_write(project)
            reactive_after_write(project)
        end
    end
    # The switch of the counters is a preference of the kernel, which reads it when
    # it compiles. A binary that does not hold the kernel has no counters.
    performance_counters &&
        "ProjecturedKernel" in _collect_local_dependencies(context, (packages..., imports...)) &&
        (preferences = Any[preferences,
                           make_baked_preference("ProjecturedKernel", "performance_counters", true)])
    # What each package that compiles ahead compiles into the image.
    compiling = [package for package in _collect_local_dependencies(context, (packages..., imports...))
                 if is_compiling_package(get_package_directory(context, package))]
    preferences = Any[preferences;
                      [make_baked_preference(package, "precompile_calls", String(precompile_calls))
                       for package in sort!(collect(compiling))]]
    # The reader of each preference goes into the written package, or Julia does
    # not read the preference and the image holds the default.
    named = String[String(package) for package in (packages..., imports...)]
    imports = String[String[String(package) for package in imports];
                     _collect_preference_readers(preferences, named,
                                                 get_app_module_name(name))]

    missing_sources = collect_missing_sources(context, vcat(collect(packages), collect(imports)))
    isempty(missing_sources) ||
        error("build_executable: Pkg can not find a dependency whose path the " *
              "[sources] of its user do not give: " *
              join(["$package needs $dependency" for (package, dependency) in missing_sources], ", "))

    info = build_info(; name, packages, main, precompile_calls, preferences,
                        optimization, debug_info, cpu_target, assets, incremental,
                        log_level, extra_info, stand_ins)
    project = write_app_package(context; name, packages, imports, init, main,
                                 info, usage, log_level, stand_ins)
    write_preferences(preferences, project)
    after_write === nothing || after_write(project)
    @info "build_executable: wrote $project\n" * info
    # A caller that only wants to SEE what a build would write pays nothing for
    # it. A caller that will compile the package, or run it, needs it resolved.
    # Skip the precompile only when `compile_app` is going to do it again anyway.
    resolve && resolve_app_project(project; precompile = precompile)
    compile || return project

    compile! = () -> compile_app(project, output, name; force, optimization, debug_info,
                                  strip_metadata, cpu_target, incremental, filter_stdlibs)
    if logfile === nothing
        compile!()
    else
        mkpath(dirname(abspath(logfile)))
        @info "build_executable: compiling — output goes to $(abspath(logfile))"
        open(logfile, "w") do io
            redirect_stdout(io) do
                redirect_stderr(io) do
                    compile!()
                end
            end
        end
    end
    fonts && bundle_fonts!(output)
    bundle_assets!(context, assets, output)
    print_build_report!(output, name)
    output
end

"""
    compile_app!(project, output, name; force, optimization, debug_info,
                  strip_metadata, cpu_target, incremental, filter_stdlibs) -> String

Compile `project` into `output`, with the launcher of PackageCompiler: one
executable, `name => "julia_main"`, and nothing more.

**The plain path.** A caller that links its own launcher, prelinks or trims
passes a `compile_app` of its own to [`build_executable`](@ref) instead of this
one, and a reactive build compiles through `materialize_app`.
"""
function compile_app!(project::AbstractString, output::AbstractString, name::AbstractString;
                       force::Bool = true, optimization::Integer = 3, debug_info::Integer = 1,
                       strip_metadata::Bool = false, cpu_target::AbstractString = "",
                       incremental::Bool = true, filter_stdlibs::Bool = false)
    arguments = `-O$(optimization) -g$(debug_info)`
    strip_metadata && (arguments = `$arguments --strip-metadata`)
    @info "Compiling $name" incremental
    # Splatted in only when it has a value: `create_app` takes a `String` and
    # refuses `nothing`, so an absent one has to be absent rather than empty.
    _create_app(project, output;
                executables = [String(name) => "julia_main"],
                force = force,
                incremental = incremental,
                filter_stdlibs = filter_stdlibs,
                include_lazy_artifacts = true,
                sysimage_build_args = arguments,
                (isempty(cpu_target) ? () : (; cpu_target = String(cpu_target)))...)
    output
end

"""
    get_smoke_flag() -> String

The flag a build report starts a binary with, to measure the start.

**`--build-info` and not `--version`.** Every binary answers `--build-info`,
because the builder writes that line itself; `--version` reaches `main` in a
binary whose build function wrote no usage. A window binary then took the flag
for its project directory and opened a window, so a measurement taken with
`--version` was a hang and not a start.
"""
get_smoke_flag() = "--build-info"

"""
    build_info(; name, packages, main, precompile_calls, preferences, optimization,
                 debug_info, cpu_target, assets, incremental, log_level,
                 extra_info, stand_ins) -> String

What went into a binary, as text. It becomes a constant read at module scope, so
it is compiled into the image and `--build-info` prints it. Written from the same
values the build used, so it cannot drift from what was built.

`extra_info`, when given, is appended after everything this writes itself — for
a caller whose build does something this core does not know about.
"""
function build_info(; name, packages, main, precompile_calls = "recorded", preferences,
                      optimization, debug_info, cpu_target, assets = Pair{String,String}[],
                      incremental::Bool = false, log_level::Symbol = :warn,
                      extra_info::AbstractString = "", stand_ins = StandIn[])
    lines = ["$name, built $(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM")) by ProjecturedBuilder",
             "packages: " * join(packages, ", "),
             "main: " * string(Base.remove_linenums!(copy(main))),
             "precompile_calls: " * String(precompile_calls),
             "compiled at -O$optimization -g$debug_info" *
                 (isempty(cpu_target) ? "" : " for $cpu_target"),
             "logs from $log_level and up, unless --log-level says another"]
    for (source, target) in assets
        push!(lines, "asset: $source -> $target")
    end
    for stand_in in stand_ins
        push!(lines, "stand-in: $(stand_in.name), which this binary does not carry" *
                     (isempty(stand_in.keeps) ? "" :
                      "; it keeps " * join(first.(stand_in.keeps), ", ")))
    end
    # Named in the record, and named so that a person reading it knows what they
    # have. `check_relocation` reads this same line back out of the built binary
    # and refuses to archive it, which is why the wording is a marker and not a
    # sentence — see `INCREMENTAL_MARK`.
    incremental && push!(lines, INCREMENTAL_MARK *
        ": built on top of the base system image, for a rebuild while developing. " *
        "It carries the whole base image and it is not for distribution.")
    for preference in _preferences(preferences)
        push!(lines, "$(preference.package).$(preference.key) = $(repr(preference.value))")
    end
    isempty(extra_info) || push!(lines, extra_info)
    join(lines, "\n") * "\n"
end

"""
    bundle_fonts!(output) -> Nothing

Copy this repository's text faces into the bundle.

`create_app` bundles a package's artifacts and its compiled code. It does not
bundle a file a package opens through a path relative to its own source
directory, and the fonts are exactly that: a `StyleFont` carries the path
`asset/font` had in the projectured-julia checkout when the style package was
compiled — every caller of this builder gets its fonts from there, whichever
repository it builds in, because that is where `ProjecturedPlatform` lives.

`share/projectured/font` is where `ProjecturedPlatform.font_file` looks when the
compiled-in path is not there, relative to the executable. The two have to agree
about the name, and this comment and that function are where they say so.

**A font's licence travels with it.** The licence texts beside the fonts (the
`.txt` files) are copied too: the licences of Lucide and of Noto Emoji ask for
their notice in every copy, and neither font carries it in its own tables.
"""
function bundle_fonts!(output::AbstractString)
    source = normpath(joinpath(@__DIR__, "..", "..", "..", "asset", "font"))
    if !isdir(source)
        @warn "no fonts to bundle: the bundle will read them from wherever the \
               style package was compiled" source
        return nothing
    end
    target = joinpath(output, "share", "projectured", "font")
    mkpath(target)
    for file in readdir(source)
        any(extension -> endswith(file, extension), (".ttf", ".otf", ".txt")) || continue
        cp(joinpath(source, file), joinpath(target, file); force = true)
    end
    @info "Bundled the fonts" target count = length(readdir(target))
    nothing
end

"""
    bundle_assets!(context, assets, output) -> Nothing

Copy each `"<path under context.root>" => "<path under the bundle>"` directory
into the bundle.

The same reason as the fonts: `create_app` bundles a package's artifacts and its
compiled code, and not a directory a package opens through a path relative to its
own source. An asset directory can be sizable, so a binary that shows it has to
carry it, and the `main` a build function writes has to look beside the
executable before it looks where the compiled-in path points.
"""
function bundle_assets!(context::BuildContext, assets, output::AbstractString)
    for (source, target) in assets
        from = joinpath(context.root, String(source))
        isdir(from) || (@warn "no such asset directory" from; continue)
        to = joinpath(output, String(target))
        mkpath(dirname(to))
        cp(from, to; force = true)
        @info "Bundled an asset" from to
    end
    nothing
end

"""
    print_build_report!(output, name) -> nothing

The two numbers every build records: the size of the bundle, and the time the
executable takes to answer [`get_smoke_flag`](@ref). Measured here, so they are
measured the same way every time.
"""
function print_build_report!(output::AbstractString, name::AbstractString)
    size_bytes = parse(Int, split(read(`du -sb $output`, String))[1])
    @info "Built" size_MB = round(size_bytes / 1024^2; digits = 1)
    executable = joinpath(output, "bin", String(name))
    start = time()
    run(pipeline(`$executable $(get_smoke_flag())`; stdout = devnull))
    @info "Started" start_seconds = round(time() - start; digits = 2)
    nothing
end
