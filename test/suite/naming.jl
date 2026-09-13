# ============================================================================
# The naming guard — one check per rule that a machine can read.
#
# `documentation/rule/naming-rules.md` says how everything is named, and
# `PAR-NAMING-LAW` makes it an architecture invariant. This is the part of it a
# static reader can check: a file name, a module name, an alias that no file
# declares, and an abbreviation the rules ban.
#
# **What it does not check, and why.** Whether a verb fits the work is a
# judgement — `find_` for a search, `compute_` for real work, `get_` for a read
# — and so is whether a name reads as English. A guard that guessed at those
# would be wrong often enough to be ignored, and a guard people ignore is worse
# than none. This checks only what is mechanical.
#
# **Static, and deliberately.** It reads directory entries, `module` lines and
# `export` lists. It loads nothing, so it runs in well under a second and cannot
# be fooled by what happens to be in a session.
# ============================================================================

"""
    _slice_module(path) -> String

The module a file's slice would declare. `source/json/JsonDocument.jl` gives
`JsonModule`, because a slice is one unit of architecture and its files are
fragments of one module.
"""
function _slice_module(root::AbstractString, path::AbstractString)
    parts = splitpath(path)
    length(parts) < 2 && return ""
    slice = parts[2]
    isempty(slice) && return ""
    # The slice folder is lower case and the package carries the CamelCase, so
    # `filesystem` gives `FileSystem` and not `Filesystem`. Ask the package.
    packages = joinpath(root, "package")
    if isdir(packages)
        for entry in readdir(packages)
            startswith(entry, "Projectured") || continue
            stem = entry[length("Projectured")+1:end]
            lowercase(stem) == slice && return stem * "Module"
        end
    end
    uppercase(slice[1:1]) * slice[2:end] * "Module"
end

"Every `.jl` file under `dir`, as a repository-relative path."
function _naming_files(root::AbstractString, dir::AbstractString)
    out = String[]
    full = joinpath(root, dir)
    isdir(full) || return out
    for (here, _dirs, names) in walkdir(full), name in names
        endswith(name, ".jl") && push!(out, relpath(joinpath(here, name), root))
    end
    sort!(out)
end

"The text of `path` with every docstring and every comment removed."
function _naming_code(root::AbstractString, path::AbstractString)
    text = read(joinpath(root, path), String)
    text = replace(text, r"(?s)\"\"\".*?\"\"\"" => "")
    replace(text, r"(?m)#.*$" => "")
end

"""
    module_violations(root) -> Vector{String}

A module is its file name plus `Module`. Three exceptions the rules state:
a package root declares the package's own name, a `<Concept>Module.jl` declares
`<Concept>Module`, and a projection file `<Stem>.jl` declares
`<Stem>ProjectionModule`.
"""
function module_violations(root::AbstractString)
    out = String[]
    for tree in ("source", "test", "example"), path in _naming_files(root, tree)
        code = _naming_code(root, path)
        declared = [m.captures[1] for m in eachmatch(r"(?m)^module\s+(\w+)\s*$", code)]
        isempty(declared) && continue
        stem = first(splitext(basename(path)))
        wanted = endswith(stem, "Module") ? stem : stem * "Module"
        slice = _slice_module(root, path)
        # A test module is a fixture that Julia forces to the top level, and the
        # kernel is layered rather than sliced, so neither takes the slice rule.
        startswith(path, "test/") && continue
        startswith(path, joinpath("source", "kernel")) && continue
        for name in declared
            name == wanted && continue
            # A slice is one unit of architecture, so a file may declare the
            # module of its slice rather than one of its own. See
            # `plan/pending/one-module-per-slice.md`.
            name == slice && continue
            name in _PENDING_SLICE_MODULES && continue
            # a projection file may name its module for the projection it holds
            name == stem * "ProjectionModule" &&
                occursin(Regex("\\b" * stem * "Projection\\b"), code) && continue
            push!(out, "$path declares module $name; the file name gives " *
                       "$wanted and its slice gives $slice")
        end
        length(declared) > 1 &&
            push!(out, "$path declares $(length(declared)) modules: " *
                       join(declared, ", ") * " — a file declares one")
    end
    out
end

"""
    alias_violations(root) -> Vector{String}

A package root may alias a module, but only under a name some file declares.
An alias that names nothing is a name a reader can not grep back to a
declaration, which is the bidirectional guess the law promises.
"""
function alias_violations(root::AbstractString)
    declared = Set{String}()
    for tree in ("source", "test", "example"), path in _naming_files(root, tree)
        for m in eachmatch(r"(?m)^module\s+(\w+)\s*$", _naming_code(root, path))
            push!(declared, m.captures[1])
        end
    end
    out = String[]
    packages = joinpath(root, "package")
    isdir(packages) || return out
    for entry in sort(readdir(packages))
        file = joinpath(packages, entry, "src", entry * ".jl")
        isfile(file) || continue
        code = replace(read(file, String), r"(?m)#.*$" => "")
        for m in eachmatch(r"(?m)^const\s+(\w+Module)\s*=\s*[\w.]*\.(\w+)\s*$", code)
            alias, real = m.captures[1], m.captures[2]
            alias == real && continue
            alias in declared && continue
            push!(out, "package/$entry declares the alias $alias for $real, " *
                       "and no file declares $alias")
        end
    end
    out
end

"""
Names this guard passes, each with the reason. A guard that reports the same
known thing every run is a guard people stop reading, so an exemption is written
here with its cause rather than left to accumulate.
"""
const _ALLOWED = Dict(
    # A constant that holds a wire value spells the value, which
    # `documentation/rule/naming-rules.md` states under the sanctioned compact
    # forms. These four hold the literal "pred-ref", "pred:ref" and "pred_ref"
    # that a user writes and the loader matches.
    "PRED_REF_DIRECTIVE" => "the wire value is literally pred-ref",
    "PRED_REF_ELEMENT_TAG" => "the wire value is literally pred:ref",
    "PRED_REF_FUNCTION_NAME" => "the wire value is literally pred_ref",
    "PRED_REF_LANGUAGE" => "the wire value is literally pred-ref")

"""
Modules whose name a slice collapse will settle, so renaming them now is work
that gets undone. See `plan/pending/one-module-per-slice.md`.
"""
const _PENDING_SLICE_MODULES = Set([
    "ConsoleBackendModule", "PdfBackendModule"])

"Words the rules ban inside a name, and the expansion each one owes."
const _BANNED_WORDS = Dict(
    "op" => "operation", "ops" => "operations", "col" => "column",
    "cols" => "columns", "ref" => "reference", "refs" => "references",
    "val" => "value", "vals" => "values", "fn" => "function",
    "perf" => "performance", "eval" => "evaluation", "nav" => "navigation",
    "seg" => "segment", "segs" => "segments", "ctx" => "context",
    "def" => "definition", "conn" => "connection", "elem" => "element",
    "num" => "number", "dedup" => "deduplicate", "kw" => "keyword")

"""
    abbreviation_violations(root) -> Vector{String}

No exported name carries an ad-hoc abbreviation. The rules sanction `api`,
`iomap`, `ctrl`, `alt`, `meta`, `ctor` and `expr`, and ban the rest.
"""
function abbreviation_violations(root::AbstractString)
    out = String[]
    for tree in ("source", "test", "example"), path in _naming_files(root, tree)
        code = _naming_code(root, path)
        for statement in eachmatch(r"(?m)^\s*export\s+((?:[^\n]*,\s*\n)*[^\n]*)", code)
            for name in split(statement.captures[1], ",")
                name = strip(name)
                occursin(r"^@?[A-Za-z_][A-Za-z0-9_!]*$", name) || continue
                haskey(_ALLOWED, name) && continue
                for word in split(lowercase(rstrip(name, '!')), "_")
                    haskey(_BANNED_WORDS, word) || continue
                    push!(out, "$path exports $name, and $word must read " *
                               "$(_BANNED_WORDS[word])")
                end
            end
        end
    end
    out
end

"""
    suite_violations(root) -> Vector{String}

A test package exports `test_<slice>()` and the static guard
`test_<slice>_layering()` beside it, and its suite file is `<Slice>Suite.jl`
in the package's own CamelCase.
"""
function suite_violations(root::AbstractString)
    out = String[]
    packages = joinpath(root, "package")
    isdir(packages) || return out
    for entry in sort(readdir(packages))
        endswith(entry, "Test") || continue
        stem = entry[length("Projectured")+1:end-length("Test")]
        isempty(stem) && continue                       # the umbrella is named apart
        slice = lowercase(stem)
        dir = joinpath(root, "test", slice)
        isdir(dir) || continue
        suite = joinpath(dir, stem * "Suite.jl")
        isfile(suite) ||
            push!(out, "test/$slice holds no $(stem)Suite.jl for $entry")
        code = join((_naming_code(root, relpath(joinpath(dir, f), root))
                     for f in readdir(dir) if endswith(f, ".jl")), "\n")
        occursin(Regex("function\\s+test_$(slice)\\s*\\("), code) ||
            push!(out, "test/$slice defines no test_$(slice)() for $entry")
        occursin(Regex("function\\s+test_$(slice)_layering\\s*\\("), code) ||
            push!(out, "test/$slice defines no test_$(slice)_layering() for $entry")
    end
    out
end

"""
    naming_violations(root) -> Vector{String}

Every mechanical rule of `documentation/rule/naming-rules.md`, as lines a
reader can act on.
"""
naming_violations(root::AbstractString) =
    vcat(module_violations(root), alias_violations(root),
         abbreviation_violations(root), suite_violations(root))

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/naming.jl
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    bad = naming_violations(root)
    if isempty(bad)
        println("every name the guard can read follows the law")
    else
        println("$(length(bad)) naming violation(s):")
        foreach(v -> println("  ", v), bad)
        exit(1)
    end
end
