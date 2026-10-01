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
# `export` lists, and it parses each file to find a definition that collides
# with another or shadows a generic it means to extend. It loads nothing, so it
# runs in about a second and cannot be fooled by what happens to be in a
# session.
# ============================================================================

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

**A module is declared in the file that names it.** A module is its file name
plus `Module`, so `JsonModule` lives in `JsonModule.jl` and `CellModule` in
`CellModule.jl`. One exception the rules state: a projection file `<Stem>.jl`
declares `<Stem>ProjectionModule`.

The rule used to allow a second form — a file could declare the module of its
slice rather than one named after itself — because 59 modules hid their head
inside a fragment. They do not any more. Removing that allowance on the tree
before `plan/done/module-head-in-its-own-file.md` reports 45 files.
"""
function module_violations(root::AbstractString)
    out = String[]
    for tree in ("source", "test", "example"), path in _naming_files(root, tree)
        code = _naming_code(root, path)
        declared = [m.captures[1] for m in eachmatch(r"(?m)^module\s+(\w+)\s*$", code)]
        isempty(declared) && continue
        stem = first(splitext(basename(path)))
        wanted = endswith(stem, "Module") ? stem : stem * "Module"
        # A test module is a fixture that Julia forces to the top level, and the
        # kernel is layered rather than sliced, so neither takes the slice rule.
        startswith(path, "test/") && continue
        startswith(path, joinpath("source", "kernel")) && continue
        for name in declared
            name == wanted && continue
            # a projection file may name its module for the projection it holds
            name == stem * "ProjectionModule" &&
                occursin(Regex("\\b" * stem * "Projection\\b"), code) && continue
            push!(out, "$path declares module $name; " *
                       "the file that names it is $wanted.jl")
        end
        length(declared) > 1 &&
            push!(out, "$path declares $(length(declared)) modules: " *
                       join(declared, ", ") * " — a file declares one")
    end
    out
end

"The groups of `source/` that are sliced: each folder in one is a slice."
const _SLICED_GROUPS = ("platform", "domain", "backend", "adapter")

"""
    slice_module_violations(root) -> Vector{String}

**A slice is one module.** Every folder of `source/platform/`, `source/domain/`,
`source/backend/` and `source/adapter/` is a slice: one of its files declares the
module of the slice, and every other file is a fragment that declares none. A
package entry that includes a file of a slice includes that module file, so the
imports and the exports of a slice are in the slice and not in its package. The
kernel is layered and not sliced, so it does not take the rule.
"""
function slice_module_violations(root::AbstractString)
    out = String[]
    declares(path) = occursin(r"(?m)^\s*(?:bare)?module\s+\w+", _naming_code(root, path))
    for group in _SLICED_GROUPS
        base = joinpath(root, "source", group)
        isdir(base) || continue
        for slice in sort!(readdir(base))
            isdir(joinpath(base, slice)) || continue
            files = [joinpath("source", group, slice, name)
                     for name in sort!(readdir(joinpath(base, slice))) if endswith(name, ".jl")]
            heads = filter(declares, files)
            length(heads) == 1 && continue
            push!(out, isempty(heads) ?
                "source/$group/$slice/ declares no module; a slice has one, in its module file" :
                "source/$group/$slice/ declares a module in $(length(heads)) files: " *
                join(basename.(heads), ", ") * "; a slice has one")
        end
    end
    for entry in _naming_files(root, "package")
        occursin(r"^package/\w+/src/\w+\.jl$", entry) || continue
        text = read(joinpath(root, entry), String)
        for found in eachmatch(r"(?m)^include\(\"(?:\.\./)+source/(\w+)/(\w+)/([^\"/]+)\"\)", text)
            found.captures[1] in _SLICED_GROUPS || continue
            path = joinpath("source", found.captures[1], found.captures[2], found.captures[3])
            isfile(joinpath(root, path)) && !declares(path) &&
                push!(out, "$entry includes $path, a fragment; a package includes the " *
                           "module file of a slice")
        end
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
        # The folder of the suite is the common folder of the test files that the
        # package includes: `test/<group>/<slice>`, or `test/<group>` for a group.
        top = joinpath(packages, entry, "src", entry * ".jl")
        isfile(top) || continue
        folders = [splitpath(dirname(normpath(joinpath(dirname(top), found.captures[1]))))
                   for found in eachmatch(r"^include\(\"([^\"]*/test/[^\"]+)\"\)"m,
                                          read(top, String))]
        if isempty(folders)
            push!(out, "$entry includes no file under test/")
            continue
        end
        depth = 0
        while all(parts -> length(parts) > depth && parts[depth + 1] == folders[1][depth + 1],
                  folders)
            depth += 1
        end
        dir = joinpath(folders[1][1:depth]...)
        isdir(dir) || (push!(out, "$entry includes from $dir, which is no folder"); continue)
        suite = joinpath(dir, stem * "Suite.jl")
        isfile(suite) ||
            push!(out, "$(relpath(dir, root)) holds no $(stem)Suite.jl for $entry")
        code = join((_naming_code(root, relpath(joinpath(dir, f), root))
                     for f in readdir(dir) if endswith(f, ".jl")), "\n")
        occursin(Regex("function\\s+test_$(slice)\\s*\\("), code) ||
            push!(out, "$(relpath(dir, root)) defines no test_$(slice)() for $entry")
        occursin(Regex("function\\s+test_$(slice)_layering\\s*\\("), code) ||
            push!(out, "$(relpath(dir, root)) defines no test_$(slice)_layering() for $entry")
    end
    out
end

# ============================================================================
# One module, many files — the definitions that collide.
#
# A slice is one module now, so two files of one slice put their definitions in
# one namespace. Two methods of one generic in two files is the design, not a
# fault: that is what dispatch is for. What is a fault is a *conflicting*
# definition — the same name with the same argument types, which is one method
# and not two.
#
# Julia rejects some of these and accepts others without a word. It refuses a
# method overwrite during precompilation, so a second `__init__` or a second
# `_kind_label(content)` is loud. It accepts a `const` redefined to an equal
# value in silence, and it accepts a second method whose arguments carry no
# types as a plain overwrite of the first.
# ============================================================================

const _JS = Base.JuliaSyntax

"""
The names a module may define in several files, because every method dispatches
on its own type. These are the projection interface and the operation seam: one
generic, one method per projection or per operation.
"""
const _MANY_METHODS = Set([
    "print_document", "print_child", "read_intent", "map_reference_forward",
    "map_reference_backward", "evaluate_operation",
    "get_projection_gesture_bindings"])

"""
    _module_files(root) -> Dict{String,Vector{String}}

Every module, and the files its definitions live in. It follows `include` from
the file that declares the module, and stops at a file that declares one of its
own, so a layer's fragments and a slice's fragments are told apart.
"""
function _module_files(root::AbstractString)
    declares = Dict{String,String}()                    # path -> module name
    for tree in ("source", "test", "example"), path in _naming_files(root, tree)
        m = match(r"(?m)^module\s+(\w+)\s*$", _naming_code(root, path))
        m === nothing || (declares[path] = m.captures[1])
    end
    out = Dict{String,Vector{String}}()
    for (path, name) in declares
        files, queue = String[], [path]
        while !isempty(queue)
            current = pop!(queue)
            current in files && continue
            push!(files, current)
            for inc in eachmatch(r"(?m)^\s*include\(\"([^\"]+)\"\)",
                                 _naming_code(root, current))
                target = normpath(joinpath(dirname(current), inc.captures[1]))
                isfile(joinpath(root, target)) || continue
                # a file that declares its own module is not this module's
                (target != path && haskey(declares, target)) && continue
                push!(queue, target)
            end
        end
        out[name] = sort(files)
    end
    out
end

"""
    _argument_types(call) -> Vector{String}

The type each argument of a definition names, as written. An argument with no
type reads `_`, because an untyped argument matches everything and two of them
are one method.
"""
function _argument_types(call)
    out = String[]
    for (i, child) in enumerate(_JS.children(call))
        i == 1 && continue                              # the function being defined
        _JS.kind(child) === _JS.K"parameters" && continue  # keyword arguments do not dispatch
        text = _JS.sourcetext(child)
        # `<:` is part of the type a `Type{<:JsonFile}` argument names, and it is
        # the whole difference between one file format's method and another's.
        m = match(r"::\s*([A-Za-z_][\w.{}<:, ]*)", text)
        push!(out, m === nothing ? "_" : strip(m.captures[1]))
    end
    out
end

"The definitions a file states at the top level of its module."
function _top_level(tree)
    out = _JS.SyntaxNode[]
    for node in _JS.children(tree)
        # a docstring wraps what it documents, including a `module`
        node = _JS.kind(node) === _JS.K"doc" ? last(_JS.children(node)) : node
        if _JS.kind(node) === _JS.K"module"
            # a module file states its definitions inside the block; a fragment
            # states them at the top level, and both belong to the one module
            for inner in _JS.children(node)
                _JS.is_leaf(inner) && continue
                _JS.kind(inner) === _JS.K"block" || continue
                append!(out, _JS.children(inner))
            end
        else
            push!(out, node)
        end
    end
    out
end

"""
    _definitions(root, path) -> Vector{Tuple{String,String}}

Every definition of `path`, as `(name, signature)`. A `const` takes the
signature `a constant`, so two files that assign one cannot both be right.
"""
const _DEFINITION_CACHE = Dict{String,Vector{Tuple{String,String}}}()

function _definitions(root::AbstractString, path::AbstractString)
    key = joinpath(root, path)
    haskey(_DEFINITION_CACHE, key) && return _DEFINITION_CACHE[key]
    out = Tuple{String,String}[]
    text = read(joinpath(root, path), String)
    tree = try
        _JS.parseall(_JS.SyntaxNode, text; filename = path)
    catch
        return _DEFINITION_CACHE[key] = out             # whether a file parses is another check
    end
    for node in _top_level(tree)
        node = _JS.kind(node) === _JS.K"doc" ? last(_JS.children(node)) : node
        kind = _JS.kind(node)
        if kind === _JS.K"const"
            m = match(r"^const\s+([A-Za-z_]\w*)", _JS.sourcetext(node))
            m === nothing || push!(out, (m.captures[1], "a constant"))
        elseif kind in (_JS.K"function", _JS.K"=")
            call = first(_JS.children(node))
            _JS.kind(call) === _JS.K"::" && (call = first(_JS.children(call)))
            _JS.kind(call) === _JS.K"where" && (call = first(_JS.children(call)))
            _JS.kind(call) === _JS.K"call" || continue
            name = _JS.sourcetext(first(_JS.children(call)))
            push!(out, (name, "a method taking (" * join(_argument_types(call), ", ") * ")"))
        end
    end
    _DEFINITION_CACHE[key] = out
end

"""
    duplicate_definition_violations(root) -> Vector{String}

No module defines one signature in two of its files. Two methods of one generic
are fine, and two methods that take the same types are one method: the second
replaces the first, loudly for a function and silently for a `const`.
"""
function duplicate_definition_violations(root::AbstractString)
    out = String[]
    for (name, files) in sort(collect(_module_files(root)), by = first)
        length(files) > 1 || continue
        where = Dict{Tuple{String,String},Vector{String}}()
        for path in files, definition in _definitions(root, path)
            first(definition) in _MANY_METHODS && continue
            push!(get!(where, definition, String[]), path)
        end
        for (definition, paths) in sort(collect(where), by = first)
            unique_paths = unique(paths)
            length(unique_paths) > 1 || continue
            push!(out, "$name defines $(first(definition)) twice, as " *
                       "$(last(definition)): " * join(unique_paths, " and "))
        end
    end
    out
end

# ============================================================================
# A definition that shadows instead of extending.
#
# After a bare `using ..XxxModule`, a plain `f(…) = …` for a name `XxxModule`
# exports does **not** extend that generic. Julia defines a new `f` in the
# calling module, the owner keeps its own methods, and every call through the
# owner reaches the fallback. Measured on Julia 1.13: no warning, no error.
#
# So a file that adds a method to another module's generic must say so, either
# by importing the name (`import ..XxxModule: f`) or by qualifying the
# definition (`XxxModule.f(…) = …`). This check reads the third case, the one
# that compiles and is wrong.
# ============================================================================

"""
    _exported(root, files) -> Set{String}

Every name a module's files export. An `export` list can continue onto an
indented line, and a name can be written `var"@macro"`.
"""
function _exported(root::AbstractString, files)
    out, open_statement = Set{String}(), false
    for path in files, line in eachline(joinpath(root, path))
        if open_statement
            if startswith(line, " ") || startswith(line, "\t")
                isempty(strip(line)) || (_collect_names!(out, line); continue)
            end
            open_statement = false
        end
        startswith(line, "export ") || continue
        _collect_names!(out, line[length("export")+1:end])
        open_statement = endswith(rstrip(line), ",")
    end
    out
end

"Add every identifier of a comma-separated list to `out`."
function _collect_names!(out::Set{String}, text::AbstractString)
    for name in split(text, ",")
        name = strip(replace(name, "var\"" => "", "\"" => ""))
        occursin(r"^@?[A-Za-z_][A-Za-z0-9_!]*$", name) && push!(out, name)
    end
    out
end

"""
    _imported(root, files) -> Set{String}

Every name a module's files import by name from a sibling. These are the names
a file may extend without qualification, because `import` makes the binding the
owner's.
"""
function _imported(root::AbstractString, files)
    out, open_statement = Set{String}(), false
    for path in files, line in eachline(joinpath(root, path))
        if open_statement
            if startswith(line, " ") || startswith(line, "\t")
                isempty(strip(line)) || (_collect_names!(out, line); continue)
            end
            open_statement = false
        end
        m = match(r"^import \.\.[A-Za-z][A-Za-z0-9_]*\s*:(.*)$", line)
        m === nothing && continue
        _collect_names!(out, m.captures[1])
        open_statement = endswith(rstrip(line), ",")
    end
    out
end

"""
    shadowed_extension_violations(root) -> Vector{String}

No module defines, unqualified and unimported, a name another module it names
exports. Such a definition reads as an extension and is a new function.
"""
function shadowed_extension_violations(root::AbstractString)
    files_of = _module_files(root)
    exports = Dict(name => _exported(root, files) for (name, files) in files_of)
    # An aggregate exports every name of the modules of its group, which it
    # gathers with a loop that this guard can not read.
    for (aggregate, group) in (("KernelModule", "kernel"), ("PlatformModule", "platform"))
        members = [m for (m, files) in files_of if m != aggregate &&
                   all(f -> startswith(f, joinpath("source", group) * "/"), files)]
        exports[aggregate] = union(Set{String}(), (exports[m] for m in members)...)
    end
    out = String[]
    for (name, files) in sort(collect(files_of), by = first)
        imported = _imported(root, files)
        # the modules this one names, whatever the form
        named = String[]
        for path in files, line in eachline(joinpath(root, path))
            m = match(r"^(?:using|import) \.\.([A-Za-z][A-Za-z0-9_]*)", line)
            m === nothing || push!(named, m.captures[1])
        end
        unique!(named)
        for path in files, (defined, _signature) in _definitions(root, path)
            occursin(".", defined) && continue          # a qualified definition is the other form
            defined in imported && continue             # imported, so the binding is the owner's
            defined in get(exports, name, Set{String}()) && continue   # the module's own
            for other in named
                other == name && continue
                defined in get(exports, other, Set{String}()) || continue
                push!(out, "$path defines $defined, which $other exports and " *
                           "$name does not import — the definition makes a new " *
                           "function rather than extending $other.$defined")
                break
            end
        end
    end
    out
end

"""
    naming_violations(root) -> Vector{String}

Every mechanical rule of `documentation/rule/naming-rules.md`, as lines a
reader can act on.
"""
naming_violations(root::AbstractString) =
    vcat(module_violations(root), slice_module_violations(root), alias_violations(root),
         abbreviation_violations(root), suite_violations(root),
         duplicate_definition_violations(root),
         shadowed_extension_violations(root))

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
