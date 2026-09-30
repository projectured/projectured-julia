# ═══════════════════════════════════════════════════════════════════════════
# layering/CheckLayering.jl
#
# The shared static layered-architecture guard. Each main package
# (`ProjecturedKernel`, `ProjecturedBase`, `ProjecturedVisual`,
# `ProjecturedDomain`) keeps its top module file as a hand-maintained
# topological sort: every top-level `include("…")` must appear *after* the
# files defining every `..XxxModule` it imports. `check_layering` enforces the
# discipline **statically, without loading the package**, in ~1s, so a
# regression is caught with a message naming the offending file and the module
# it references too early.
#
# The walker is **fragment-aware**: a `Module.jl` aggregator can `include(…)`
# 0-module *fragment* files that share its namespace, and the top package file
# can `include(…)` per-layer fragment files (`cell/CellLayer.jl`, …) whose
# own includes are the layer's module files, in order. Every `include(...)` is
# followed recursively from the top file, each module-body fragment's imports
# are collected under its nearest module-defining ancestor, and the checks
# assert:
#
# 1. every on-disk `.jl` file is reached by the include tree exactly once,
# 2. every module file reached names a module defined by exactly one file,
# 3. the include order over the module files is a valid topological order over
#    the union of own+fragment imports (a `const Xxx = OtherPackage.Xxx` alias
#    at the top of the package file satisfies a `..Xxx` dep — that is how
#    base/visual/domain re-export the lower packages' modules),
# 4. for files that live under a declared `layers` folder, every `..XxxModule`
#    dep resolves to a module whose file also lives under a layers folder of
#    index ≤ the importer's (non-layers folders are exempt during transition),
# 5. (opt-in via `check_private_imports`) every cross-layer
#    `import ..XxxModule: sym` names only symbols the target module exports.
#    Same-layer neighbours are still exempt here, but that is **transitional**:
#    PAR-MODULE-BOUNDARY-IS-API forbids reaching into a sibling module's internals too,
#    and the same-layer case is enforced per package once its imports are clean. A
#    plain `import ..XxxModule` is unconstrained.
# 6. (opt-in via `interface_files`) every declared interface file declares and
#    never implements, and exports every name it declares (PAR-INTERFACE-DECLARES-ONLY).
# 7. every `XxxModule.sym` qualification names an exported symbol. This is the
#    other half of (5): a qualified reference bypasses the export list entirely, and
#    under PAR-QUALIFIED-EXTENSION qualification is how a file extends another module's
#    generic — so without this check PAR-MODULE-BOUNDARY-IS-API would hold for import
#    headers and be unenforced exactly where it now matters most.
# 8. every file names a sibling module with bare
#    `using ..XxxModule` only — never `import ..XxxModule` or a symbol list
#    (PAR-QUALIFIED-EXTENSION).
#
# Each test package calls `check_layering` with its own src root and declared
# layer order (`test_kernel_layering()`, `test_base_layering()`, …); this file
# replaces the four near-identical per-package `test/runtests.jl` guards.
# ═══════════════════════════════════════════════════════════════════════════

const DOT = Symbol(".")

# ── AST helpers ────────────────────────────────────────────────────────────

"Recursively collect every `Expr` for which `pred` is true."
function collect_exprs(pred, x, acc = Expr[])
    if x isa Expr
        pred(x) && push!(acc, x)
        for a in x.args
            collect_exprs(pred, a, acc)
        end
    end
    acc
end

parse_file(path) = Meta.parseall(read(path, String); filename = path)

"""
Given one argument of an `import`/`using` statement, return the referenced
sibling module symbol for a *relative* path (`..Foo` / `..Foo: a, b`), or
`nothing` for an absolute import (Base/stdlib) — which cannot create an
intra-package ordering edge.
"""
function relative_module(arg)
    path = (arg isa Expr && arg.head === :(:)) ? arg.args[1] : arg
    path isa Expr && path.head === :. || return nothing
    any(==(DOT), path.args) || return nothing        # no leading dot ⇒ absolute
    for a in path.args
        a isa Symbol && a !== DOT && return a         # first real name = module
    end
    nothing
end

"""
For a symbol-list import argument (`import ..Mod: a, @b, c as d`), return the
imported symbol names (`[a, @b, c]` — a rename constrains the *original* name).
A plain-path argument (`import ..Mod`) returns an empty list, meaning the
import is unconstrained. `var"@x"` surface syntax already parses to the symbol
`@x`, so macro names need no extra normalization.
"""
function imported_symbols(arg)
    arg isa Expr && arg.head === :(:) || return Symbol[]
    syms = Symbol[]
    for a in arg.args[2:end]
        a isa Expr && a.head === :as && (a = a.args[1])
        a isa Expr && a.head === :. && a.args[end] isa Symbol && push!(syms, a.args[end])
    end
    syms
end

"""
Return `(imports, includes, sym_imports, exports)` for the statements at the
top level of `body_expr` — a module body (`:block`) or a bare fragment body
(`Meta.parseall` yields `:toplevel`):

- `imports::Vector{Symbol}` — the referenced relative sibling modules,
- `includes::Vector{String}` — the ordered `include(...)` paths,
- `sym_imports::Vector{Pair{Symbol, Vector{Symbol}}}` — one pair per relative
  import argument: `import ..Mod: a, b` → `Mod => [a, b]`; plain
  `import ..Mod` → `Mod => []` (unconstrained),
- `exports::Vector{Symbol}` — the names in `export` statements.
"""
function collect_edges(body_expr)
    imports = Symbol[]
    includes = String[]
    sym_imports = Pair{Symbol, Vector{Symbol}}[]
    exports = Symbol[]
    stmts = body_expr isa Expr ?
        (body_expr.head in (:block, :toplevel) ? body_expr.args : (body_expr,)) :
        ()
    for stmt in stmts
        stmt isa Expr || continue
        if stmt.head === :call && length(stmt.args) >= 2 &&
                stmt.args[1] === :include && stmt.args[2] isa AbstractString
            push!(includes, stmt.args[2])
        elseif stmt.head in (:import, :using)
            for arg in stmt.args
                d = relative_module(arg)
                d === nothing && continue
                push!(imports, d)
                push!(sym_imports, d => imported_symbols(arg))
            end
        elseif stmt.head === :export
            for s in stmt.args
                s isa Symbol && push!(exports, s)
            end
        end
    end
    imports, includes, sym_imports, exports
end

# ── fragment-aware include walker ──────────────────────────────────────────

"""
Walk the include tree rooted at `top_file`, recursively following each
`include(...)` relative to the including file's directory. Return
`(reached, entries)`:

- `reached::Vector{String}` — every file reached (relpath to `src_root`), in
  visit order; used to check every on-disk file is included exactly once.
- `entries` — one entry per **module file** reached, in include order:
  `(rel_path, module_name, agg_deps, agg_sym_imports, agg_exports)`, each
  aggregate the union/concatenation over the module's own statements and every
  fragment file it (transitively) includes: `agg_deps` the imported sibling
  modules, `agg_sym_imports` the per-import symbol lists (`import ..X: a, b` →
  `X => [a, b]`; plain `import ..X` → `X => []`, unconstrained), `agg_exports`
  the exported names.

A file whose AST defines exactly one `module` is a *module file*; its
`agg_deps` includes descendant fragments' imports. A file with zero `module`s
is a *fragment*: below a module file its imports are folded into that
module's `agg_deps`; reached straight from the top file it is a *layer
fragment* — its includes are the layer's module files, and it may not carry
relative imports of its own (there is no module to attach them to). A file
with 2+ modules is an error, as is a module file included inside another
module file.

`allow_root_fragments = true` lifts that last restriction for a package whose
root file deliberately holds fragments in its own namespace — `inet-julia`'s
model wrappers and capture files, which are a slice's face to the simulation
lifecycle and to the observation machinery and sit outside the slice's inner
module by design. Their imports attach to the package root, which lives in no
layer folder and is exempt from the layer check either way, so what the option
costs is that those files' imports go unchecked rather than that a wrong one
passes.
"""
function walk_includes(top_file, src_root; allow_root_fragments = false)
    reached = String[]
    entries = Tuple{String, Symbol, Vector{Symbol},
                    Vector{Pair{Symbol, Vector{Symbol}}}, Vector{Symbol}}[]
    file_owner = Dict{String, Symbol}()
    file_imports = Dict{String, Vector{Pair{Symbol, Vector{Symbol}}}}()

    # Descend into `file`. `owner` is the module whose namespace encloses it
    # (`nothing` for the top file's layer fragments); returns the
    # `(imports, sym_imports, exports)` to fold into that ancestor (all empty
    # for module files, which emit an entry instead).
    function descend(file, owner)
        rel = relpath(file, src_root)
        push!(reached, rel)
        ast = parse_file(file)
        mods = collect_exprs(e -> e.head === :module, ast)
        if length(mods) > 1
            error("$rel defines $(length(mods)) modules; expected 0 (fragment) or 1 (module)")
        end
        if length(mods) == 1 && owner !== nothing
            error("$rel defines a module but is included inside another module file")
        end
        name = length(mods) == 1 ? mods[1].args[2]::Symbol : nothing
        body = length(mods) == 1 ? mods[1].args[3] : ast
        imports, includes, sym_imports, exports = collect_edges(body)
        if length(mods) == 0 && owner === nothing && !isempty(imports) &&
                !allow_root_fragments
            error("$rel is a layer fragment with relative imports; only module files may import ..Xxx")
        end
        # A module file owns itself; a fragment inherits its enclosing module.
        my_owner = name === nothing ? owner : name
        my_owner === nothing || (file_owner[rel] = my_owner)
        # This file's *own* import headers, before children are folded in — the
        # PAR-QUALIFIED-EXTENSION lint is per file, and a fragment's imports would
        # otherwise be attributed to the module file that includes it.
        file_imports[rel] = copy(sym_imports)
        # Recurse into includes, aggregating fragment imports/exports upward.
        for inc in includes
            child_path = joinpath(dirname(file), inc)
            isfile(child_path) || error("$rel includes \"$inc\" but the file does not exist")
            child_imports, child_syms, child_exports = descend(child_path, my_owner)
            append!(imports, child_imports)
            append!(sym_imports, child_syms)
            append!(exports, child_exports)
        end
        if name !== nothing
            # Module file: emit an entry, but do not propagate deps upward.
            push!(entries, (rel, name, unique(imports), sym_imports, unique(exports)))
            (Symbol[], Pair{Symbol, Vector{Symbol}}[], Symbol[])
        else
            # Fragment: propagate imports/exports to the enclosing module.
            (unique(imports), sym_imports, unique(exports))
        end
    end

    # The top file itself is `module ProjecturedXxx ... end`. No entry is
    # emitted for it; each top-level include is either a module file (one
    # entry) or a layer fragment (one entry per module file it includes).
    push!(reached, relpath(top_file, src_root))
    top_ast = parse_file(top_file)
    top_mods = collect_exprs(e -> e.head === :module, top_ast)
    length(top_mods) == 1 ||
        error("$(relpath(top_file, src_root)) must define exactly 1 module (the top)")
    top_body = top_mods[1].args[3]
    _, top_includes = collect_edges(top_body)
    for inc in top_includes
        child_path = joinpath(dirname(top_file), inc)
        isfile(child_path) || error("top include \"$inc\" not found on disk")
        descend(child_path, nothing)
    end
    reached, entries, file_owner, file_imports
end

"""
Collect the module aliases declared at the top of the package file — every
`const Xxx = OtherPackage.Xxx` binding. A `..Xxx` dep that resolves to an
alias points at a *lower package's* module, so it never constrains the
include order of this package.
"""
function alias_names(top_file)
    ast = parse_file(top_file)
    top_mods = collect_exprs(e -> e.head === :module, ast)
    length(top_mods) == 1 || return Set{Symbol}()
    aliases = Set{Symbol}()
    for stmt in top_mods[1].args[3].args
        stmt isa Expr || continue
        stmt.head === :const || continue
        length(stmt.args) >= 1 && stmt.args[1] isa Expr || continue
        eq = stmt.args[1]
        eq.head === :(=) || continue
        eq.args[1] isa Symbol || continue
        push!(aliases, eq.args[1])
    end
    aliases
end

# ── pure topological checker ───────────────────────────────────────────────

"""
    topo_errors(entries, aliases = Set{Symbol}()) -> Vector{String}

`entries` is an ordered `Vector` of `(label, module_name, deps)`. Returns a
human-readable error for every dependency that is not satisfied by an *earlier*
entry or an alias — either a forward edge (the module is defined later) or a
dangling reference (no entry defines it at all). Empty result ⇒ valid
topological order.
"""
function topo_errors(entries, aliases = Set{Symbol}())
    all_mods = Set(m for (_, m, _) in entries)
    seen = Set{Symbol}()
    errs = String[]
    for (i, (label, mod, deps)) in enumerate(entries)
        for d in deps
            if d in seen || d in aliases
                continue
            elseif d in all_mods
                push!(errs, "[$i] $label ($mod) imports ..$d, which is included later — move $label after it")
            else
                push!(errs, "[$i] $label ($mod) imports ..$d, which no file defines")
            end
        end
        push!(seen, mod)
    end
    errs
end

"""
    slice_edge_errors(entries, allowed) -> Vector{String}

Every import that crosses from one slice to another where `allowed` does not
permit it. `entries` are module files as `walk_includes` answers them, with
paths relative to the folder that holds the slice folders, so the first folder
of a path is the slice of its module. `allowed` maps a slice to the slices that
it may use. An import of a module that no entry defines, such as a module of a
package below that the entry file binds, is not checked here.
"""
function slice_edge_errors(entries, allowed)
    slice_of = Dict{Symbol, String}(entry[2] => layer_of(entry[1]) for entry in entries)
    errs = String[]
    for (rel, mod, deps) in entries
        slice = layer_of(rel)
        for dep in deps
            other = get(slice_of, dep, nothing)
            (other === nothing || other == slice) && continue
            other in get(allowed, slice, String[]) ||
                push!(errs, "$rel ($mod) uses ..$dep of the slice $other, which the table " *
                            "does not allow for the slice $slice")
        end
    end
    errs
end

# ── layer checker ──────────────────────────────────────────────────────────

"""Return the top-level folder name for a relpath (`"cell/CellModule.jl"` → `"cell"`).
Returns `""` if the file lives directly under the package root."""
function layer_of(rel::AbstractString)
    parts = splitpath(rel)
    length(parts) >= 2 ? parts[1] : ""
end

"""
    layer_errors(entries, layers, exempt_files = Set{String}()) -> Vector{String}

Assert that for every entry whose file lives under a declared `layers` folder,
every dep resolves to a module whose file is also under a layers folder of
index ≤ the importer's. Non-layers folders are exempt (a dep pointing into a
non-layers folder does not constrain the importer, and an importer in a
non-layers folder skips the check). This is the transition-safe form; the
final phase removes the exemption.
"""
function layer_errors(entries, layers, exempt_files = Set{String}())
    # Build module → layer index (or `nothing` if outside `layers`).
    idx_of_layer = Dict(l => i for (i, l) in enumerate(layers))
    mod_layer = Dict{Symbol, Union{Int, Nothing}}()
    for (rel, mod, _) in entries
        mod_layer[mod] = get(idx_of_layer, layer_of(rel), nothing)
    end
    errs = String[]
    for (rel, mod, deps) in entries
        rel in exempt_files && continue         # transitional per-file exemption
        my_idx = get(idx_of_layer, layer_of(rel), nothing)
        my_idx === nothing && continue          # importer exempt (non-layers folder)
        for d in deps
            dep_idx = get(mod_layer, d, nothing)
            dep_idx === nothing && continue     # dep exempt (non-layers / alias)
            if dep_idx > my_idx
                push!(errs,
                    "$rel ($mod, layer \"$(layers[my_idx])\") imports ..$d " *
                    "which lives in higher layer \"$(layers[dep_idx])\"")
            end
        end
    end
    errs
end

# ── private-import checker ─────────────────────────────────────────────────

"""
    private_import_errors(entries, layers, exempt_files = Set{String}()) -> Vector{String}

Assert that a cross-layer `import ..XxxModule: sym` names only symbols the
target module exports. A non-exported name is a module-internal implementation
detail; importing one across a layer boundary couples a higher layer to a
lower layer's internals, invisibly to both the export list and the
module-level layer check. Exempt, mirroring `layer_errors`: same-layer
imports (neighbours inside one layer may share internals), plain
`import ..XxxModule` (unconstrained), importers or deps outside the declared
`layers` folders, deps no entry defines (package aliases), and
`exempt_files` (transitional per-file exemption).

Qualified private access (`XxxModule._name`) reaches just as far and is *not*
covered here — that is `qualified_reference_errors`' job, and under PAR-QUALIFIED-EXTENSION
qualification is the normal way to extend another module's generic, so the two
checks are the two halves of PAR-MODULE-BOUNDARY-IS-API.
"""
function private_import_errors(entries, layers, exempt_files = Set{String}())
    idx_of_layer = Dict(l => i for (i, l) in enumerate(layers))
    mod_layer = Dict{Symbol, Union{Int, Nothing}}()
    mod_exports = Dict{Symbol, Set{Symbol}}()
    for (rel, mod, _, _, exports) in entries
        mod_layer[mod] = get(idx_of_layer, layer_of(rel), nothing)
        mod_exports[mod] = Set(exports)
    end
    errs = String[]
    for (rel, mod, _, sym_imports, _) in entries
        rel in exempt_files && continue         # transitional per-file exemption
        my_idx = get(idx_of_layer, layer_of(rel), nothing)
        my_idx === nothing && continue          # importer exempt (non-layers folder)
        for (dep, syms) in sym_imports
            isempty(syms) && continue           # plain `import ..Mod` — unconstrained
            haskey(mod_exports, dep) || continue  # dep exempt (package alias)
            dep_idx = mod_layer[dep]
            dep_idx === nothing && continue     # dep exempt (non-layers folder)
            # same layer — exempt for now (transitional; PAR-MODULE-BOUNDARY-IS-API
            # forbids this, staged per package)
            dep_idx == my_idx && continue
            for s in syms
                s in mod_exports[dep] || push!(errs,
                    "$rel ($mod, layer \"$(layers[my_idx])\") imports non-exported " *
                    "$s from ..$dep (layer \"$(layers[dep_idx])\") — export it, or " *
                    "share it via same-module fragments / a seam below both users")
            end
        end
    end
    errs
end

# ── qualified-reference checker (PAR-MODULE-BOUNDARY-IS-API at the
# qualification site) ──────────

"""
    qualified_reference_errors(src_root, file_owner, entries, layers,
                               exempt_files = Set{String}()) -> Vector{String}

Assert that every `XxxModule.sym` written in a file names a symbol `XxxModule`
exports.

`import ..Mod: sym` is not the only way to reach into another module —
`Mod.sym` in the body reaches just as far, and bypasses the export list
*entirely*. PAR-QUALIFIED-EXTENSION makes qualification the normal way to extend
another module's generic (`ReferenceModule.get_reference_step_kind(s::PointReferenceStep) = …`),
so without this check the migration would quietly open a hole exactly where
PAR-MODULE-BOUNDARY-IS-API matters most: "the module boundary *is* the API
boundary" would hold for import headers and be unenforced everywhere else.

Exempt, mirroring `private_import_errors`: a module qualifying *itself* (a
fragment naming its own module), deps no entry defines (`Base`, stdlib, package
aliases), importers or deps outside the declared `layers` folders, and
`exempt_files`. Unlike `private_import_errors` there is **no same-layer
exemption** — a qualified reference is new syntax introduced by
PAR-QUALIFIED-EXTENSION, so there is no legacy to grandfather and it is held to
the rule from the start.

`layers` may be empty (visual and domain declare a slice DAG, not layer
indices): the layer folders only drive the *exemptions*, so with no layers
declared nothing is exempt and every file is checked.
"""
function qualified_reference_errors(src_root, file_owner, entries, layers,
                                    exempt_files = Set{String}())
    idx_of_layer = Dict(l => i for (i, l) in enumerate(layers))
    mod_layer = Dict{Symbol, Union{Int, Nothing}}()
    mod_exports = Dict{Symbol, Set{Symbol}}()
    for (rel, mod, _, _, exports) in entries
        mod_layer[mod] = get(idx_of_layer, layer_of(rel), nothing)
        mod_exports[mod] = Set(exports)
    end
    errs = String[]
    for rel in sort(collect(keys(file_owner)))
        rel in exempt_files && continue
        owner = file_owner[rel]
        # With layers declared, a file outside them is exempt (as in `layer_errors`).
        # With none declared, there is nothing to be outside of — check everything.
        if !isempty(layers) && get(idx_of_layer, layer_of(rel), nothing) === nothing
            continue
        end
        ast = parse_file(joinpath(src_root, rel))
        # `Mod.sym` parses to `Expr(:., :Mod, QuoteNode(:sym))`. A nested
        # `a.b.c` has an Expr (not a Symbol) head, so only the innermost
        # `Mod.sym` — the one that can name a module — is considered.
        quals = collect_exprs(x -> x.head === :. && length(x.args) == 2 &&
                                   x.args[1] isa Symbol && x.args[2] isa QuoteNode, ast)
        for e in quals
            dep = e.args[1]::Symbol
            sym = e.args[2].value
            sym isa Symbol || continue          # `Mod.:(==)` etc. — not a plain name
            dep === owner && continue           # a fragment naming its own module
            haskey(mod_exports, dep) || continue  # not a module of this package
            isempty(layers) || mod_layer[dep] !== nothing ||
                continue                        # dep exempt (non-layers folder)
            sym in mod_exports[dep] && continue
            push!(errs,
                "$rel ($owner) qualifies non-exported $dep.$sym — export it from " *
                "..$dep, or share it via same-module fragments / a seam below both users")
        end
    end
    errs
end

# ── PAR-QUALIFIED-EXTENSION import-form lint
# ─────────────────────────────────────────────────

"""
    relative_import_errors(src_root, unmigrated_files) -> Vector{String}

PAR-QUALIFIED-EXTENSION: a file imports the names it **extends** and names every
other module with a bare `using ..Xxx`. Three forms are wrong:

- `import ..Xxx` with no symbol list — it binds the module name and nothing
  else, which is what a bare `using` already does, and better.
- `using ..Xxx: a, b` — a symbol list on a `using` says nothing. Either the file
  extends those names, and the line is an `import`, or it calls them, and the
  export list already says what it may call (PAR-MODULE-BOUNDARY-IS-API).
- `import ..Xxx: a, b` where the module adds no method to `a` — an import list
  is a statement of what this code implements, so a name nobody extends belongs
  on the bare `using` instead.

**The compiler does not check the form.** Measured on Julia 1.13: after a bare
`using ..Xxx`, a plain `f(…) = …` for a name `Xxx` exports raises no error and
no warning. It defines a new `f` in the calling module, `Xxx.f` keeps its own
methods, and every call through `Xxx` reaches the fallback. So the import list
is what makes an extension reach its generic, and
`shadowed_extension_violations` in `test/suite/naming.jl` is what reports the
definition that misses it. This checker is the tidiness half: it keeps an import
list meaning what it says.

**Every file under `src_root` is checked.** The sweep that brought the tree to
this form is done except for `graph`, so what remains is an exemption set rather
than an opt-in one: `unmigrated_files` names the files still to migrate, and a
file named there and since migrated is reported, so the set cannot go stale.

"Extended" is read over every file under `src_root`, because a slice is one
module whose header sits in one file and whose definitions sit in the others.
For a root that holds several modules this over-approximates, so the checker
stays silent where it cannot be sure.
"""
function relative_import_errors(src_root, unmigrated_files)
    errs = String[]
    extended = extended_names(src_root)
    every = String[]
    for (dir, _dirs, files) in walkdir(src_root), file in files
        endswith(file, ".jl") && push!(every, relpath(joinpath(dir, file), src_root))
    end
    for rel in sort(collect(unmigrated_files))
        isfile(joinpath(src_root, rel)) ||
            push!(errs, "$rel is listed as not yet migrated to " *
                        "PAR-QUALIFIED-EXTENSION but is not on disk")
    end
    for rel in sort(every)
        rel in unmigrated_files && continue
        path = joinpath(src_root, rel)
        for stmt in collect_exprs(x -> x.head in (:import, :using), parse_file(path))
            for arg in stmt.args
                dep = relative_module(arg)
                # absolute (Base/stdlib/package) — not PAR-QUALIFIED-EXTENSION's business
                dep === nothing && continue
                syms = imported_symbols(arg)
                if stmt.head === :import && isempty(syms)
                    push!(errs,
                        "$rel uses a bare `import ..$dep` — PAR-QUALIFIED-EXTENSION " *
                        "wants `using ..$dep`, which binds the name and brings the " *
                        "exports with it")
                elseif stmt.head === :using && !isempty(syms)
                    push!(errs,
                        "$rel uses `using ..$dep: $(join(syms, ", "))` — a symbol " *
                        "list on a `using` says nothing; `import` the names this " *
                        "code extends and name the module bare for the rest")
                elseif stmt.head === :import
                    idle = [s for s in syms if !(String(s) in extended)]
                    isempty(idle) ||
                        push!(errs,
                            "$rel imports $(join(idle, ", ")) from $dep and extends " *
                            "$(length(idle) == 1 ? "it" : "them") nowhere — an import " *
                            "list states what this code implements, so move " *
                            "$(length(idle) == 1 ? "it" : "them") to `using ..$dep`")
                end
            end
        end
    end
    errs
end

"""
    extended_names(src_root) -> Set{String}

Every name that a file under `src_root` defines a method for, unqualified. These
are the names an import list may carry, because a method defined under a bare
name reaches its generic only when the name was imported.
"""
function extended_names(src_root)
    out = Set{String}()
    for (dir, _dirs, files) in walkdir(src_root), file in files
        endswith(file, ".jl") || continue
        for e in collect_exprs(x -> x.head in (:function, :(=)), parse_file(joinpath(dir, file)))
            call = e.args[1]
            call isa Expr && call.head === :where && (call = call.args[1])
            call isa Expr && call.head === :(::) && (call = call.args[1])
            (call isa Expr && call.head === :call) || continue
            name = call.args[1]
            name isa Symbol && push!(out, String(name))
        end
    end
    out
end

# ── interface-purity checker ───────────────────────────────────────────────

"The name an `abstract type` / `const` / `function f end` declaration introduces, else `nothing`."
decl_name(s::Symbol) = s
function decl_name(e::Expr)
    e.head === :curly && return decl_name(e.args[1])   # abstract type Foo{T}
    e.head === :<:    && return decl_name(e.args[1])   # abstract type Foo <: Bar
    nothing
end
decl_name(::Any) = nothing

"A `const` may bind only a type expression (`Union{…}`, `Foo{T}`, `Bar`) — a call is state."
is_type_expr(x) = x isa Symbol || (x isa Expr && x.head in (:curly, :<:, :.))

"""
    interface_purity_errors(src_root, interface_files, entries) -> Vector{String}

Assert PAR-INTERFACE-DECLARES-ONLY over each declared interface file: it *declares*,
and never *implements*. Legal at top level — inside the `module` block, or in a bare
fragment file — are the module docstring, an `abstract type`, a `const` type
alias, an open generic as a bodiless `function f end`, and module plumbing
(`module` / `export` / `using` / `import` / `include`). Anything carrying a body
is implementation: a short- or long-form method (a default and an error fallback
included — a default is behaviour), a macro, a concrete `struct`, a `const` bound
to a call. It belongs in the sibling file that implements the contract.

Purity is decidable from the AST: a bodiless `function f end` parses to a
one-argument `Expr(:function)`, a method to a two-argument one.

Also assert the export half of PAR-INTERFACE-DECLARES-ONLY: every name an
interface file declares is exported by its owning module (`interface_files`
maps the file's path, relative
to `src_root`, to that module). An interface file has no private half — its
export list *is* the layer's API surface.
"""
function interface_purity_errors(src_root, interface_files, entries)
    mod_exports = Dict(mod => Set(exports) for (_, mod, _, _, exports) in entries)
    errs = String[]
    for (rel, mod) in sort(collect(interface_files))
        path = joinpath(src_root, rel)
        isfile(path) || (push!(errs, "$rel: declared an interface file but not on disk"); continue)
        haskey(mod_exports, mod) || (push!(errs, "$rel: no file defines its owning module $mod"); continue)
        declared = Symbol[]
        scan_interface!(errs, declared, rel, parse_file(path), Ref(0))
        for name in declared
            name in mod_exports[mod] || push!(errs,
                "$rel declares $name but $mod does not export it — an interface file " *
                "has no private half (PAR-INTERFACE-DECLARES-ONLY); export it, or move " *
                "it to an implementation file")
        end
    end
    errs
end

# Walk one interface file's top level, collecting the names it declares and an
# error per expression that implements rather than declares. `line` tracks the
# most recent LineNumberNode so a violation can name its line.
function scan_interface!(errs, declared, rel, x, line)
    bad(what, fix) = push!(errs, "$rel:$(line[]) $what — an interface file declares, " *
                                 "it never implements (PAR-INTERFACE-DECLARES-ONLY); $fix")
    if x isa LineNumberNode
        line[] = x.line
    elseif x isa Expr
        if x.head in (:toplevel, :block)
            foreach(a -> scan_interface!(errs, declared, rel, a, line), x.args)
        elseif x.head === :module
            scan_interface!(errs, declared, rel, x.args[3], line)
        elseif x.head === :macrocall && x.args[1] === GlobalRef(Core, Symbol("@doc"))
            scan_interface!(errs, declared, rel, last(x.args), line)   # the documented form
        elseif x.head === :abstract
            name = decl_name(x.args[1])
            name === nothing || push!(declared, name)
        elseif x.head === :const
            assignment = x.args[1]
            name, value = assignment.args[1], assignment.args[2]
            if is_type_expr(value)
                n = decl_name(name)
                n === nothing || push!(declared, n)
            else
                bad("`const $(decl_name(name))` binds a value, not a type alias",
                    "state and computed constants belong in an implementation file")
            end
        elseif x.head === :function
            if length(x.args) == 1                                     # `function f end`
                name = decl_name(x.args[1])
                name === nothing || push!(declared, name)
            else
                bad("defines a method", "move the body to the file that implements the contract")
            end
        elseif x.head === :(=) && x.args[1] isa Expr &&
               x.args[1].head in (:call, :where)                       # `f(x) = …`
            bad("defines a method", "move the body to the file that implements the contract")
        elseif x.head === :struct
            bad("defines a concrete struct", "an interface declares only abstract types")
        elseif x.head === :macro
            bad("defines a macro", "a macro is implementation")
        elseif !(x.head in (:export, :using, :import)) &&
               !(x.head === :call && x.args[1] === :include)
            bad("is a top-level `$(x.head)` expression", "an interface file only declares")
        end
    end
end

# ── the shared entry point ─────────────────────────────────────────────────

"""
    get_package_source_root(pkg) -> String

The folder a package's source lives in: `source/<slice>/` at the repository
root. A package is a name and an include list; the two do not share a directory
(`plan/done/repository-tree.md`), so the root file `pathof` returns is the
**top file** and this is the `src_root` beside it.

The package root file sits three levels below the repository root, both before
and after the flattening of `package/`, so the depth is stable. The slice folder
is the package name without its `Projectured` prefix, in lower case.
"""
get_package_source_root(pkg::Module) =
    normpath(joinpath(dirname(pathof(pkg)), "..", "..", "..", "source",
                      lowercase(replace(String(nameof(pkg)), "Projectured" => ""))))

"""
    check_layering(src_root, top_file; name = "package",
                   layers = String[], exempt_files = Set{String}(),
                   check_private_imports = false,
                   interface_files = Dict{String, Symbol}(),
                   unmigrated_files = Set{String}())

Run the full static layered-architecture guard for one main package inside
a `@testset`:

1. every on-disk `.jl` file under `src_root` is reached by `top_file`'s
   include tree exactly once,
2. every module is defined by exactly one file (top-level includes may be
   module files or per-layer fragments listing the layer's module files),
3. the module files' include order is a valid topological order over the real
   `import ..XxxModule` edges (module aliases to lower packages are exempt),
4. declared `layers` respect their index (skipped when `layers` is empty),
5. cross-layer symbol imports name only exported symbols (opt-in via
   `check_private_imports = true`, requires `layers`; enable per package once
   its imports are clean),
6. each file in `interface_files` (a path ⇒ owning-module map) declares and
   never implements, and exports every name it declares
   (PAR-INTERFACE-DECLARES-ONLY); the map is per package, so a package opts its
   interface files in as they come clean,
7. every `XxxModule.sym` qualification names an exported symbol
   (PAR-MODULE-BOUNDARY-IS-API's other half — always runs, since qualification is new
   syntax with no legacy to grandfather; `layers` only drives its exemptions),
8. every file outside `unmigrated_files` imports only what it extends and never
   `import ..Xxx` / `using ..Xxx: a, b` (PAR-QUALIFIED-EXTENSION); the set is opt-in
   and grows as the migration proceeds.

`src_root` is the folder whose `.jl` files the include tree must reach, and the
root that layer folders are read against. `top_file` can sit outside it — a
package whose root file lives in `package/<Name>/src/` and whose source lives in
a repository-level folder passes that folder. A reached file outside `src_root`
(the top file, a sample the tree includes) is walked and ordered but is not
held against the on-disk set, and it lives in no layer. `foreign_files` names
files under `src_root` (relative to it) that belong to another package and so
are not expected in this include tree.
"""
function check_layering(src_root, top_file; name = "package",
                        layers = String[], exempt_files = Set{String}(),
                        check_private_imports = false,
                        interface_files = Dict{String, Symbol}(),
                        unmigrated_files = Set{String}(),
                        extra_aliases = Set{Symbol}(),
                        allow_root_fragments = false,
                        foreign_files = Set{String}())
    @testset "$name layered-architecture guard" begin
        reached, entries, file_owner, _ =
            walk_includes(top_file, src_root; allow_root_fragments)

        @testset "every src file is included exactly once" begin
            @test length(reached) == length(unique(reached))
            on_disk = Set{String}()
            for (root, _, files) in walkdir(src_root), f in files
                endswith(f, ".jl") || continue
                rel = relpath(joinpath(root, f), src_root)
                rel in foreign_files || push!(on_disk, rel)
            end
            # A file outside `src_root` — the top file of a package whose
            # source sits in a repository-level folder, or a sample it
            # includes — is walked and ordered but is not the source tree's
            # own, so it is neither expected on disk nor reported as extra.
            inside = Set(r for r in reached if !startswith(r, ".."))
            missing_from_includes = setdiff(on_disk, inside)
            extra_in_includes     = setdiff(inside, on_disk)
            if !isempty(missing_from_includes)
                println(stderr, "\nFiles on disk but not reached by the include tree:")
                foreach(f -> println(stderr, "  ", f), sort(collect(missing_from_includes)))
            end
            if !isempty(extra_in_includes)
                println(stderr, "\nFiles included but not on disk:")
                foreach(f -> println(stderr, "  ", f), sort(collect(extra_in_includes)))
            end
            @test isempty(missing_from_includes)
            @test isempty(extra_in_includes)
        end

        @testset "each module is defined by exactly one file" begin
            names = [m for (_, m, _) in entries]
            @test length(names) == length(unique(names))
        end

        # A module the top file binds as a literal `const`, plus whatever the
        # caller knows the file binds another way. A package whose root module
        # binds its dependencies' submodules with a loop rather than a written
        # table has no `const` line to read, so the caller passes the set it
        # measured from the loaded package.
        aliases = union(alias_names(top_file), extra_aliases)

        @testset "includes are a valid topological order" begin
            errs = topo_errors(entries, aliases)
            if !isempty(errs)
                println(stderr, "\nInclude-order violations in $(basename(top_file)):")
                foreach(e -> println(stderr, "  ", e), errs)
            end
            @test isempty(errs)
        end

        if !isempty(layers)
            @testset "declared layers respect the layer index" begin
                errs = layer_errors(entries, layers, exempt_files)
                if !isempty(errs)
                    println(stderr, "\nLayer-index violations (layers = $layers):")
                    foreach(e -> println(stderr, "  ", e), errs)
                end
                @test isempty(errs)
            end
        end

        if check_private_imports && !isempty(layers)
            @testset "cross-layer imports name only exported symbols" begin
                errs = private_import_errors(entries, layers, exempt_files)
                if !isempty(errs)
                    println(stderr, "\nCross-layer private-symbol imports:")
                    foreach(e -> println(stderr, "  ", e), errs)
                end
                @test isempty(errs)
            end
        end

        if !isempty(interface_files)
            @testset "interface files declare, never implement" begin
                errs = interface_purity_errors(src_root, interface_files, entries)
                if !isempty(errs)
                    println(stderr, "\nInterface-purity violations (PAR-INTERFACE-DECLARES-ONLY):")
                    foreach(e -> println(stderr, "  ", e), errs)
                end
                @test isempty(errs)
            end
        end

        @testset "qualified references name only exported symbols" begin
            errs = qualified_reference_errors(src_root, file_owner, entries,
                                              layers, exempt_files)
            if !isempty(errs)
                println(stderr, "\nQualified non-exported access (PAR-MODULE-BOUNDARY-IS-API):")
                foreach(e -> println(stderr, "  ", e), errs)
            end
            @test isempty(errs)
        end

        @testset "every file imports what it extends" begin
            errs = relative_import_errors(src_root, unmigrated_files)
            if !isempty(errs)
                println(stderr, "\nImport-form violations (PAR-QUALIFIED-EXTENSION):")
                foreach(e -> println(stderr, "  ", e), errs)
            end
            @test isempty(errs)
        end
    end
end

"""
    check_slice_edges(src_root, top_files, allowed; name = "package")

The static guard of the edges between the slices of one package, whose module
files sit in slice folders under `src_root`. It walks the include tree of each
of `top_files`, and fails for each import that crosses from one slice to
another where `allowed`, a map from a slice to the slices that it may use, does
not permit it. The slices that the include trees reach are exactly the keys of
`allowed`, so a new slice needs its row in the table.
"""
function check_slice_edges(src_root, top_files, allowed; name = "package")
    @testset "$name edges between slices" begin
        entries = Tuple{String, Symbol, Vector{Symbol},
                        Vector{Pair{Symbol, Vector{Symbol}}}, Vector{Symbol}}[]
        for file in top_files
            append!(entries, walk_includes(file, src_root)[2])
        end
        @test sort(unique(layer_of(entry[1]) for entry in entries)) ==
              sort(collect(keys(allowed)))
        for err in slice_edge_errors(entries, allowed)
            @test err == ""
        end
    end
end

# ── self-tests for the checkers ────────────────────────────────────────────

"""
    test_layering_checkers()

Self-tests for `topo_errors` / `layer_errors` / `private_import_errors` on
synthetic entry lists, and for the `walk_includes` walker on a synthetic
package tree.
"""
function test_layering_checkers()
    @testset "walk_includes handles module files and layer fragments" begin
        mktempdir() do root
            # Top module includes one module file directly and one layer
            # fragment whose includes are the layer's module files, in order.
            mkpath(joinpath(root, "cell"))
            mkpath(joinpath(root, "document"))
            write(joinpath(root, "Top.jl"), """
                module Top
                include("cell/A.jl")
                include("document/DocumentLayer.jl")
                end
                """)
            write(joinpath(root, "cell/A.jl"), "module A\nend\n")
            write(joinpath(root, "document/DocumentLayer.jl"), """
                include("B.jl")
                include("C.jl")
                """)
            write(joinpath(root, "document/B.jl"),
                  "module B\nimport ..A: a_pub\ninclude(\"BFragment.jl\")\nexport b_pub\nend\n")
            write(joinpath(root, "document/BFragment.jl"),
                  "import ..A\nusing ..C: var\"@c_macro\"\nexport b_frag\n")
            write(joinpath(root, "document/C.jl"), "module C\nexport @c_macro, c_pub\nend\n")

            reached, entries = walk_includes(joinpath(root, "Top.jl"), root)
            # Every file reached exactly once, layer fragment included.
            @test sort(reached) == sort(["Top.jl", "cell/A.jl",
                                         "document/DocumentLayer.jl", "document/B.jl",
                                         "document/BFragment.jl", "document/C.jl"])
            # One entry per module file, in include order; the fragment's
            # imports fold into its enclosing module's deps.
            @test [(m, sort(d)) for (_, m, d) in entries] ==
                  [(:A, Symbol[]), (:B, [:A, :C]), (:C, Symbol[])]
            # Per-import symbol lists and exports fold in the same way; a
            # plain `import ..A` yields an unconstrained `A => []`, and
            # `var"@c_macro"` / `export @c_macro` both parse to `@c_macro`.
            @test entries[2][4] == [:A => [:a_pub], :A => Symbol[],
                                    :C => [Symbol("@c_macro")]]
            @test entries[2][5] == [:b_pub, :b_frag]
            @test entries[3][5] == [Symbol("@c_macro"), :c_pub]
            # B imports ..C, which the layer fragment includes later.
            @test length(topo_errors(entries)) == 1
            # B imports a_pub across layers, but A does not export it.
            errs = private_import_errors(entries, ["cell", "document"])
            @test length(errs) == 1
            @test occursin("a_pub", errs[1])
            # Exporting a_pub from A makes the same import legal.
            write(joinpath(root, "cell/A.jl"), "module A\nexport a_pub\nend\n")
            _, entries_fixed = walk_includes(joinpath(root, "Top.jl"), root)
            @test isempty(private_import_errors(entries_fixed, ["cell", "document"]))

            # A layer fragment carrying its own relative import is an error.
            write(joinpath(root, "document/DocumentLayer.jl"), """
                import ..A
                include("B.jl")
                include("C.jl")
                """)
            @test_throws ErrorException walk_includes(joinpath(root, "Top.jl"), root)
        end
    end

    @testset "check_layering accepts a top file outside src_root" begin
        mktempdir() do root
            # The package root sits in `package/src/`; the source in `source/`
            # beside it, with one file that belongs to another package; and
            # the tree includes a sample from outside the source folder.
            mkpath(joinpath(root, "package/src"))
            mkpath(joinpath(root, "source/cell"))
            mkpath(joinpath(root, "source/foreign"))
            mkpath(joinpath(root, "sample"))
            write(joinpath(root, "package/src/Top.jl"), """
                module Top
                include("../../source/cell/CellLayer.jl")
                include("../../sample/Sample.jl")
                end
                """)
            write(joinpath(root, "source/cell/CellLayer.jl"), "include(\"A.jl\")\n")
            write(joinpath(root, "source/cell/A.jl"), "module A\nexport a_pub\nend\n")
            write(joinpath(root, "source/foreign/F.jl"), "module F\nend\n")
            write(joinpath(root, "sample/Sample.jl"), "module Sample\nusing ..A\nend\n")
            src_root = joinpath(root, "source")
            top = joinpath(root, "package/src/Top.jl")
            reached, entries = walk_includes(top, src_root)
            @test "cell/A.jl" in reached
            @test count(r -> startswith(r, ".."), reached) == 2   # the top file and the sample
            @test [m for (_, m, _) in entries] == [:A, :Sample]
            # The sample lives in no layer, so its import of a layer module is
            # not held to the layer index.
            @test isempty(layer_errors(entries, ["cell"]))
            # The foreign file is the one on-disk file the tree does not reach.
            on_disk = String[]
            for (d, _, files) in walkdir(src_root), f in files
                push!(on_disk, relpath(joinpath(d, f), src_root))
            end
            inside = filter(r -> !startswith(r, ".."), reached)
            @test setdiff(on_disk, inside) == ["foreign/F.jl"]
        end
    end

    @testset "topo_errors detects a forward edge" begin
        # A depends on B but is ordered first ⇒ one error naming A→B.
        bad  = [("a.jl", :A, [:B]), ("b.jl", :B, Symbol[])]
        @test length(topo_errors(bad)) == 1
        @test occursin("..B", topo_errors(bad)[1])

        # Reordering B before A fixes it.
        good = [("b.jl", :B, Symbol[]), ("a.jl", :A, [:B])]
        @test isempty(topo_errors(good))

        # A dependency no file defines is reported distinctly.
        dangling = [("a.jl", :A, [:Ghost])]
        @test occursin("no file defines", topo_errors(dangling)[1])

        # An alias satisfies a dep without an entry defining it.
        @test isempty(topo_errors(dangling, Set([:Ghost])))
    end

    @testset "layer_errors detects an upward edge" begin
        layers = ["cell", "document"]
        # cell/A imports ..B where B is defined in document/ — upward, error.
        bad = [("document/B.jl", :B, Symbol[]),
               ("cell/A.jl",     :A, [:B])]
        errs = layer_errors(bad, layers)
        @test length(errs) == 1
        @test occursin("higher layer", errs[1])

        # document/A imports ..B where B is in cell/ — downward, OK.
        good = [("cell/B.jl",     :B, Symbol[]),
                ("document/A.jl", :A, [:B])]
        @test isempty(layer_errors(good, layers))

        # An importer under a non-layers folder is exempt.
        exempt_importer = [("document/B.jl", :B, Symbol[]),
                           ("common/A.jl",   :A, [:B])]
        @test isempty(layer_errors(exempt_importer, layers))

        # A dep pointing into a non-layers folder is exempt.
        exempt_dep = [("common/B.jl", :B, Symbol[]),
                      ("cell/A.jl",   :A, [:B])]
        @test isempty(layer_errors(exempt_dep, layers))

        # A per-file exemption suppresses the upward-edge error for that importer.
        upward = [("document/B.jl", :B, Symbol[]),
                  ("cell/A.jl",     :A, [:B])]
        @test length(layer_errors(upward, layers)) == 1
        @test isempty(layer_errors(upward, layers, Set(["cell/A.jl"])))
    end

    @testset "private_import_errors flags cross-layer non-exported symbols" begin
        layers = ["cell", "document"]
        no_syms = Pair{Symbol, Vector{Symbol}}[]
        # document/A imports exported :pub and private :_priv from cell/B —
        # exactly one error, naming the private symbol.
        bad = [("cell/B.jl",     :B, Symbol[], no_syms, [:pub]),
               ("document/A.jl", :A, [:B], [:B => [:pub, :_priv]], Symbol[])]
        errs = private_import_errors(bad, layers)
        @test length(errs) == 1
        @test occursin("_priv", errs[1]) && occursin("..B", errs[1])

        # Exported-names-only import is clean.
        good = [bad[1], ("document/A.jl", :A, [:B], [:B => [:pub]], Symbol[])]
        @test isempty(private_import_errors(good, layers))

        # Same-layer neighbours may share internals.
        same = [("cell/B.jl", :B, Symbol[], no_syms, [:pub]),
                ("cell/A.jl", :A, [:B], [:B => [:_priv]], Symbol[])]
        @test isempty(private_import_errors(same, layers))

        # Plain `import ..B` (empty symbol list) is unconstrained.
        plain = [bad[1], ("document/A.jl", :A, [:B], [:B => Symbol[]], Symbol[])]
        @test isempty(private_import_errors(plain, layers))

        # A dep no entry defines (package alias) is exempt.
        alias = [("document/A.jl", :A, [:X], [:X => [:_priv]], Symbol[])]
        @test isempty(private_import_errors(alias, layers))

        # A dep in a non-layers folder is exempt, as is an importer there.
        dep_out = [("common/B.jl",   :B, Symbol[], no_syms, Symbol[]),
                   ("document/A.jl", :A, [:B], [:B => [:_priv]], Symbol[])]
        @test isempty(private_import_errors(dep_out, layers))
        importer_out = [("cell/B.jl",   :B, Symbol[], no_syms, Symbol[]),
                        ("common/A.jl", :A, [:B], [:B => [:_priv]], Symbol[])]
        @test isempty(private_import_errors(importer_out, layers))

        # A per-file exemption suppresses the error for that importer.
        @test isempty(private_import_errors(bad, layers, Set(["document/A.jl"])))
    end

    @testset "interface_purity_errors separates declaration from implementation" begin
        no_syms = Pair{Symbol, Vector{Symbol}}[]
        entries = [("cell/CellModule.jl", :CellModule, Symbol[], no_syms,
                    [:AbstractCell, :Reference, :is_cell_up_to_date, :get_reference_step_kind])]
        interface_files = Dict("cell/Interface.jl" => :CellModule)
        check(source) = mktempdir() do root
            mkpath(joinpath(root, "cell"))
            write(joinpath(root, "cell/Interface.jl"), source)
            interface_purity_errors(root, interface_files, entries)
        end

        # A pure interface: docstrings, an abstract type, a type alias, open generics.
        @test isempty(check("""
            \"\"\"The vocabulary.\"\"\"
            abstract type AbstractCell{T} end
            const Reference = Union{Nothing, AbstractCell}
            \"\"\"An open generic.\"\"\"
            function is_cell_up_to_date end
            """))

        # A default is behaviour — long form, short form, and a `where` method alike.
        for method in ("function is_cell_up_to_date(c::AbstractCell)\n    true\nend",
                       "is_cell_up_to_date(c::AbstractCell) = true",
                       "get_reference_step_kind(::T) where {T} = :structural")
            errs = check("abstract type AbstractCell{T} end\n$method\n")
            @test length(errs) == 1
            @test occursin("defines a method", errs[1]) && occursin("PAR-INTERFACE-DECLARES-ONLY", errs[1])
        end

        # An error fallback is a method too — the loophole this rule closes.
        @test occursin("defines a method",
                       only(check("""get_reference_step_kind(::Val{n}) where {n} = error("no method")\n""")))

        # State, a concrete struct, and a macro are all implementation.
        @test occursin("binds a value", only(check("const Reference = Ref{Any}(nothing)\n")))
        @test occursin("concrete struct", only(check("struct Reference end\n")))
        @test occursin("defines a macro", only(check("macro is_cell_up_to_date(x)\n    x\nend\n")))

        # Module plumbing is not implementation: a module wrapper, imports, an
        # `include` of the implementation fragment, and a docstring on a generic.
        @test isempty(check("""
            \"\"\"CellModule — the contract.\"\"\"
            module CellModule
            using ..Other
            import ..Other: thing
            export AbstractCell, is_cell_up_to_date
            abstract type AbstractCell{T} end
            \"\"\"An open generic.\"\"\"
            function is_cell_up_to_date end
            include("Defaults.jl")
            end
            """))

        # The export half: a declared name its module does not export.
        errs = check("abstract type AbstractCell{T} end\nfunction unexported_thing end\n")
        @test length(errs) == 1
        @test occursin("does not export it", errs[1]) && occursin("unexported_thing", errs[1])
    end

    @testset "qualified_reference_errors flags non-exported qualification" begin
        layers = ["cell", "document"]
        no_syms = Pair{Symbol, Vector{Symbol}}[]
        entries = [("cell/B.jl",     :B, Symbol[], no_syms, [:pub]),
                   ("document/A.jl", :A, Symbol[], no_syms, Symbol[])]
        file_owner = Dict("cell/B.jl" => :B, "document/A.jl" => :A)
        check(source; owner = file_owner, ents = entries) = mktempdir() do root
            mkpath(joinpath(root, "cell"));  mkpath(joinpath(root, "document"))
            write(joinpath(root, "cell/B.jl"), "module B\nexport pub\nend\n")
            write(joinpath(root, "document/A.jl"), source)
            qualified_reference_errors(root, owner, ents, layers)
        end

        # Qualifying an exported name is the PAR-QUALIFIED-EXTENSION
        # extension form — clean.
        @test isempty(check("B.pub(x::Int) = 1\n"))

        # Qualifying a non-exported name reaches past the module boundary.
        errs = check("B._priv(x::Int) = 1\n")
        @test length(errs) == 1
        @test occursin("B._priv", errs[1]) && occursin("non-exported", errs[1])

        # Reaching a private name for a *read*, not just an extension, counts too.
        @test occursin("B._secret", only(check("f() = B._secret\n")))

        # A module qualifying itself is a fragment self-reference, not a breach.
        self = Dict("cell/B.jl" => :B, "document/A.jl" => :B)   # A.jl is a fragment of B
        @test isempty(check("B._priv(x::Int) = 1\n"; owner = self))

        # `Base.show` and other non-package modules are none of our business.
        @test isempty(check("Base.show(io::IO, x::Int) = nothing\nMOI.optimize!(m) = m\n"))

        # Unlike private_import_errors there is NO same-layer exemption:
        # qualification is new syntax under PAR-QUALIFIED-EXTENSION, so there is no
        # legacy to grandfather.
        same_layer = [("cell/B.jl", :B, Symbol[], no_syms, [:pub]),
                      ("cell/A.jl", :A, Symbol[], no_syms, Symbol[])]
        same_owner = Dict("cell/B.jl" => :B, "cell/A.jl" => :A)
        errs = mktempdir() do root
            mkpath(joinpath(root, "cell"))
            write(joinpath(root, "cell/B.jl"), "module B\nexport pub\nend\n")
            write(joinpath(root, "cell/A.jl"), "B._priv(x::Int) = 1\n")
            qualified_reference_errors(root, same_owner, same_layer, layers)
        end
        @test length(errs) == 1

        # A per-file exemption suppresses it.
        @test isempty(mktempdir() do root
            mkpath(joinpath(root, "cell"));  mkpath(joinpath(root, "document"))
            write(joinpath(root, "cell/B.jl"), "module B\nexport pub\nend\n")
            write(joinpath(root, "document/A.jl"), "B._priv(x::Int) = 1\n")
            qualified_reference_errors(root, file_owner, entries, layers,
                                       Set(["document/A.jl"]))
        end)
    end

    @testset "relative_import_errors enforces the PAR-QUALIFIED-EXTENSION import form" begin
        check(source) = mktempdir() do root
            mkpath(joinpath(root, "cell"))
            write(joinpath(root, "cell/A.jl"), source)
            relative_import_errors(root, Set{String}())
        end

        # Bare `using ..B` and a qualified extension: nothing to import.
        @test isempty(check("using ..B\nB.f(x::Int) = 1\n"))

        # `import ..B: f` where `f` is extended here — the blessed form.
        @test isempty(check("import ..B: f\nf(x::Int) = 1\n"))

        # `import ..B: f, g` where neither is extended — the list says what this
        # code implements, and it implements nothing.
        errs = check("import ..B: f, g\n")
        @test length(errs) == 1
        @test occursin("f, g", errs[1]) && occursin("extends them nowhere", errs[1])

        # One name extended, one not: only the idle one is reported.
        errs = check("import ..B: f, g\nf(x::Int) = 1\n")
        @test length(errs) == 1
        @test occursin("imports g", errs[1])

        # Bare `import ..B` is banned: bare `using` already binds the name.
        @test occursin("bare `import ..B`", only(check("import ..B\n")))

        # A `using` symbol list is banned as well — it says nothing either way.
        @test occursin("using ..B: f", only(check("using ..B: f\n")))

        # Absolute imports (Base, stdlib, external packages) are not
        # PAR-QUALIFIED-EXTENSION's business.
        @test isempty(check("import Base\nusing Test\nimport MathOptInterface as MOI\n"))

        # A file named in the exemption set is untouched by the lint.
        @test isempty(mktempdir() do root
            mkpath(joinpath(root, "cell"))
            write(joinpath(root, "cell/A.jl"), "import ..B: f\n")
            relative_import_errors(root, Set(["cell/A.jl"]))
        end)

        # An exempt file that is not on disk is itself an error — the set must not go stale.
        @test occursin("not on disk",
                       only(mktempdir(root -> relative_import_errors(root, Set(["gone.jl"])))))
    end

    @testset "slice_edge_errors allows only the edges of the table" begin
        entries = [("a/AModule.jl", :AModule, Symbol[]),
                   ("b/BModule.jl", :BModule, [:AModule, :KernelLikeModule]),
                   ("b/BHelperModule.jl", :BHelperModule, [:BModule])]
        # An edge inside a slice, and one to a module that no entry defines, pass.
        @test isempty(slice_edge_errors(entries, Dict("a" => String[], "b" => ["a"])))
        errs = slice_edge_errors(entries, Dict("a" => String[], "b" => String[]))
        @test length(errs) == 1 && occursin("..AModule of the slice a", only(errs))
    end
end
