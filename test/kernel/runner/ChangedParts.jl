# ============================================================================
# The parts of what changed.
#
# A change reaches the tests of the code that it changes and of the code that
# uses that code. The packages of the repository say which code uses which: the
# `[deps]` of each `Project.toml`. Inside one package, a table of the edges
# between its slices says it more finely. The result is a selection for a quick
# check after a change; the whole suites still run before a land.
# ============================================================================

# One package of the repository: its name, the names of the packages of the
# repository that it depends on, and the common folder of the files that it
# includes from `source/` or from `test/`.
struct _RepositoryPackage
    name::String
    dependencies::Vector{String}
    folder::String
end

function _common_folder(paths::Vector{String})
    isempty(paths) && return ""
    parts = splitpath.(paths)
    depth = 0
    while all(p -> length(p) > depth && p[depth + 1] == parts[1][depth + 1], parts)
        depth += 1
    end
    depth == 0 ? "" : join(parts[1][1:depth], "/")
end

function _repository_packages(root::AbstractString)
    folder = joinpath(root, "package")
    isdir(folder) || return _RepositoryPackage[]
    names = Set(entry for entry in readdir(folder)
                if isfile(joinpath(folder, entry, "Project.toml")))
    packages = _RepositoryPackage[]
    for name in sort(collect(names))
        project = read(joinpath(folder, name, "Project.toml"), String)
        section = match(r"(?ms)^\[deps\]\s*\n(.*?)(?:^\[|\z)", project)
        dependencies = section === nothing ? String[] :
            [m.captures[1] for m in eachmatch(r"(?m)^\s*(\w+)\s*=", section.captures[1])
             if m.captures[1] in names]
        entry = joinpath(folder, name, "src", name * ".jl")
        included = String[]
        if isfile(entry)
            for m in eachmatch(r"(?m)^\s*include\(\"([^\"]+)\"\)", read(entry, String))
                path = relpath(normpath(joinpath(dirname(entry), m.captures[1])), root)
                startswith(path, "source/") || startswith(path, "test/") || continue
                push!(included, path)
            end
        end
        push!(packages, _RepositoryPackage(name, dependencies, _common_folder(dirname.(included))))
    end
    packages
end

# The names of the packages that depend on `name`, also through other packages.
function _package_users(packages::Vector{_RepositoryPackage}, name::String)
    users = Set{String}()
    frontier = [name]
    while !isempty(frontier)
        current = pop!(frontier)
        for package in packages
            current in package.dependencies && !(package.name in users) || continue
            push!(users, package.name)
            push!(frontier, package.name)
        end
    end
    users
end

# The slices that use `slice`, also through other slices, from a table of the
# slices that each slice may use.
function _slice_users(edges::AbstractDict, slice::AbstractString)
    users = Set{String}()
    frontier = [String(slice)]
    while !isempty(frontier)
        current = pop!(frontier)
        for (user, used) in edges
            current in used && !(user in users) || continue
            push!(users, user)
            push!(frontier, user)
        end
    end
    users
end

_test_folder_of(source_folder::AbstractString) = "test" * source_folder[length("source") + 1:end]

"""
    reached_test_paths(root, changed; slice_edges = Dict()) -> Set{String}

The test files and the test folders of the repository at `root` that a change of
the files `changed` reaches, as paths from `root`:

- a changed file under `test/` reaches itself;
- a changed file of a package reaches the test folder of the package and the test
  folders of each package of the repository that depends on it, also through
  other packages; the test folder of a package is `test/` and the folder of its
  source under `source/`, and that of a test package the folder of its files;
- inside a source folder that `slice_edges` names, such as `"source/platform" =>
  PLATFORM_SLICE_EDGES`, a changed file of a slice reaches the test folder of the
  slice and those of the slices that use it, also through other slices, in place
  of the test folder of the whole package.
"""
function reached_test_paths(root::AbstractString, changed::AbstractVector{<:AbstractString};
                            slice_edges::AbstractDict = Dict{String, Any}())
    packages = _repository_packages(root)
    sources = [p for p in packages if startswith(p.folder, "source/")]
    reached = Set{String}()
    for file in changed
        if startswith(file, "test/")
            push!(reached, file)
            continue
        end
        owner = nothing
        for package in sources
            is_own = startswith(file, package.folder * "/") ||
                     startswith(file, "package/$(package.name)/")
            if is_own
                (owner === nothing || length(package.folder) > length(owner.folder)) &&
                    (owner = package)
            end
        end
        owner === nothing && continue
        sliced = nothing
        for (folder, edges) in slice_edges
            startswith(file, folder * "/") && (sliced = (folder, edges))
        end
        if sliced === nothing
            push!(reached, _test_folder_of(owner.folder))
        else
            folder, edges = sliced
            slice = first(splitpath(file[length(folder) + 2:end]))
            for name in union(Set([slice]), _slice_users(edges, slice))
                push!(reached, _test_folder_of(folder * "/" * name))
            end
        end
        # Each package that uses the owner: the test folder of a source package, the
        # folder of a test package, except the own test package of the owner, whose
        # folder the lines above reach or, for a package of slices, reach by slice.
        own = _test_folder_of(owner.folder)
        for user in _package_users(packages, owner.name)
            folder = packages[findfirst(p -> p.name == user, packages)].folder
            folder = startswith(folder, "source/") ? _test_folder_of(folder) : folder
            isempty(folder) || folder == own || push!(reached, folder)
        end
    end
    reached
end

"""
    changed_files(root; base = "main") -> Vector{String}

The files of the repository at `root` that differ from the commit where the
branch left `base`: the committed changes, the changes that are not committed,
and the new files that git does not ignore, as paths from `root`.
"""
function changed_files(root::AbstractString; base::AbstractString = "main")
    fork = _git_text(root, `merge-base $base HEAD`)
    isempty(fork) && error("git finds no common commit of $base and HEAD in $root")
    listed = vcat(split(_git_text(root, `diff --name-only $fork`), '\n'),
                  split(_git_text(root, `ls-files --others --exclude-standard`), '\n'))
    sort!(unique!(String.(filter(!isempty, listed))))
end

# The path of the file of a part from `root`, or "" when it is outside `root`.
function _part_path(part::TestPart, root::AbstractString)
    file = _method_file(part.run)
    isempty(file) && return ""
    path = relpath(file, root)
    startswith(path, "..") ? "" : path
end

_is_reached(path::AbstractString, reached) =
    !isempty(path) && any(r -> path == r || startswith(path, r * "/"), reached)

"""
    select_changed_parts(suite::TestSuite, root, reached) -> Union{TestSuite, Nothing}

The suite with only the parts whose file is a path in `reached`, or under one, as
[`reached_test_paths`](@ref) gives them; `nothing` when no part is left.
"""
function select_changed_parts(suite::TestSuite, root::AbstractString, reached)
    kept = Union{TestPart, TestSuite}[]
    for entry in suite.entries
        if entry isa TestSuite
            inner = select_changed_parts(entry, root, reached)
            inner === nothing || push!(kept, inner)
        elseif _is_reached(_part_path(entry, root), reached)
            push!(kept, entry)
        end
    end
    isempty(kept) ? nothing : TestSuite(suite.name, kept)
end

"""
    run_changed_parts(suite::TestSuite; base = "main", slice_edges = Dict(), keywords...)

Run the parts of `suite` that the changes since `base` reach, with the other
keywords of [`run_suite`](@ref). The repository is the one of the first part of
`suite`. It prints the changed files and the test paths that they reach.
"""
function run_changed_parts(suite::TestSuite; base::AbstractString = "main",
                           slice_edges::AbstractDict = Dict{String, Any}(), keywords...)
    first_part = _first_part(suite)
    file = first_part === nothing ? "" : _method_file(first_part.run)
    root = _git_text(isfile(file) ? dirname(file) : pwd(), `rev-parse --show-toplevel`)
    changed = changed_files(root; base)
    reached = reached_test_paths(root, changed; slice_edges)
    println("$(length(changed)) files changed since $base; they reach: ",
            isempty(reached) ? "no test" : join(sort(collect(reached)), ", "))
    chosen = select_changed_parts(suite, root, reached)
    chosen === nothing && (println("No part of $(suite.name) is reached."); return nothing)
    run_suite(chosen; keywords...)
end
