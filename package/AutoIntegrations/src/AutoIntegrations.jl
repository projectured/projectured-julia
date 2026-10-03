"""
    AutoIntegrations

Loads an installed package when the packages that it names as its triggers are
loaded, as the environment of the user chooses.

A package takes part with a table in its `Project.toml`. Each trigger is a
package name with its uuid, as in `[weakdeps]`, and a trigger need not be a
dependency of the package:

```toml
[auto-integration]
default = "auto"

[auto-integration.triggers]
Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
SimpleDirectMediaLayer = "98e33af6-2ee5-5afd-9e75-cbc738b767c4"
```

The environment of the user sets the state of a package in the table
`[AutoIntegrations]` of the file `LocalPreferences.toml` beside its
`Project.toml`:

```toml
[AutoIntegrations]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

`"auto"` loads the package when all its triggers are loaded. `"manual"` loads it
only when a `using` line names it. A package with no entry has the state of its
`default`, and a table with no `default` gives `"manual"`. The first environment
of the load path that has an entry decides, so the active project comes first.
[`set_auto_integration!`](@ref) writes an entry. The file is read directly,
because Julia gives the preferences of a package only to an environment that
names the package, and the environment of the user names the packages that it
uses, not this one.

A candidate is a direct dependency of an environment of the load path: the set
that a `using` line in `Main` can reach. So a package loads only when the user
installed it by name. A folder of packages, such as `@stdlib`, gives no
candidate.

After each load of a package, Julia calls the callback of this module. When no
other load is in progress, it loads each candidate that is not loaded, whose
triggers are all loaded and whose state is `"auto"`, until a pass loads nothing, because a loaded package can be the
trigger of another. A loaded candidate binds no name in `Main`. If a candidate
fails to load, a warning names it, the `using` line of the user goes on, and the
session does not try it again. A process that writes a cache file loads nothing,
so no cache file depends on what one user installed.
"""
module AutoIntegrations

using TOML

export set_auto_integration!

"""
    _Candidate

A direct dependency of an environment that declares the table
`[auto-integration]`: the package, the packages that must be loaded before it
loads, and its state when the environment of the user has no entry for it.
"""
struct _Candidate
    package::Base.PkgId
    triggers::Vector{Base.PkgId}
    default::Symbol
end

const _STATES = (:auto, :manual)
const _DECLARATION_TABLE = "auto-integration"
const _PREFERENCES_TABLE = "AutoIntegrations"
const _PREFERENCES_FILES = ("JuliaLocalPreferences.toml", "LocalPreferences.toml")

# The candidates of the load path, and the key of the files they were read from.
const _CANDIDATES = Ref(_Candidate[])
const _CANDIDATES_KEY = Ref{Any}(nothing)

# The candidates that failed to load in this session.
const _FAILED = Set{Base.PkgId}()

# Set while a callback runs, because a load inside the callback calls the
# callbacks again.
const _RUNNING = Threads.Atomic{Bool}(false)

"""
    set_auto_integration!(name, state)

Write the state of the package `name` into the file `LocalPreferences.toml` of
the active project: `:auto` or `:manual`, or `nothing` to remove the entry, so
that the package's own default applies. The state applies from the next load of
a package.
"""
function set_auto_integration!(name::AbstractString, state::Union{Symbol,Nothing})
    state === nothing || state in _STATES ||
        throw(ArgumentError("set_auto_integration!: the state is :auto, :manual or nothing, not :$state"))
    project = Base.active_project()
    project === nothing && error("set_auto_integration!: no project is active")
    folder = dirname(project)
    file = something(_find_preferences_file(folder), joinpath(folder, "LocalPreferences.toml"))
    preferences = isfile(file) ? TOML.parsefile(file) : Dict{String,Any}()
    table = get!(Dict{String,Any}, preferences, _PREFERENCES_TABLE)
    if state === nothing
        delete!(table, String(name))
        isempty(table) && delete!(preferences, _PREFERENCES_TABLE)
    else
        table[String(name)] = String(state)
    end
    open(io -> TOML.print(io, preferences; sorted = true), file, "w")
    nothing
end

# The project files of the environments of the load path, the active project first.
_collect_environment_projects() = filter(isfile, Base.load_path())

# The preferences file beside a project, as Julia finds it: the first that exists.
function _find_preferences_file(folder::AbstractString)
    for name in _PREFERENCES_FILES
        file = joinpath(folder, name)
        isfile(file) && return file
    end
    nothing
end

# The files that the candidates depend on, with their times of change: each
# project file and each manifest beside it. An `add`, an `update` or an
# `activate` changes the key.
function _compute_candidates_key(projects)
    map(projects) do project
        folder = dirname(project)
        manifests = sort!(filter(name -> occursin(r"^(Julia)?Manifest(-v[\d.]+)?\.toml$", name),
                                 readdir(folder)))
        (project, mtime(project), [mtime(joinpath(folder, name)) for name in manifests])
    end
end

# The candidates of the load path, read again only when a file of the key changed.
function _collect_candidates()
    projects = _collect_environment_projects()
    key = _compute_candidates_key(projects)
    key == _CANDIDATES_KEY[] && return _CANDIDATES[]
    candidates = _Candidate[]
    seen = Set{Base.PkgId}()
    for project in projects
        dependencies = get(TOML.parsefile(project), "deps", Dict{String,Any}())
        for (name, uuid) in dependencies
            package = Base.PkgId(Base.UUID(uuid), name)
            package in seen && continue
            push!(seen, package)
            candidate = _find_candidate(package)
            candidate === nothing || push!(candidates, candidate)
        end
    end
    _CANDIDATES[] = candidates
    _CANDIDATES_KEY[] = key
    candidates
end

# The declaration of an installed package, or `nothing` when the package is not
# installed or declares no table.
function _find_candidate(package::Base.PkgId)
    entry = Base.locate_package(package)
    entry === nothing && return nothing
    root = dirname(dirname(entry))
    index = findfirst(name -> isfile(joinpath(root, name)), Base.project_names)
    index === nothing && return nothing
    declaration = get(TOML.parsefile(joinpath(root, Base.project_names[index])),
                      _DECLARATION_TABLE, nothing)
    declaration isa Dict || return nothing
    triggers = Base.PkgId[]
    for (name, uuid) in get(declaration, "triggers", Dict{String,Any}())
        parsed = uuid isa String ? tryparse(Base.UUID, uuid) : nothing
        if parsed === nothing
            @warn "AutoIntegrations: the trigger $name of $(package.name) has no valid uuid"
            return nothing
        end
        push!(triggers, Base.PkgId(parsed, name))
    end
    default = get(declaration, "default", "manual")
    if !(default in ("auto", "manual"))
        @warn "AutoIntegrations: the default of $(package.name) is \"auto\" or \"manual\", not $(repr(default))"
        default = "manual"
    end
    _Candidate(package, triggers, Symbol(default))
end

# The state of a candidate: the first entry of the load path, or its default.
function _find_state(candidate::_Candidate)
    for project in _collect_environment_projects()
        file = _find_preferences_file(dirname(project))
        file === nothing && continue
        table = get(TOML.parsefile(file), _PREFERENCES_TABLE, nothing)
        table isa Dict || continue
        state = get(table, candidate.package.name, nothing)
        state === nothing && continue
        state in ("auto", "manual") && return Symbol(state)
        @warn "AutoIntegrations: the state of $(candidate.package.name) in $file is \"auto\" or \"manual\", not $(repr(state))"
    end
    candidate.default
end

_is_loaded(package::Base.PkgId) = Base.root_module_exists(package)

function _is_ready(candidate::_Candidate)
    !_is_loaded(candidate.package) && !(candidate.package in _FAILED) &&
        all(_is_loaded, candidate.triggers) && _find_state(candidate) === :auto
end

# Load one candidate; answer whether it loaded.
function _load_candidate!(candidate::_Candidate)
    try
        Base.require(candidate.package)
        true
    catch exception
        push!(_FAILED, candidate.package)
        @warn "AutoIntegrations: $(candidate.package.name) failed to load" exception = (exception, catch_backtrace())
        false
    end
end

# Load each ready candidate, until a pass loads nothing.
function _load_ready_candidates!()
    while true
        loaded = false
        for candidate in _collect_candidates()
            _is_ready(candidate) && (loaded |= _load_candidate!(candidate))
        end
        loaded || return nothing
    end
end

# Whether a package loads now. Julia calls the callback of a dependency while the
# package that imports it still loads, and a candidate loaded then could need that
# package and load it a second time. Julia calls the callback of the outer package
# after its load ends, so the callback waits for that one.
_is_any_package_loading() = @lock Base.require_lock !isempty(Base.package_locks)

# The callback after each load of a package. A fault here must not stop the
# `using` line of the user, so it becomes a warning.
function _run_after_load(::Base.PkgId)
    _is_any_package_loading() && return nothing
    Threads.atomic_cas!(_RUNNING, false, true) && return nothing
    try
        _load_ready_candidates!()
    catch exception
        @warn "AutoIntegrations: the automatic load failed" exception = (exception, catch_backtrace())
    finally
        _RUNNING[] = false
    end
    nothing
end

function __init__()
    ccall(:jl_generating_output, Cint, ()) == 1 && return nothing
    push!(Base.package_callbacks, _run_after_load)
    nothing
end

end # module AutoIntegrations
