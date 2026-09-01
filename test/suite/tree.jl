# ============================================================================
# The guard — one dimension per level.
#
# `plan/done/repository-tree.md` §3 states what each top-level folder may not
# hold. This is that, as a check.
#
# **Written before the move, deliberately.** Three of the six rules are VACUOUS
# today, because `source/`, `example/` and `environment/` do not exist yet. A
# rule asserted after a move records what happened to be true; a rule asserted
# before it says what was intended, and it fails the first step that gets it
# wrong. So this passes now, and every step of §8 has to keep it passing.
#
# **Static, and deliberately.** It reads directory entries, `Project.toml` files
# and `include` lines. It loads nothing, so it runs in well under a second and
# cannot be fooled by what happens to be in a session.
# ============================================================================

# Two keys of a `Project.toml` are all this guard reads, and a regex reads them.
# `using TOML` would make the standard library a declared dependency of every
# package that includes this file, and `test_package_graph()` asserts that a
# package declares exactly what its source names.
_project_key(text, key) =
    (m = match(Regex("(?m)^\\s*" * key * " = \"([^\"]+)\""), text)) === nothing ?
        nothing : m.captures[1]

"""
    _tracked_manifests(root) -> Vector{String}

Every `Manifest.toml` git holds, as a repository-relative path. This is the one
place the guard asks git anything: an untracked manifest is a local artifact and
a tracked one is a decision, and no directory entry can tell the two apart. When
git cannot answer, every manifest is reported rather than none — a guard that
goes quiet is the failure this file exists to catch.
"""
function _tracked_manifests(root::AbstractString)
    try
        out = readchomp(Cmd(`git ls-files "*Manifest.toml"`; dir = root))
        return isempty(out) ? String[] : split(out, "\n")
    catch
        found = String[]
        for (dir, _, files) in walkdir(root), file in files
            file == "Manifest.toml" &&
                push!(found, relpath(joinpath(dir, file), root))
        end
        return found
    end
end

_entries(path) = isdir(path) ? sort!(readdir(path)) : String[]
_subdirs(path) = filter(d -> isdir(joinpath(path, d)), _entries(path))
_jl(path) = filter(f -> endswith(f, ".jl"), _entries(path))

"""
    source_violations(root) -> Vector{String}

**`source/` holds no `Project.toml` and no `Manifest.toml`.** Source is
material. A package is a name and an include list, and the two need not share a
directory. A project file under `source/` means one of them drifted back.
"""
function source_violations(root::AbstractString)
    out = String[]
    base = joinpath(root, "source")
    isdir(base) || return out
    for (dir, _, files) in walkdir(base), file in files
        file == "Project.toml" &&
            push!(out, "$(relpath(joinpath(dir, file), root)) — source/ holds no package")
        file == "Manifest.toml" &&
            push!(out, "$(relpath(joinpath(dir, file), root)) — source/ holds no environment")
    end
    out
end

"""
    package_violations(root) -> Vector{String}

**A package directory holds its `Project.toml`, its root file under `src/`, and
nothing else.**

No `Manifest.toml` — that is what makes a package double as an environment,
which is the entanglement this tree exists to undo. No second `.jl` — a second
one is source, and source lives in `source/`. No folder but `src/`, `ext/` and
`deps/`, which are Julia's choice and not this tree's: the loader finds a root at
`src/<Name>.jl`, `pkgdir` derives the package directory from it, and `Pkg.build`
runs `deps/build.jl` from the package directory and nowhere else. A flat root
loads and then `pkgdir` throws, which is how omnet-julia found this.

The per-directory half is skipped while **any** slice still has the
`<slice>/<kind>` shape, so it bites once §8 step 5 flattens the last of them.
Gating on the whole folder rather than on each directory is deliberate:
`package/repl/` is already at the flat depth and would otherwise be held to a
rule the tree around it does not yet obey. The `Manifest.toml` half is checked
at every depth and bites **today**.
"""
function package_violations(root::AbstractString)
    out = String[]
    base = joinpath(root, "package")
    isdir(base) || return out

    # No package may also be an environment — but only a **tracked** manifest
    # says that. Activating a package directory is a documented way to run one
    # suite without the SDL stack (`julia --project=package/ProjecturedKernelTest`),
    # and that writes a `Manifest.toml` there. `.gitignore` covers it; it is a
    # local resolution artifact, like a compile cache, not a checked-in
    # environment. The five this rule caught were all tracked.
    for file in _tracked_manifests(root)
        startswith(file, "package/") || continue
        isfile(joinpath(root, dirname(file), "Project.toml")) || continue
        push!(out, "$file — a package that also resolves an environment; " *
                   "the environments live in environment/")
    end

    # Still the `<slice>/<kind>` shape somewhere? Then the rules below are not
    # yet the tree's rules, and holding one directory to them says nothing.
    #
    # The test is for a **package** at `<slice>/<kind>`, not for a directory.
    # `git mv` moves files, and a directory whose last tracked file left survives
    # on any untracked thing still in it — a build log, an allocation profile, a
    # stale manifest. Six of those survived the flatten here, and while this
    # gate tested `isdir` they switched the whole rule off and the guard
    # reported that every folder held one kind of thing. That is the failure
    # this file exists to catch, committed by this file.
    for name in _subdirs(base), kind in ("main", "test", "example")
        isfile(joinpath(base, name, kind, "Project.toml")) && return out
    end

    for name in _subdirs(base)
        directory = joinpath(base, name)
        # A directory here that is not a package is a leftover of the flatten,
        # and `continue` on it is how one hid: `package/adaptagrams/` kept its
        # `deps/` after everything else had moved out.
        if !isfile(joinpath(directory, "Project.toml"))
            push!(out, "package/$name — a directory under package/ that is not a package")
            continue
        end
        text = read(joinpath(directory, "Project.toml"), String)
        package = _project_key(text, "name")
        package === nothing && continue                           # an environment, reported elsewhere
        _project_key(text, "entryfile") === nothing ||
            push!(out, "package/$name — names an `entryfile`; the root is src/$package.jl")
        # `runtests.jl` is Julia's, not this tree's: `Pkg.test` looks for it in
        # the package directory and nowhere else.
        roots = filter(!=("runtests.jl"), _jl(directory))
        isempty(roots) ||
            push!(out, "package/$name — holds $(length(roots)) `.jl` file(s) beside its " *
                       "Project.toml; the root is src/$package.jl")
        isfile(joinpath(directory, "src", package * ".jl")) ||
            push!(out, "package/$name — has no src/$package.jl")
        for sub in _subdirs(directory)
            # All three are Julia's choice, not this tree's: the loader finds a
            # root at `src/<Name>.jl` and an extension at `ext/<Name>Ext.jl`,
            # and `Pkg.build` runs `deps/build.jl` from the package directory
            # and nowhere else.
            (sub == "src" || sub == "ext" || sub == "deps") && continue
            push!(out, "package/$name/$sub — a package directory holds no folders " *
                       "but src/, ext/ and deps/")
        end
    end
    out
end

"""
    environment_violations(root) -> Vector{String}

**An environment holds a `Project.toml` and a `Manifest.toml`, and no code at
all.** An environment is a resolved dependency closure. The moment it carries a
`.jl` it is a package, and something will come to depend on it.
"""
function environment_violations(root::AbstractString)
    out = String[]
    base = joinpath(root, "environment")
    isdir(base) || return out
    for (dir, _, files) in walkdir(base), file in files
        endswith(file, ".jl") &&
            push!(out, "$(relpath(joinpath(dir, file), root)) — an environment holds no code")
    end
    out
end

# Every `include("…")` in `path`, resolved against the file's own directory.
function _includes(path::AbstractString)
    out = String[]
    text = read(path, String)
    for m in eachmatch(r"include\(\s*\"([^\"]+)\"\s*\)", text)
        push!(out, normpath(joinpath(dirname(path), m.captures[1])))
    end
    out
end

"""
    ships_violations(root) -> Vector{String}

**`test/` holds nothing that ships, and `example/` holds nothing a `source/`
file loads.**

The two folders exist to be *ignored*: a reader folds them away and what is left
is the system. That only works while nothing under `source/` reaches into them.
A package whose name ends in `Test` or `Example` is exempt, because reaching
them is the whole of what it does.

Checked as written rather than as declared, because the declared edge is already
`test_package_graph()`'s job and the two failures look nothing alike.
"""
function ships_violations(root::AbstractString)
    out = String[]
    forbidden = [joinpath(root, "test"), joinpath(root, "example")]
    roots = String[]
    isdir(joinpath(root, "source")) && push!(roots, joinpath(root, "source"))
    base = joinpath(root, "package")
    if isdir(base)
        for name in _subdirs(base)
            (endswith(name, "Test") || endswith(name, "Example")) && continue
            isdir(joinpath(base, name, "src")) && push!(roots, joinpath(base, name, "src"))
        end
    end
    for area in roots, (dir, _, files) in walkdir(area), file in files
        endswith(file, ".jl") || continue
        path = joinpath(dir, file)
        for target in _includes(path), bad in forbidden
            startswith(target, bad * "/") || continue
            push!(out, "$(relpath(path, root)) includes $(relpath(target, root)) — " *
                       "what ships may not reach $(basename(bad))/")
        end
    end
    out
end

"""
    guard_root_violations(root) -> Vector{String}

**Every directory a guard walks exists.**

A guard that silently stops looking is worse than no guard, because it reads as
evidence. omnet-julia lost a day to `test/qualifications.jl`, which walked
`("package", "samples")` after the samples moved and went on **passing while it
covered 188 fewer files**.

Every guard in this repository that walks the tree is named here. A guard that
is not at its path is a failure and not a skip — that is the half which catches
the move itself.
"""
function guard_root_violations(root::AbstractString)
    out = String[]
    guards = [joinpath(root, "test", "projectured", "PackageGraphTest.jl"),
              joinpath(root, "test", "kernel", "layering", "CheckLayering.jl")]
    present = filter(isfile, guards)
    isempty(present) &&
        push!(out, "no guard of this list is at its path — every walker moved, and " *
                   "this list did not follow")
    for guard in present
        text = read(guard, String)
        # `(?<!joinpath)` because `joinpath("package", "repl")` is a PATH and not
        # a walk list, and it has exactly the shape this looks for.
        for m in eachmatch(r"(?<!joinpath)\(\s*(\"[a-z][a-z_]*\"(?:\s*,\s*\"[a-z][a-z_]*\")+)\s*,?\s*\)", text)
            names = [strip(s, ['"', ' ']) for s in split(m.captures[1], ",")]
            live = filter(n -> isdir(joinpath(root, n)), names)
            dead = filter(n -> !isdir(joinpath(root, n)), names)
            (isempty(live) || isempty(dead)) && continue
            for n in dead
                push!(out, "$(relpath(guard, root)) walks \"$n\", which is not a directory " *
                           "(beside \"$(first(live))\", which is) — a stale walk root")
            end
        end
    end
    out
end

"""
    tree_violations(root) -> Vector{String}

Every rule of `plan/done/repository-tree.md` §3, as lines a reader can act on.
"""
tree_violations(root::AbstractString) =
    vcat(source_violations(root), package_violations(root),
         environment_violations(root), ships_violations(root),
         guard_root_violations(root))

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/tree.jl
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    bad = tree_violations(root)
    if isempty(bad)
        println("every folder holds one kind of thing")
    else
        println("$(length(bad)) violation(s) of the tree rules:")
        foreach(v -> println("  ", v), bad)
        exit(1)
    end
end
