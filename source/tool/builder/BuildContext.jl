# Fragment of `BuilderModule` — the repository a build writes into, and how
# it finds a package by name.
#
# A build function names no repository: the caller passes a `BuildContext`, and
# every path the builder writes — the app package under `build/app/`, the
# compiled binary under `build/<name>/` — is relative to its `root`. So the same
# builder writes the binaries of this repository and of a downstream program, one context
# each, and neither repository's name appears in the code that does the writing.

"""
    BuildContext(root; package_roots, log_variable, statements, version)

Where a build writes, and where it looks up a package's directory and uuid.

- `root` — the repository whose `build/app/` and `build/<name>/` a build
  writes into.
- `package_roots` — folders that hold packages, searched in order by
  [`get_package_directory`](@ref). Defaults to `[joinpath(root, "package")]`; a
  caller whose packages live in more than one checkout lists every one, in the
  order it wants them searched.
- `log_variable` — the environment variable that sets the log level of a
  binary this context builds, read behind `--log-level` on the command line and
  ahead of the baked default. Defaults to `"PROJECTURED_LOG_LEVEL"`.
- `statements` — a precompile statements file [`compile_app!`](@ref) passes to
  `create_app`, or `nothing`.
- `version` — the text `--version` prints after the binary's name. Defaults to
  `"0.1.0"`.
"""
struct BuildContext
    root::String
    package_roots::Vector{String}
    log_variable::String
    statements::Union{String,Nothing}
    version::String
end

function BuildContext(root::AbstractString;
                       package_roots = [joinpath(root, "package")],
                       log_variable::AbstractString = "PROJECTURED_LOG_LEVEL",
                       statements::Union{AbstractString,Nothing} = nothing,
                       version::AbstractString = "0.1.0")
    BuildContext(String(root), String[String(p) for p in package_roots], String(log_variable),
                 statements === nothing ? nothing : String(statements), String(version))
end

"""
    get_package_directory(context, name) -> String

Where the package called `name` lives, searched in `context.package_roots` in
order. This is why a build function names no package's directory itself: it
names the package as a string, and this resolves it. A root holds packages in
folders of their names, or is the folder of one package itself, as the
repository of a package of another repository is.
"""
function get_package_directory(context::BuildContext, name::AbstractString)
    for root in context.package_roots
        here = joinpath(root, String(name))
        isdir(here) && return here
        _is_package_root(root, name) && return root
    end
    error("get_package_directory: no package called $(repr(name)) in " *
          join(context.package_roots, " or "))
end

"""
    has_package_directory(context, name) -> Bool

Whether a folder of `context.package_roots` holds the package called `name`.
"""
has_package_directory(context::BuildContext, name::AbstractString) =
    any(root -> isfile(joinpath(root, String(name), "Project.toml")) || _is_package_root(root, name),
        context.package_roots)

# Whether `root` is itself the folder of the package called `name`.
function _is_package_root(root::AbstractString, name::AbstractString)
    project = joinpath(root, "Project.toml")
    isfile(project) && get(TOML.parsefile(project), "name", nothing) == name
end

"""
    collect_missing_sources(context, packages) -> Vector{Pair{String,String}}

Every `package => dependency` in the dependency tree of `packages` where
`dependency` is a package of `context.package_roots` and the `[sources]` table
of `package` gives no path for it. No registry holds such a dependency, so Pkg
can not resolve the package that a build writes.
"""
function collect_missing_sources(context::BuildContext, packages)
    missing_sources = Pair{String,String}[]
    seen = Set{String}()
    pending = String[String(package) for package in packages]
    while !isempty(pending)
        name = pop!(pending)
        (name in seen || !has_package_directory(context, name)) && continue
        push!(seen, name)
        project = TOML.parsefile(joinpath(get_package_directory(context, name), "Project.toml"))
        sources = get(project, "sources", Dict{String,Any}())
        for dependency in keys(get(project, "deps", Dict{String,Any}()))
            has_package_directory(context, dependency) || continue
            haskey(sources, dependency) || push!(missing_sources, name => dependency)
            push!(pending, dependency)
        end
    end
    sort!(missing_sources)
end

"The uuid a package answers to, read from its own `Project.toml`."
get_package_uuid(directory::AbstractString) =
    TOML.parsefile(joinpath(directory, "Project.toml"))["uuid"]

"""
    make_projectured_build_context() -> BuildContext

The context of this repository, projectured-julia: `root` is found by walking
up from `@__DIR__` to a directory that holds `CLAUDE.md` and `package/`, so the
context is right wherever this package is checked out.
"""
function make_projectured_build_context()
    directory = @__DIR__
    while true
        isfile(joinpath(directory, "CLAUDE.md")) &&
            isdir(joinpath(directory, "package")) && return BuildContext(directory)
        parent = dirname(directory)
        parent == directory &&
            error("make_projectured_build_context: no repository root above $(@__DIR__)")
        directory = parent
    end
end
