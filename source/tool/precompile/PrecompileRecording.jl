# Fragment of `PrecompileModule` — the recording: run the workload of a package
# in a new process under `--trace-compile`, keep the calls that it compiled, and
# write them into the folder `precompile/` of the package that owns them.

"""
    find_repository_root(path = Base.active_project()) -> Union{String,Nothing}

The repository that holds `path`: the nearest folder above it with a folder
`package/`. Answers `nothing` when there is none.
"""
function find_repository_root(path::AbstractString = something(Base.active_project(), pwd()))
    folder = isdir(path) ? abspath(path) : dirname(abspath(path))
    while true
        isdir(joinpath(folder, "package")) && return folder
        parent = dirname(folder)
        parent == folder && return nothing
        folder = parent
    end
end

function _get_default_root()
    root = find_repository_root()
    root === nothing &&
        error("The active environment is not in a repository with a folder `package/`.")
    root
end

"""
    is_compiling_package(folder) -> Bool

Whether the entry file of the package in `folder`, `src/<name>.jl`, calls
[`@compile_ahead`](@ref).
"""
function is_compiling_package(folder::AbstractString)
    entry = joinpath(folder, "src", basename(normpath(folder)) * ".jl")
    isfile(entry) && occursin(r"(?m)^\s*@compile_ahead\b", read(entry, String))
end

"""
    has_package_workload(folder) -> Bool

Whether the entry file of the package in `folder` calls
[`@compile_ahead`](@ref) with a workload, and not alone.
"""
function has_package_workload(folder::AbstractString)
    entry = joinpath(folder, "src", basename(normpath(folder)) * ".jl")
    isfile(entry) || return false
    text = read(entry, String)
    occursin(r"(?m)^\s*@compile_ahead\b", text) && !occursin(r"(?m)^\s*@compile_ahead\s*$", text)
end

"""
    collect_compiling_packages(root) -> Vector{String}

The packages in `root/package/` whose entry file calls
[`@compile_ahead`](@ref), sorted by name.
"""
collect_compiling_packages(root::AbstractString) =
    [name for name in sort!(readdir(joinpath(root, "package")))
     if is_compiling_package(joinpath(root, "package", name))]

"""
    collect_package_closures(environment) -> Dict{String,Set{String}}

Each package of the manifest of `environment`, with the set of the packages that
it sees: itself and each package that it depends on, directly or through
others.
"""
function collect_package_closures(environment::AbstractString)
    manifest = TOML.parsefile(joinpath(environment, "Manifest.toml"))
    direct = Dict{String,Vector{String}}()
    for (name, entries) in get(manifest, "deps", Dict())
        deps = get(first(entries), "deps", String[])
        direct[name] = deps isa AbstractDict ? collect(keys(deps)) : collect(deps)
    end
    closures = Dict{String,Set{String}}()
    function visit(name)
        haskey(closures, name) && return closures[name]
        seen = closures[name] = Set([name])
        for dependency in get(direct, name, String[])
            union!(seen, visit(dependency))
        end
        seen
    end
    foreach(visit, keys(direct))
    closures
end

# The modules that `call` names: the first name of each dotted name, and each
# bare name, as `Pkg` in `Base.Val{Pkg}`. The caller keeps only the names of
# packages, so a bare name of a type counts for nothing.
function _collect_call_roots(call::AbstractString)
    roots = Set{String}()
    function visit(x)
        x isa Symbol && push!(roots, String(x))
        x isa Expr || return
        if x.head === :.
            first = x
            while first isa Expr
                first = first.args[1]
            end
            first isa Symbol && push!(roots, String(first))
        else
            foreach(visit, x.args)
        end
    end
    visit(try Meta.parse(call) catch; nothing end)
    roots
end

"""
    find_call_owner(call, candidates, closures; fallback) -> String

The package of `candidates` that keeps `call`: a package that sees each package
that the call names, the lowest in the graph of the dependencies. Of two that
are equally low, the one that more candidates depend on wins, and then the name
decides. Answers `fallback`, the package of the application, when no candidate
sees them all.
"""
function find_call_owner(call::AbstractString, candidates, closures::AbstractDict;
                         fallback::AbstractString)
    roots = filter(root -> haskey(closures, root), _collect_call_roots(call))
    seeing = [candidate for candidate in candidates
              if haskey(closures, candidate) && issubset(roots, closures[candidate])]
    isempty(seeing) && return String(fallback)
    lowest = [candidate for candidate in seeing
              if !any(other -> other != candidate && other in closures[candidate], seeing)]
    count_dependents(candidate) =
        count(other -> haskey(closures, other) && candidate in closures[other], candidates)
    String(first(sort!(lowest; by = candidate -> (-count_dependents(candidate), candidate))))
end

"""
    compute_call_owners(calls, candidates, closures; fallback) -> Dict{String,Vector{String}}

The calls of a recording, by the package that keeps them, as
[`find_call_owner`](@ref) chooses it.
"""
function compute_call_owners(calls, candidates, closures::AbstractDict;
                             fallback::AbstractString)
    owners = Dict{String,Vector{String}}()
    for call in calls
        push!(get!(owners, find_call_owner(call, candidates, closures; fallback), String[]), call)
    end
    foreach(sort!, values(owners))
    owners
end

"""
    collect_traced_calls(trace) -> Vector{String}

The calls of a file that `--trace-compile` wrote, once each and sorted, so that
a new recording makes a diff that a person can read. A call that names `Main`
belongs to the command of the recording, and a call that does not parse cannot
be read back, so both are dropped, and so is a call of
`ProjecturedPrecompile` itself, which belongs to no package.
"""
function collect_traced_calls(trace::AbstractString)
    prefix = "precompile("
    kept = Set{String}()
    for line in eachline(trace)
        line = strip(replace(line, r"^#=.*?=#\s*" => "", r"\)\s*#[^)]*$" => ")"))
        (startswith(line, prefix) && endswith(line, ")")) || continue
        (occursin("Main.", line) || occursin("ProjecturedPrecompile.", line)) && continue
        call = line[(length(prefix) + 1):(end - 1)]
        _is_complete_call(call) && push!(kept, call)
    end
    sort!(collect(kept))
end

function _is_complete_call(call::AbstractString)
    parsed = Meta.parse(call; raise = false)
    !(parsed isa Expr && parsed.head in (:error, :incomplete))
end

"""
    write_recorded_calls!(path, calls; workload) -> String

Write `calls` as the recorded list `path`, which names the workload that
recorded it. With no calls, remove the file. Answers `path`.
"""
function write_recorded_calls!(path::AbstractString, calls; workload::AbstractString)
    if isempty(calls)
        rm(path; force = true)
        return path
    end
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# The calls that the workload of ", workload, " compiled, recorded by")
        println(io, "# ProjecturedPrecompile. Record them again; do not edit this file.")
        foreach(call -> println(io, call), calls)
    end
    path
end

function _get_package_uuid(root::AbstractString, package::AbstractString)
    project = joinpath(root, "package", package, "Project.toml")
    isfile(project) || error("There is no package ", package, " in ", root, ".")
    TOML.parsefile(project)["uuid"]
end

# An environment that sets `precompile_calls = "none"` for `package`. First on
# the load path of a process, its preference wins over the one of the active
# project. It names the package under `[extras]` only, which a preference needs
# and which loads nothing.
function _write_none_environment!(folder::AbstractString, package::AbstractString,
                                  uuid::AbstractString)
    write(joinpath(folder, "Project.toml"), string("[extras]\n", package, " = \"", uuid, "\"\n"))
    write(joinpath(folder, "LocalPreferences.toml"),
          string("[", package, "]\nprecompile_calls = \"none\"\n"))
    folder
end

"""
    trace_package_calls(package; root, environment, display, threads) -> Vector{String}

Run `run_package_workload()` of `package` in a new process under
`--trace-compile`, and answer the calls that it compiled, as
[`collect_traced_calls`](@ref) keeps them. The process loads `package` at
`precompile_calls = "none"`, because a call that the image already holds does
not compile again and the trace would not see it. A first process with no trace
builds the images, so that the trace holds no call of the build. With
`display = false` the processes open no display: SDL runs on its dummy video
driver. When the workload fails, the recording keeps the calls that it compiled
before the failure and shows the failure in a warning.

The trace holds the calls that the run dispatched to, and each one compiles
with the calls that inference resolved inside it, so a build that compiles the
list compiles those again too.
"""
function trace_package_calls(package::AbstractString;
                             root::AbstractString = _get_default_root(),
                             environment::AbstractString = joinpath(root, "environment", "all"),
                             display::Bool = false,
                             threads::Integer = 2)
    trace = tempname() * ".jl"
    preferences = _write_none_environment!(mktempdir(), package, _get_package_uuid(root, package))
    load_path = join([preferences; LOAD_PATH], Sys.iswindows() ? ';' : ':')
    julia = `$(Base.julia_cmd()) --startup-file=no --project=$environment --threads=$threads`
    variables = Pair{String,String}["JULIA_LOAD_PATH" => load_path]
    display || push!(variables, "SDL_VIDEODRIVER" => "dummy")
    failure = tempname()
    try
        run(addenv(`$julia -e $("import $package")`, variables...))
        script = """
            import $package
            try
                $package.run_package_workload()
            catch exception
                write($(repr(failure)), sprint(showerror, exception))
            end
            exit(0)
            """
        run(addenv(`$julia --trace-compile=$trace -e $script`, variables...))
        isfile(failure) &&
            @warn string("The workload of ", package, " failed, so the recording holds the ",
                         "calls that it compiled before the failure. ", read(failure, String))
        collect_traced_calls(trace)
    finally
        rm(trace; force = true)
        rm(failure; force = true)
        rm(preferences; recursive = true, force = true)
    end
end

"""
    record_package_calls!(package; root, environment, display, threads) -> String

Record the workload of `package` into `precompile/workload.txt` of the package,
as [`trace_package_calls`](@ref) traces it. Answers the path.
"""
function record_package_calls!(package::AbstractString;
                               root::AbstractString = _get_default_root(), kwargs...)
    calls = trace_package_calls(package; root, kwargs...)
    path = joinpath(root, "package", package, "precompile", "workload.txt")
    write_recorded_calls!(path, calls; workload = package)
end

"""
    record_repository_calls!(; root, environment, display, threads) -> Vector{String}

Record the workload of each package of the repository `root` that calls
[`@compile_ahead`](@ref) with a workload, each one after the packages that it
depends on. Answers the paths.
"""
function record_repository_calls!(; root::AbstractString = _get_default_root(),
                                  environment::AbstractString = joinpath(root, "environment", "all"),
                                  kwargs...)
    packages = filter(package -> has_package_workload(joinpath(root, "package", package)),
                      collect_compiling_packages(root))
    closures = collect_package_closures(environment)
    count_below(package) = count(other -> other in get(closures, package, Set{String}()), packages)
    sort!(packages; by = package -> (count_below(package), package))
    [record_package_calls!(package; root, environment, kwargs...) for package in packages]
end

"""
    record_application_calls!(package, application; root, environment, display, threads) -> Vector{String}

Record the workload of `package`, the package of the binary `application`, and
write each call into `precompile/<application>.txt` of the package of the
repository that keeps it, as [`compute_call_owners`](@ref) chooses. The other
packages keep their own recorded calls while the workload runs, so this records
only the calls that their own workloads do not compile. The old files of
`application` go first, so that their calls compile again and the trace sees
them.

A package that loads later can make the code of a call invalid in the image of
the lower package that keeps it. So at the end the recording records the
workload of `package` again, into its `precompile/workload.txt`, with the new
files in place: that trace holds each call that the binary still compiles,
also each call that compiles again, and the package of the application, which
loads last, keeps it. Answers the paths that it wrote.
"""
function record_application_calls!(package::AbstractString, application::AbstractString;
                                   root::AbstractString = _get_default_root(),
                                   environment::AbstractString = joinpath(root, "environment", "all"),
                                   kwargs...)
    file = application * ".txt"
    candidates = collect_compiling_packages(root)
    for candidate in candidates
        rm(joinpath(root, "package", candidate, "precompile", file); force = true)
    end
    calls = trace_package_calls(package; root, environment, kwargs...)
    owners = compute_call_owners(calls, candidates, collect_package_closures(environment);
                                 fallback = package)
    paths = [write_recorded_calls!(joinpath(root, "package", owner, "precompile", file), owned;
                                   workload = application)
             for (owner, owned) in sort!(collect(owners); by = first)]
    push!(paths, record_package_calls!(package; root, environment, kwargs...))
    paths
end

"""
    compare_display_recordings(package; root, environment, threads)
        -> (; with_display_only, without_display_only)

Trace the workload of `package` once with a display and once without, and
answer the calls that only one of the two compiled. Both lists are empty when a
recording with no display gives the same result. Needs a display.
"""
function compare_display_recordings(package::AbstractString; kwargs...)
    with_display = Set(trace_package_calls(package; display = true, kwargs...))
    without_display = Set(trace_package_calls(package; display = false, kwargs...))
    (with_display_only = sort!(collect(setdiff(with_display, without_display))),
     without_display_only = sort!(collect(setdiff(without_display, with_display))))
end
