# Fragment of `ProjecturedBuilder` — a copy of the packages that Pkg can install
# from a registry.
#
# A package of this repository includes its code from `source/<slice>/`, three
# folders above its entry file. Pkg installs only the folder of a package, so an
# installed package would find no `source/`. The release copy puts each package
# in a folder of its own that holds everything it reads: its `Project.toml`
# without `[sources]`, its entry file with the include prefix `../source/`, its
# slice, the folders it reads while it runs, and the licence files. The
# repository keeps its own layout.
#
# One release copy lives in a git repository, and a registry names each package
# of it by the tree of its folder. A package whose content did not change keeps
# its folder byte for byte, so it keeps its tree and gets no new version.

"""
    build_package_release!(context; packages, output, assets, licences,
                           manifest, julia_compat, registry) -> Vector

Write the release copy of `packages` into `output`, one folder per package, and
answer one `(name, status, version)` for each package, dependencies first. That
is the order in which a registry must take them. `status` is `:new`,
`:changed` or `:unchanged`.

- `packages` — the names of the packages to release. Every package of
  `context` that one of them depends on must be among them, or the copy could
  not resolve; a missing one stops the build.
- `output` — the working tree of the release repository. A package folder that
  is already there is the last release of that package. When `output` is a git
  repository, it must have no uncommitted change: the last release is what its
  last commit holds.
- `assets` — `"<package>" => ["<folder of the repository>" => "<folder in the package>", …]`,
  the folders that a package reads while it runs.
- `licences` — files of `context.root` that go into every package folder and
  into `output` itself.
- `manifest` — the manifest whose versions give the `[compat]` bounds of the
  packages from other registries.
- `julia_compat` — the `[compat]` bound of Julia, for a package that names none.
- `registry` — `nothing`, or the registry that serves the release: the name of
  a registry that Pkg reaches, such as `"General"`, or the folder of one. Every
  version of the last release must be in it, or the build stops. A registry
  refuses a version that skips the one before it, so a release that was
  committed and never registered would block every later version of its
  packages.

The copy takes the files that git tracks in `context.root`, so a file that git
ignores, such as a coverage file, never reaches a user.

**The version of a package.** A new package keeps the version of its
`Project.toml`. A package whose content changed gets the next patch version of
its released one, and caret bounds on its sibling packages from their versions
in this release. A package whose content did not change keeps its released
folder as it is, `[compat]` included. The content is every file of the folder,
and the `Project.toml` without `version`, `[compat]` and `[sources]`.

**The check.** Every path that a package reads, in the forms that
[`collect_outside_paths`](@ref) follows, must stay inside its package folder,
and the file or folder it names must exist. The build writes every package into
a staging folder and checks them all first; `output` changes only when every
package passed.
"""
function build_package_release!(context::BuildContext; packages,
                                  output::AbstractString,
                                  assets = Dict{String,Vector{Pair{String,String}}}(),
                                  licences = String[],
                                  manifest::AbstractString = joinpath(context.root, "environment",
                                                                      "all", "Manifest.toml"),
                                  julia_compat::AbstractString = "1.11",
                                  registry::Union{AbstractString,Nothing} = nothing)
    names = String[String(name) for name in packages]
    projects = Dict(name => TOML.parsefile(joinpath(get_package_directory(context, name), "Project.toml"))
                    for name in names)
    _check_release_is_closed(context, projects)
    for licence in licences
        isfile(joinpath(context.root, licence)) ||
            error("build_package_release!: no licence file at $(joinpath(context.root, licence))")
    end
    isfile(manifest) ||
        error("build_package_release!: no manifest at $manifest, so no package of another " *
              "registry would get a [compat] bound")
    registered = _read_registered_versions(manifest)
    output = abspath(String(output))
    mkpath(output)
    _check_release_is_committed(output)
    registry === nothing || _check_release_is_registered(output, names, registry)
    order = _compute_dependency_order(projects)
    staging = mktempdir(get_staging_root())
    results = NamedTuple{(:name, :status, :version),Tuple{String,Symbol,VersionNumber}}[]
    try
        for name in order
            staged = joinpath(staging, name)
            _write_package_content(context, name, staged;
                                   assets = get(assets, name, Pair{String,String}[]), licences)
            outside = collect_outside_paths(staged)
            isempty(outside) ||
                error("build_package_release!: $name reads outside its folder, which an installed " *
                      "package can not do:\n" *
                      join(["  $(relpath(path.file, staged)):$(path.line) → $(path.target)"
                            for path in outside], "\n"))
        end
        versions = Dict{String,VersionNumber}()
        for name in order
            staged, released = joinpath(staging, name), joinpath(output, name)
            status, version = _compute_release_version(staged, released, projects[name])
            versions[name] = version
            status === :unchanged ||
                _write_release_project(joinpath(staged, "Project.toml"), projects[name], version;
                                       versions, registered, julia_compat)
            push!(results, (name = name, status = status, version = version))
        end
        for result in results
            result.status === :unchanged && continue
            released = joinpath(output, result.name)
            rm(released; recursive = true, force = true)
            cp(joinpath(staging, result.name), released)
        end
    finally
        rm(staging; recursive = true, force = true)
    end
    for licence in licences
        cp(joinpath(context.root, licence), joinpath(output, basename(licence)); force = true)
    end
    counts = Dict(status => count(result -> result.status === status, results)
                  for status in (:new, :changed, :unchanged))
    @info("build_package_release!: wrote $output", packages = length(results),
          new = counts[:new], changed = counts[:changed], unchanged = counts[:unchanged])
    results
end

"""
    collect_outside_paths(folder) -> Vector

Every path in the Julia files of `folder` that leaves `folder`, names nothing
there, or can not be followed, as `(file, line, target)`. It follows:

- `include` and `Base.include` of a string literal, or of a `joinpath` of
  literals, relative to the file;
- `joinpath(@__DIR__, …)` and `joinpath(dirname(@__FILE__), …)`, up to the
  first argument that is not a literal.

A `@__DIR__` or a `@__FILE__` anywhere else, and a path through `pkgdir` or
`pathof`, is reported, because the scan can not follow it.
"""
function collect_outside_paths(folder::AbstractString)
    folder = abspath(String(folder))
    found = NamedTuple{(:file, :line, :target),Tuple{String,Int,String}}[]
    for (directory, _, files) in walkdir(folder), file in files
        endswith(file, ".jl") || continue
        path = joinpath(directory, file)
        _collect_outside_paths!(found, Meta.parseall(read(path, String); filename = path),
                                folder, path, Ref(0))
    end
    found
end

function _collect_outside_paths!(found, expression, folder, file, line)
    expression isa LineNumberNode && (line[] = expression.line; return found)
    expression isa Expr || return found
    walk(argument) = _collect_outside_paths!(found, argument, folder, file, line)
    report(target) = (push!(found, (file = file, line = line[], target = target)); found)
    if expression.head === :macrocall
        name = _get_macro_name(expression)
        name === Symbol("@__DIR__") && return report("@__DIR__ outside joinpath")
        name === Symbol("@__FILE__") && return report("@__FILE__ outside joinpath(dirname(…))")
    end
    if expression.head === :call && !isempty(expression.args)
        callee, arguments = _get_callee_name(expression.args[1]), expression.args[2:end]
        callee in (:pkgdir, :pathof) && return report("a path through $callee")
        if callee === :include && !isempty(arguments)
            literals = _get_literal_path(last(arguments))
            literals === nothing ||
                _check_release_path!(found, folder, file, line[], joinpath(dirname(file), literals...))
            foreach(walk, arguments)
            return found
        end
        if callee === :joinpath && !isempty(arguments) && _is_source_directory(arguments[1])
            literals = String[]
            for argument in arguments[2:end]
                argument isa String || break
                push!(literals, argument)
            end
            _check_release_path!(found, folder, file, line[], joinpath(dirname(file), literals...))
            foreach(walk, arguments[2:end])
            return found
        end
    end
    foreach(walk, expression.args)
    found
end

# `include`, `Base.include` → `:include`; anything else that is not a name → `nothing`.
_get_callee_name(callee::Symbol) = callee
_get_callee_name(callee::Expr) =
    callee.head === :. && callee.args[end] isa QuoteNode ? callee.args[end].value : nothing
_get_callee_name(_) = nothing

# `@__DIR__` and `Base.@__DIR__` both answer `Symbol("@__DIR__")`.
_get_macro_name(expression::Expr) = _get_callee_name(expression.args[1])

# `@__DIR__`, or `dirname(@__FILE__)`: the folder of the file itself.
function _is_source_directory(expression)
    expression isa Expr || return false
    expression.head === :macrocall && return _get_macro_name(expression) === Symbol("@__DIR__")
    expression.head === :call && length(expression.args) == 2 &&
        _get_callee_name(expression.args[1]) === :dirname &&
        expression.args[2] isa Expr && expression.args[2].head === :macrocall &&
        _get_macro_name(expression.args[2]) === Symbol("@__FILE__")
end

# The parts of a path that is a string literal or a `joinpath` of literals, or
# `nothing` for any other expression.
function _get_literal_path(expression)
    expression isa String && return [expression]
    expression isa Expr && expression.head === :call && !isempty(expression.args) &&
        _get_callee_name(expression.args[1]) === :joinpath &&
        all(argument -> argument isa String, expression.args[2:end]) &&
        return String[argument for argument in expression.args[2:end]]
    nothing
end

function _check_release_path!(found, folder, file, line, target)
    target = normpath(target)
    inside = target == normpath(folder * "/") || startswith(target, normpath(folder * "/"))
    (inside && ispath(target)) || push!(found, (file = file, line = line, target = target))
    found
end

# Every dependency of a released package that is a package of `context` must be
# released too.
function _check_release_is_closed(context::BuildContext, projects)
    missing_packages = String[]
    for (name, project) in projects, dependency in keys(get(project, "deps", Dict{String,Any}()))
        has_package_directory(context, dependency) && !haskey(projects, dependency) &&
            push!(missing_packages, "$name → $dependency")
    end
    isempty(missing_packages) ||
        error("build_package_release!: these packages depend on a package that the release " *
              "leaves out:\n  " * join(sort!(missing_packages), "\n  "))
end

# A release repository with an uncommitted change holds a release that no commit
# records, so a registry could never name its trees.
function _check_release_is_committed(output)
    isdir(joinpath(output, ".git")) || return nothing
    changes = read(`git -C $output status --porcelain`, String)
    isempty(changes) ||
        error("build_package_release!: $output has changes that are not committed. Commit " *
              "them, and register the versions they hold, before the next release:\n" * changes)
    nothing
end

# Every package that the last release holds has its version in `registry`.
function _check_release_is_registered(output, names, registry::AbstractString)
    released = filter(name -> isfile(joinpath(output, name, "Project.toml")), names)
    isempty(released) && return nothing
    instance = _find_registry(registry)
    missing_versions = String[]
    for name in released
        project = TOML.parsefile(joinpath(output, name, "Project.toml"))
        entry = get(instance.pkgs, Base.UUID(project["uuid"]), nothing)
        version = VersionNumber(project["version"])
        (entry !== nothing && version in _collect_registered_versions(instance, entry)) ||
            push!(missing_versions, "$name $version")
    end
    isempty(missing_versions) ||
        error("build_package_release!: the last release holds versions that $registry does " *
              "not, and the next version of each would skip one. Register them first:\n  " *
              join(missing_versions, "\n  "))
    nothing
end

# A registry by the name under which Pkg reaches it, or by its folder.
function _find_registry(registry::AbstractString)
    isdir(registry) && return Pkg.Registry.RegistryInstance(registry)
    for instance in Pkg.Registry.reachable_registries()
        instance.name == registry && return instance
    end
    error("build_package_release!: Pkg reaches no registry called $registry, and no folder " *
          "has that path")
end

# `Pkg.Registry.registry_info` takes the registry too from Julia 1.13 on.
function _collect_registered_versions(instance, entry)
    info = applicable(Pkg.Registry.registry_info, instance, entry) ?
        Pkg.Registry.registry_info(instance, entry) : Pkg.Registry.registry_info(entry)
    collect(keys(info.version_info))
end

_get_sibling_names(project, projects) =
    sort!([dependency for dependency in keys(get(project, "deps", Dict{String,Any}()))
           if haskey(projects, dependency)])

function _compute_dependency_order(projects)
    order, seen = String[], Set{String}()
    function visit(name)
        name in seen && return
        push!(seen, name)
        foreach(visit, _get_sibling_names(projects[name], projects))
        push!(order, name)
    end
    foreach(visit, sort!(collect(keys(projects))))
    order
end

function _compute_release_version(staged, released, project)
    isfile(joinpath(released, "Project.toml")) ||
        return :new, VersionNumber(project["version"])
    previous = TOML.parsefile(joinpath(released, "Project.toml"))
    version = VersionNumber(previous["version"])
    _compute_content_digest(staged, project) == _compute_content_digest(released, previous) &&
        return :unchanged, version
    :changed, VersionNumber(version.major, version.minor, version.patch + 1)
end

# The files of `folder` under `context.root` that git tracks, as paths relative
# to `context.root`.
function _collect_tracked_files(context::BuildContext, folder::AbstractString)
    listing = read(`git -C $(context.root) ls-files -z -- $folder`, String)
    tracked = filter(!isempty, split(listing, '\0'))
    isempty(tracked) &&
        error("build_package_release!: git tracks no file under $(joinpath(context.root, folder))")
    String.(tracked)
end

function _copy_tracked_files(context::BuildContext, from::AbstractString, to::AbstractString)
    for path in _collect_tracked_files(context, from)
        destination = joinpath(to, relpath(path, from))
        mkpath(dirname(destination))
        cp(joinpath(context.root, path), destination)
    end
end

# The files of one package folder. Its `Project.toml` is the one of the
# repository until `_write_release_project` writes the released one.
function _write_package_content(context::BuildContext, name, destination; assets, licences)
    package = relpath(get_package_directory(context, name), context.root)
    mkpath(destination)
    for path in _collect_tracked_files(context, joinpath(package, "src"))
        text = read(joinpath(context.root, path), String)
        for match in eachmatch(r"include\(\"\.\./\.\./\.\./source/([A-Za-z0-9_]+)/", text)
            slice = match.captures[1]
            target = joinpath(destination, "source", slice)
            isdir(target) || _copy_tracked_files(context, joinpath("source", slice), target)
        end
        target = joinpath(destination, relpath(path, package))
        mkpath(dirname(target))
        write(target, replace(text, "include(\"../../../source/" => "include(\"../source/"))
    end
    for (from, to) in assets
        _copy_tracked_files(context, from, joinpath(destination, to))
    end
    for licence in licences
        cp(joinpath(context.root, licence), joinpath(destination, basename(licence)))
    end
    cp(joinpath(context.root, package, "Project.toml"), joinpath(destination, "Project.toml"))
end

# A digest of what a user of the package gets: every file, each with its length,
# and the `Project.toml` without `version`, `[compat]` and `[sources]`.
function _compute_content_digest(folder, project)
    content = IOBuffer()
    for (directory, _, files) in walkdir(folder), file in sort(files)
        path = joinpath(directory, file)
        relative = relpath(path, folder)
        relative == "Project.toml" && continue
        bytes = read(path)
        write(content, relative, "\n", string(length(bytes)), "\n", bytes)
    end
    identity_project = Dict(key => value for (key, value) in project
                            if key ∉ ("version", "compat", "sources"))
    TOML.print(content, identity_project; sorted = true)
    bytes2hex(sha256(take!(content)))
end

# The version of every package of a manifest that came from a registry, without
# its build suffix: a `[compat]` entry can not name one. A standard library and
# a package reached by path carry no tree hash.
function _read_registered_versions(manifest::AbstractString)
    dependencies = get(TOML.parsefile(manifest), "deps", Dict{String,Any}())
    versions = Dict{String,VersionNumber}()
    for (name, entries) in dependencies
        entry = entries[1]
        (haskey(entry, "git-tree-sha1") && haskey(entry, "version")) || continue
        version = VersionNumber(entry["version"])
        versions[name] = VersionNumber(version.major, version.minor, version.patch)
    end
    versions
end

const _PROJECT_KEY_ORDER = Dict("name" => 1, "uuid" => 2, "version" => 3, "authors" => 4,
                                "deps" => 5, "compat" => 6)

function _write_release_project(path, project, version; versions, registered, julia_compat)
    released = Dict{String,Any}(key => value for (key, value) in project if key != "sources")
    released["version"] = string(version)
    compat = Dict{String,Any}(get(project, "compat", Dict{String,Any}()))
    for dependency in keys(get(project, "deps", Dict{String,Any}()))
        if haskey(versions, dependency)
            compat[dependency] = string(versions[dependency])
        elseif !haskey(compat, dependency) && haskey(registered, dependency)
            compat[dependency] = string(registered[dependency])
        end
    end
    haskey(compat, "julia") || (compat["julia"] = String(julia_compat))
    released["compat"] = compat
    open(path, "w") do io
        TOML.print(io, released; sorted = true, by = key -> (get(_PROJECT_KEY_ORDER, key, 99), key))
    end
end
