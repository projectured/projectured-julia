# Fragment of `BuilderModule` — a copy of the packages that Pkg can install
# from a registry.
#
# A package of this repository includes its code from `source/<group>/<slice>/`, three
# folders above its entry file. Pkg installs only the folder of a package, so an
# installed package would find no `source/`. The release copy puts each package
# in a folder of its own that holds everything it reads: its `Project.toml`
# without `[sources]`, its entry file, its slice under `src/` (`source/<path>`
# becomes `src/<path>`, and the include names the path from `src/`), the folders
# it reads while it runs, and the licence files. `source/` and `src/` are both one
# folder below the root, so a file keeps its depth, and a path from `@__DIR__`
# reaches the same folder. The repository keeps its own layout.
#
# The release copy is one git repository with a folder for each package,
# `<Name>/`, and the test and example packages that the tests need in
# `test/<Name>/` and `example/<Name>/`. A registry names each version of a package by the tree of its
# folder. A package whose content did not change keeps its folder byte for byte,
# so it keeps its tree and gets no new version.

"""
    build_package_release!(context; packages, output, assets, licences, readme,
                           tests, workflow, overview, manifest, julia_compat,
                           registry) -> Vector

Write the release copy of `packages` into `output`, one folder per package, and
answer one `(name, folder, status, version)` for each package and each support
package, dependencies first. That is the order in which a registry must take
them, and `folder` is where the package is in `output`. `status` is `:new`,
`:changed` or `:unchanged`.

- `packages` — the names of the packages to release. Every package of
  `context` that one of them depends on, or names as a weak dependency, must be
  among them, or the copy could not resolve; a missing one stops the build.
- `output` — the working tree of the release repository. A package folder
  that is already there, `<output>/<Name>/`, is the last release of that
  package. When `output` is a git repository, it must have no uncommitted
  change: the last release is what its last commit holds. The build changes
  only the folders of the changed packages, and the licence files, the
  workflow and the overview at the root.
- `assets` —
  `"<package>" => ["<folder of the repository>" => "<folder in the package>", …]`,
  the folders that a package reads while it runs, a package of `tests` too.
- `licences` — files of `context.root` that go into every package folder and
  into `output` itself.
- `readme` — `nothing`, or a function `readme(name)` whose text goes into the
  `README.md` of each package folder.
- `tests` — `nothing`, or a function `tests(name)` that answers `nothing` or
  `"<test package>" => "<text of runtests.jl>"`: the package of `context` whose
  suite tests `name`. The copy writes `test/` with that `runtests.jl` and a
  `test/Project.toml` that names the test package. The test package and every
  package of `context` that it needs and `packages` leaves out are the support
  packages: each one is released once, a test package in `test/<Name>/` and an
  example package in `example/<Name>/`, with a version as any package. A
  registry holds them, so `Pkg.test` of an installed package installs them as
  it installs any dependency.
- `workflow` — `nothing`, or a function `workflow(jobs)` whose text goes into
  `.github/workflows/<name>.yml` at the root of `output`, one file for each
  package with a `test/runtests.jl`, so each one has a badge of its own. `jobs`
  holds the one `(name, develop, coverage)` of that package: `develop`, the folders that a test of the commit
  develops into the environment of `Pkg.test(name)`, and `coverage`, the
  folders of its code. `develop` holds the folders of the released packages
  and the support packages that the test needs, `name` included and
  dependencies first. A package reaches its siblings through a registry, which
  holds a version only after its commit, so the test develops their folders
  instead.
- `overview` — `nothing`, or a function `overview(names)` whose text goes into
  `README.md` at the root of `output`, the front page of the release
  repository. `names` are the released packages, dependencies first.
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
in this release, its weak dependencies too. A package whose content did not change keeps its released
folder as it is, `[compat]` and `test/` included. The content is every file of
the folder but those of `test/`, and the `Project.toml` without `version`,
`[compat]` and `[sources]`: a change of a test gives no released package a new
version. A support package counts the files of its `test/` too, because a test
package keeps its suite there, so a change of a test gives the test package a
new version.

**The check.** Every path that a package reads, in the forms that
[`collect_outside_paths`](@ref) follows, must stay inside its package folder,
and the file or folder it names must exist. In `test/`, a form that the scan can
not follow is accepted: a test reads the folder of its own file, and an
installed package by `pathof`. The build writes every package into
a staging folder and checks them all first; `output` changes only when every
package passed.
"""
function build_package_release!(context::BuildContext; packages,
                                  output::AbstractString,
                                  assets = Dict{String,Vector{Pair{String,String}}}(),
                                  licences = String[],
                                  readme = nothing,
                                  tests = nothing,
                                  workflow = nothing,
                                  overview = nothing,
                                  manifest::AbstractString = joinpath(context.root,
                                      "environment", "all", "Manifest.toml"),
                                  julia_compat::AbstractString = "1.11",
                                  registry::Union{AbstractString,Nothing} = nothing)
    names = String[String(name) for name in packages]
    projects = Dict(name => TOML.parsefile(joinpath(get_package_directory(context, name),
                                                    "Project.toml"))
                    for name in names)
    _check_release_is_closed(context, projects)
    for licence in licences
        isfile(joinpath(context.root, licence)) ||
            error("build_package_release!: no licence file at " *
                  "$(joinpath(context.root, licence))")
    end
    isfile(manifest) ||
        error("build_package_release!: no manifest at $manifest, so no package of " *
              "another registry would get a [compat] bound")
    registered = _read_registered_versions(manifest)
    # A package that the manifest reaches by path and that `context` does not hold
    # is a package of a sibling repository, which a registry holds as a package of
    # its own: it gets the bound of the version that the manifest names.
    for (name, version) in _read_path_versions(manifest)
        has_package_directory(context, name) || (registered[name] = version)
    end
    # The suite of each released package, and the support packages: its test
    # package and every package of `context` that this needs and the release
    # leaves out. A support package is released once, in `test/` or `example/`,
    # and a registry holds it, so the test of an installed package reaches it as
    # it reaches any dependency.
    suites = Dict{String,Pair{String,String}}()
    for name in names
        suite = tests === nothing ? nothing : tests(name)
        suite === nothing || (suites[name] = suite)
    end
    support = sort!(unique([found for (test_package, _) in values(suites)
                            for found in _collect_support_packages(context, test_package,
                                                                   names)]))
    folders = Dict{String,String}(name => name for name in names)
    for name in support
        folders[name] = _get_support_folder(name)
        projects[name] = TOML.parsefile(joinpath(get_package_directory(context, name),
                                                 "Project.toml"))
    end
    output = abspath(String(output))
    mkpath(output)
    _check_release_is_committed(output)
    registry === nothing || _check_release_is_registered(output, folders, registry)
    order = _compute_dependency_order(projects)
    staging = mktempdir(get_staging_root())
    results = NamedTuple{(:name, :folder, :status, :version),
                         Tuple{String,String,Symbol,VersionNumber}}[]
    try
        for name in order
            staged = joinpath(staging, folders[name])
            package_assets = get(assets, name, Pair{String,String}[])
            if name in support
                _write_support_package(context, name, staged; assets = package_assets,
                                       licences)
            else
                _write_package_content(context, name, staged; assets = package_assets,
                                       licences)
                readme === nothing || write(joinpath(staged, "README.md"), readme(name))
                haskey(suites, name) && _write_release_tests(context, staged, suites[name])
            end
            accepted = name in support ? _is_accepted_support_path : _is_accepted_test_path
            outside = filter(path -> !accepted(staged, path), collect_outside_paths(staged))
            isempty(outside) ||
                error("build_package_release!: $name reads outside its folder, which " *
                      "an installed " *
                      "package can not do:\n" *
                      join(["  $(relpath(path.file, staged)):$(path.line) → " *
                            "$(path.target)"
                            for path in outside], "\n"))
        end
        versions = Dict{String,VersionNumber}()
        for name in order
            staged, released = joinpath(staging, folders[name]), joinpath(output, folders[name])
            status, version = _compute_release_version(staged, released, projects[name];
                                                       whole = name in support)
            versions[name] = version
            status === :unchanged ||
                _write_release_project(joinpath(staged, "Project.toml"), projects[name],
                                       version;
                                       versions, registered, julia_compat)
            push!(results, (name = name, folder = folders[name], status = status,
                            version = version))
        end
        for result in results
            result.status === :unchanged && continue
            released = joinpath(output, result.folder)
            rm(released; recursive = true, force = true)
            mkpath(dirname(released))
            cp(joinpath(staging, result.folder), released)
        end
    finally
        rm(staging; recursive = true, force = true)
    end
    for licence in licences
        cp(joinpath(context.root, licence), joinpath(output, basename(licence)); force = true)
    end
    workflow === nothing || _write_release_workflow(output, workflow, order, folders)
    overview === nothing ||
        write(joinpath(output, "README.md"), overview(filter(!in(support), order)))
    counts = Dict(status => count(result -> result.status === status, results)
                  for status in (:new, :changed, :unchanged))
    @info("build_package_release!: wrote $output", packages = length(results),
          new = counts[:new], changed = counts[:changed], unchanged = counts[:unchanged])
    results
end

"""
    collect_outside_paths(folder) -> Vector

Every path in the Julia files of `folder` that leaves `folder`, names nothing
there, or can not be followed, as `(file, line, target, kind)`. `kind` is
`:include` for a file that a file includes, `:path` for a path that the code
reads when it runs, and `:form` for a form that the scan can not follow; the
`target` of a `:form` says the form. It follows:

- `include` and `Base.include` of a string literal, or of a `joinpath` of
  literals, relative to the file;
- `joinpath(@__DIR__, …)` and `joinpath(dirname(@__FILE__), …)`, up to the
  first argument that is not a literal.

A `@__DIR__` or a `@__FILE__` anywhere else, and a path through `pkgdir` or
`pathof`, is reported, because the scan can not follow it.
"""
function collect_outside_paths(folder::AbstractString)
    folder = abspath(String(folder))
    found = NamedTuple{(:file, :line, :target, :kind),Tuple{String,Int,String,Symbol}}[]
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
    report(target) =
        (push!(found, (file = file, line = line[], target = target, kind = :form)); found)
    if expression.head === :macrocall
        name = _get_macro_name(expression)
        name === Symbol("@__DIR__") && return report("@__DIR__ outside joinpath")
        name === Symbol("@__FILE__") &&
            return report("@__FILE__ outside joinpath(dirname(…))")
    end
    if expression.head === :call && !isempty(expression.args)
        callee, arguments = _get_callee_name(expression.args[1]), expression.args[2:end]
        callee in (:pkgdir, :pathof) && return report("a path through $callee")
        if callee === :include && !isempty(arguments)
            literals = _get_literal_path(last(arguments))
            literals === nothing ||
                _check_release_path!(found, folder, file, line[],
                                     joinpath(dirname(file), literals...), :include)
            foreach(walk, arguments)
            return found
        end
        if callee === :joinpath && !isempty(arguments) &&
           _is_source_directory(arguments[1])
            literals = String[]
            for argument in arguments[2:end]
                argument isa String || break
                push!(literals, argument)
            end
            _check_release_path!(found, folder, file, line[],
                                 joinpath(dirname(file), literals...), :path)
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
    callee.head === :. && callee.args[end] isa QuoteNode ?
        callee.args[end].value : nothing
_get_callee_name(_) = nothing

# `@__DIR__` and `Base.@__DIR__` both answer `Symbol("@__DIR__")`.
_get_macro_name(expression::Expr) = _get_callee_name(expression.args[1])

# `@__DIR__`, or `dirname(@__FILE__)`: the folder of the file itself.
function _is_source_directory(expression)
    expression isa Expr || return false
    expression.head === :macrocall &&
        return _get_macro_name(expression) === Symbol("@__DIR__")
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

function _check_release_path!(found, folder, file, line, target, kind)
    target = normpath(target)
    (_is_inside_folder(folder, target) && ispath(target)) ||
        push!(found, (file = file, line = line, target = target, kind = kind))
    found
end

_is_inside_folder(folder, target) =
    target == normpath(folder * "/") || startswith(target, normpath(folder * "/"))

# Every dependency of a released package that is a package of `context` must be
# released too.
function _check_release_is_closed(context::BuildContext, projects)
    missing_packages = String[]
    for (name, project) in projects, dependency in _get_dependency_names(project)
        has_package_directory(context, dependency) && !haskey(projects, dependency) &&
            push!(missing_packages, "$name → $dependency")
    end
    isempty(missing_packages) ||
        error("build_package_release!: these packages depend on a package that the " *
              "release leaves out:\n  " *
              join(sort!(missing_packages), "\n  "))
end

# A release repository with an uncommitted change holds a release that no commit
# records, so a registry could never name its trees.
function _check_release_is_committed(output)
    isdir(joinpath(output, ".git")) || return nothing
    changes = read(`git -C $output status --porcelain`, String)
    isempty(changes) ||
        error("build_package_release!: $output has changes that are not committed. " *
              "Commit them, and register the versions they hold, before the next " *
              "release:\n" *
              changes)
    nothing
end

# The workflow of the release repository: one job for each package of `order`
# that has tests, with the folders that its test develops and the folders of its
# code. It reads the folders as the release leaves them, so a package that keeps
# its released folder gets the jobs of its released tests.
function _write_release_workflow(output, workflow, order, folders)
    jobs = [(name = name,
             develop = _collect_release_test_closure(output, name, order, folders),
             coverage = [joinpath(name, folder) for folder in ("src", "ext")
                         if isdir(joinpath(output, name, folder))])
            for name in order
            if folders[name] == name && isfile(joinpath(output, name, "test", "runtests.jl"))]
    # One workflow for each package, so each one has a badge of its own. The
    # release owns the folder, so a workflow of a package that has no tests any
    # more goes away.
    folder = joinpath(output, ".github", "workflows")
    isdir(folder) && foreach(file -> endswith(file, ".yml") && rm(joinpath(folder, file)),
                             readdir(folder))
    mkpath(folder)
    for job in jobs
        write(joinpath(folder, "$(job.name).yml"), workflow([job]))
    end
    nothing
end

# The folders of the packages that `Pkg.test(name)` needs in its environment,
# `name` included, in the order of `order`: what `name` and its test project
# depend on, and what those depend on in turn, released packages and support
# packages alike. A job develops each one, because a job reaches no registry
# that holds them.
function _collect_release_test_closure(output, name, order, folders)
    projects = [joinpath(output, folders[name], "Project.toml"),
                joinpath(output, folders[name], "test", "Project.toml")]
    found = Set([name])
    while !isempty(projects)
        project = TOML.parsefile(pop!(projects))
        for dependency in keys(get(project, "deps", Dict{String,Any}()))
            (dependency in order && !(dependency in found)) || continue
            push!(found, dependency)
            push!(projects, joinpath(output, folders[dependency], "Project.toml"))
        end
    end
    [folders[package] for package in order if package in found]
end

# Every package that the last release holds has its version in `registry`.
function _check_release_is_registered(output, folders, registry::AbstractString)
    released = sort!([name for (name, folder) in folders
                      if isfile(joinpath(output, folder, "Project.toml"))])
    isempty(released) && return nothing
    instance = _find_registry(registry)
    missing_versions = String[]
    for name in released
        project = TOML.parsefile(joinpath(output, folders[name], "Project.toml"))
        entry = get(instance.pkgs, Base.UUID(project["uuid"]), nothing)
        version = VersionNumber(project["version"])
        (entry !== nothing && version in _collect_registered_versions(instance, entry)) ||
            push!(missing_versions, "$name $version")
    end
    isempty(missing_versions) ||
        error("build_package_release!: the last release holds versions that $registry " *
              "does not, and the next version of each would skip one. Register them " *
              "first:\n  " *
              join(missing_versions, "\n  "))
    nothing
end

# A registry by the name under which Pkg reaches it, or by its folder.
function _find_registry(registry::AbstractString)
    isdir(registry) && return Pkg.Registry.RegistryInstance(registry)
    for instance in Pkg.Registry.reachable_registries()
        instance.name == registry && return instance
    end
    error("build_package_release!: Pkg reaches no registry called $registry, and no " *
          "folder has that path")
end

# `Pkg.Registry.registry_info` takes the registry too from Julia 1.13 on.
function _collect_registered_versions(instance, entry)
    info = applicable(Pkg.Registry.registry_info, instance, entry) ?
        Pkg.Registry.registry_info(instance, entry) : Pkg.Registry.registry_info(entry)
    collect(keys(info.version_info))
end

# The dependencies and the weak dependencies of a project, by name: a weak one is a
# package that an extension needs, and it gets a `[compat]` bound and an order in
# the registration as a dependency does.
_get_dependency_names(project) =
    union(keys(get(project, "deps", Dict{String,Any}())),
          keys(get(project, "weakdeps", Dict{String,Any}())))

_get_sibling_names(project, projects) =
    sort!([dependency for dependency in _get_dependency_names(project)
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

function _compute_release_version(staged, released, project; whole::Bool = false)
    isfile(joinpath(released, "Project.toml")) ||
        return :new, VersionNumber(project["version"])
    previous = TOML.parsefile(joinpath(released, "Project.toml"))
    version = VersionNumber(previous["version"])
    _compute_content_digest(staged, project; whole) ==
        _compute_content_digest(released, previous; whole) &&
        return :unchanged, version
    :changed, VersionNumber(version.major, version.minor, version.patch + 1)
end

# The files of `folder` under `context.root` that git tracks, as paths relative
# to `context.root`.
function _collect_tracked_files(context::BuildContext, folder::AbstractString)
    listing = read(`git -C $(context.root) ls-files -z -- $folder`, String)
    tracked = filter(!isempty, split(listing, '\0'))
    isempty(tracked) &&
        error("build_package_release!: git tracks no file under " *
              "$(joinpath(context.root, folder))")
    String.(tracked)
end

# `from` is a folder or a file of the repository, and `to` the same in the copy.
function _copy_tracked_files(context::BuildContext, from::AbstractString,
                             to::AbstractString)
    for path in _collect_tracked_files(context, from)
        destination = path == from ? to : joinpath(to, relpath(path, from))
        mkpath(dirname(destination))
        cp(joinpath(context.root, path), destination)
    end
end

# The longest folder that each of `folders` starts with, such as `source/platform`.
function _get_common_folder(folders)
    parts = [split(folder, "/") for folder in folders]
    depth = 0
    while all(p -> length(p) > depth && p[depth + 1] == parts[1][depth + 1], parts)
        depth += 1
    end
    join(parts[1][1:depth], "/")
end

# The files of one package folder. Its `Project.toml` is the one of the
# repository until `_write_release_project` writes the released one.
function _write_package_content(context::BuildContext, name, destination;
                                assets, licences)
    package = relpath(get_package_directory(context, name), context.root)
    mkpath(destination)
    for path in _collect_tracked_files(context, joinpath(package, "src"))
        text = read(joinpath(context.root, path), String)
        # The source of a package is the common folder of the files that its entry
        # file includes: one slice, or a whole group for the platform.
        included = [dirname(found.captures[1]) for found in
                    eachmatch(r"include\(\"\.\./\.\./\.\./(source/[^\"]+)\"\)", text)]
        if !isempty(included)
            folder = _get_common_folder(included)
            target = joinpath(destination, "src", relpath(folder, "source"))
            isdir(target) || _copy_tracked_files(context, folder, target)
        end
        target = joinpath(destination, relpath(path, package))
        mkpath(dirname(target))
        write(target, replace(text, "include(\"../../../source/" => "include(\""))
    end
    # The extensions of a package include nothing of the repository.
    isdir(joinpath(context.root, package, "ext")) &&
        _copy_tracked_files(context, joinpath(package, "ext"), joinpath(destination, "ext"))
    # The recorded precompile statements of a package, which AutoPrecompile reads
    # from the folder of a loaded package.
    isdir(joinpath(context.root, package, "precompile")) &&
        _copy_tracked_files(context, joinpath(package, "precompile"),
                            joinpath(destination, "precompile"))
    for (from, to) in assets
        _copy_tracked_files(context, from, joinpath(destination, to))
    end
    for licence in licences
        cp(joinpath(context.root, licence), joinpath(destination, basename(licence)))
    end
    cp(joinpath(context.root, package, "Project.toml"),
       joinpath(destination, "Project.toml"))
end

# The test folder of one released package: `runtests.jl`, and a `Project.toml`
# that names the test package. The release holds the test package once, in
# `test/`, and a registry holds it, so `Pkg.test` of an installed package
# installs it as it installs any dependency.
function _write_release_tests(context::BuildContext, staged, test)
    test_package, runtests = test
    folder = joinpath(staged, "test")
    mkpath(folder)
    project = Dict{String,Any}("deps" => Dict{String,Any}(
        test_package => _read_package_uuid(context, test_package)))
    open(io -> TOML.print(io, project; sorted = true), joinpath(folder, "Project.toml"), "w")
    write(joinpath(folder, "runtests.jl"), runtests)
    nothing
end

# The folder of a support package in the release: `test/<name>` for a test
# package, and `example/<name>` for an example package.
function _get_support_folder(name)
    endswith(name, "Test") && return joinpath("test", name)
    endswith(name, "Example") && return joinpath("example", name)
    error("build_package_release!: the test of a released package needs $name, which " *
          "is no test package and no example package; release it, or name it so")
end

# The test package and every package of `context` that it needs and `released`
# leaves out, by name.
function _collect_support_packages(context::BuildContext, test_package, released)
    found = String[]
    function visit(name)
        name in found && return
        push!(found, name)
        project = TOML.parsefile(joinpath(get_package_directory(context, name), "Project.toml"))
        for dependency in keys(get(project, "deps", Dict{String,Any}()))
            has_package_directory(context, dependency) && !(dependency in released) &&
                visit(dependency)
        end
    end
    visit(test_package)
    sort!(found)
end

_read_package_uuid(context::BuildContext, name) =
    TOML.parsefile(joinpath(get_package_directory(context, name), "Project.toml"))["uuid"]

# One support package: its `src/` with the prefix `../../../` of a path into this
# repository changed to `../`, the folders that those paths name, the folders it
# reads while it runs, the licence files, and its `Project.toml` without
# `[sources]`: every package that it depends on comes from a registry.
function _write_support_package(context::BuildContext, name, destination; assets, licences)
    package = relpath(get_package_directory(context, name), context.root)
    mkpath(destination)
    folders = String[]
    for path in _collect_tracked_files(context, joinpath(package, "src"))
        text = read(joinpath(context.root, path), String)
        for found in eachmatch(r"\"\.\./\.\./\.\./([^\"]+)\"", text)
            target = rstrip(found.captures[1], '/')
            push!(folders, isdir(joinpath(context.root, target)) ? target : dirname(target))
        end
        target = joinpath(destination, relpath(path, package))
        mkpath(dirname(target))
        write(target, replace(text, "\"../../../" => "\"../"))
    end
    for folder in _collect_covering_folders(folders)
        _copy_tracked_files(context, folder, joinpath(destination, folder))
    end
    for (from, to) in assets
        _copy_tracked_files(context, from, joinpath(destination, to))
    end
    for licence in licences
        cp(joinpath(context.root, licence), joinpath(destination, basename(licence)))
    end
    project = TOML.parsefile(joinpath(context.root, package, "Project.toml"))
    delete!(project, "sources")
    open(joinpath(destination, "Project.toml"), "w") do io
        TOML.print(io, project; sorted = true,
                   by = key -> (get(_PROJECT_KEY_ORDER, key, 99), key))
    end
end

# The folders of `folders` that no other folder of the list holds.
function _collect_covering_folders(folders)
    candidates = sort!(unique(String.(folders)))
    filter(folder -> !any(other -> startswith(folder, other * "/"), candidates), candidates)
end

# A finding of the scan in `test/` that the tests answer for themselves: a form
# that the scan can not follow, such as the folder of the file or `pathof` of an
# installed package, and a path inside the package that names nothing yet, which
# a test reads only when it runs. An `include` must name a file, and no path may
# leave the package.
_is_accepted_test_path(staged, path) =
    startswith(path.file, joinpath(staged, "test") * Base.Filesystem.path_separator) &&
    (path.kind === :form || (path.kind === :path && _is_inside_folder(staged, path.target)))

# A finding of the scan in a support package: a form that the scan can not
# follow, and a path inside the package that names nothing yet. An `include` must
# name a file, and no path may leave the package.
_is_accepted_support_path(staged, path) =
    path.kind === :form || (path.kind === :path && _is_inside_folder(staged, path.target))

# A digest of what a user of the package gets: every file but those of `test/`,
# each with its length, and the `Project.toml` without `version`, `[compat]` and
# `[sources]`. With `whole`, the files of `test/` count too: a test package keeps
# its suite there.
function _compute_content_digest(folder, project; whole::Bool = false)
    content = IOBuffer()
    for (directory, _, files) in walkdir(folder), file in sort(files)
        path = joinpath(directory, file)
        relative = relpath(path, folder)
        (relative == "Project.toml" ||
         (!whole && startswith(relative, "test" * Base.Filesystem.path_separator))) &&
            continue
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

# The version of every package of a manifest that it reaches by path.
function _read_path_versions(manifest::AbstractString)
    dependencies = get(TOML.parsefile(manifest), "deps", Dict{String,Any}())
    versions = Dict{String,VersionNumber}()
    for (name, entries) in dependencies
        entry = entries[1]
        (haskey(entry, "path") && haskey(entry, "version")) || continue
        versions[name] = VersionNumber(entry["version"])
    end
    versions
end

const _PROJECT_KEY_ORDER = Dict("name" => 1, "uuid" => 2, "version" => 3, "authors" => 4,
                                "deps" => 5, "weakdeps" => 6, "extensions" => 7,
                                "compat" => 8)

function _write_release_project(path, project, version;
                                versions, registered, julia_compat)
    released = Dict{String,Any}(key => value for (key, value) in project
                                if key != "sources")
    released["version"] = string(version)
    compat = Dict{String,Any}(get(project, "compat", Dict{String,Any}()))
    for dependency in _get_dependency_names(project)
        if haskey(versions, dependency)
            compat[dependency] = string(versions[dependency])
        elseif !haskey(compat, dependency) && haskey(registered, dependency)
            compat[dependency] = string(registered[dependency])
        end
    end
    haskey(compat, "julia") || (compat["julia"] = String(julia_compat))
    released["compat"] = compat
    open(path, "w") do io
        TOML.print(io, released; sorted = true,
                   by = key -> (get(_PROJECT_KEY_ORDER, key, 99), key))
    end
end
