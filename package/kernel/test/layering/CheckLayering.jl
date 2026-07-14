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
#    AR-48 forbids reaching into a sibling module's internals too, and the
#    same-layer case is enforced per package once its imports are clean. A plain
#    `import ..XxxModule` is unconstrained.
# 6. (opt-in via `interface_files`) every declared interface file declares and
#    never implements, and exports every name it declares (AR-72).
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
"""
function walk_includes(top_file, src_root)
    reached = String[]
    entries = Tuple{String, Symbol, Vector{Symbol},
                    Vector{Pair{Symbol, Vector{Symbol}}}, Vector{Symbol}}[]

    # Descend into `file`. `in_module` says whether a module-file ancestor
    # encloses it; returns the `(imports, sym_imports, exports)` to fold into
    # that ancestor (all empty for module files, which emit an entry instead).
    function descend(file, in_module)
        rel = relpath(file, src_root)
        push!(reached, rel)
        ast = parse_file(file)
        mods = collect_exprs(e -> e.head === :module, ast)
        if length(mods) > 1
            error("$rel defines $(length(mods)) modules; expected 0 (fragment) or 1 (module)")
        end
        if length(mods) == 1 && in_module
            error("$rel defines a module but is included inside another module file")
        end
        body = length(mods) == 1 ? mods[1].args[3] : ast
        imports, includes, sym_imports, exports = collect_edges(body)
        if length(mods) == 0 && !in_module && !isempty(imports)
            error("$rel is a layer fragment with relative imports; only module files may import ..Xxx")
        end
        # Recurse into includes, aggregating fragment imports/exports upward.
        for inc in includes
            child_path = joinpath(dirname(file), inc)
            isfile(child_path) || error("$rel includes \"$inc\" but the file does not exist")
            child_imports, child_syms, child_exports =
                descend(child_path, in_module || length(mods) == 1)
            append!(imports, child_imports)
            append!(sym_imports, child_syms)
            append!(exports, child_exports)
        end
        if length(mods) == 1
            # Module file: emit an entry, but do not propagate deps upward.
            name = mods[1].args[2]::Symbol
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
        descend(child_path, false)
    end
    reached, entries
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

Known limitation: qualified private access (`XxxModule._name` in code or
macro output) is not caught — today's only instances are same-module fragment
self-references; this check keeps the common import-header path honest.
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
            dep_idx == my_idx && continue       # same layer — exempt for now (transitional; AR-48 forbids this, staged per package)
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

Assert AR-72 over each declared interface file: it *declares*, and never
*implements*. Legal at top level — inside the `module` block, or in a bare
fragment file — are the module docstring, an `abstract type`, a `const` type
alias, an open generic as a bodiless `function f end`, and module plumbing
(`module` / `export` / `using` / `import` / `include`). Anything carrying a body
is implementation: a short- or long-form method (a default and an error fallback
included — a default is behaviour), a macro, a concrete `struct`, a `const` bound
to a call. It belongs in the sibling file that implements the contract.

Purity is decidable from the AST: a bodiless `function f end` parses to a
one-argument `Expr(:function)`, a method to a two-argument one.

Also assert the export half of AR-72: every name an interface file declares is
exported by its owning module (`interface_files` maps the file's path, relative
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
                "has no private half (AR-72); export it, or move it to an implementation file")
        end
    end
    errs
end

# Walk one interface file's top level, collecting the names it declares and an
# error per expression that implements rather than declares. `line` tracks the
# most recent LineNumberNode so a violation can name its line.
function scan_interface!(errs, declared, rel, x, line)
    bad(what, fix) = push!(errs, "$rel:$(line[]) $what — an interface file declares, " *
                                 "it never implements (AR-72); $fix")
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
    check_layering(src_root, top_file; name = "package",
                   layers = String[], exempt_files = Set{String}(),
                   check_private_imports = false,
                   interface_files = Dict{String, Symbol}())

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
   never implements, and exports every name it declares (AR-72); the map is
   per package, so a package opts its interface files in as they come clean.
"""
function check_layering(src_root, top_file; name = "package",
                        layers = String[], exempt_files = Set{String}(),
                        check_private_imports = false,
                        interface_files = Dict{String, Symbol}())
    @testset "$name layered-architecture guard" begin
        reached, entries = walk_includes(top_file, src_root)

        @testset "every src file is included exactly once" begin
            @test length(reached) == length(unique(reached))
            on_disk = Set{String}()
            for (root, _, files) in walkdir(src_root), f in files
                endswith(f, ".jl") || continue
                push!(on_disk, relpath(joinpath(root, f), src_root))
            end
            missing_from_includes = setdiff(on_disk, Set(reached))
            extra_in_includes     = setdiff(Set(reached), on_disk)
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

        aliases = alias_names(top_file)

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
                    println(stderr, "\nInterface-purity violations (AR-72):")
                    foreach(e -> println(stderr, "  ", e), errs)
                end
                @test isempty(errs)
            end
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
                    [:AbstractCell, :Reference, :is_up_to_date, :step_kind])]
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
            function is_up_to_date end
            """))

        # A default is behaviour — long form, short form, and a `where` method alike.
        for method in ("function is_up_to_date(c::AbstractCell)\n    true\nend",
                       "is_up_to_date(c::AbstractCell) = true",
                       "step_kind(::T) where {T} = :structural")
            errs = check("abstract type AbstractCell{T} end\n$method\n")
            @test length(errs) == 1
            @test occursin("defines a method", errs[1]) && occursin("AR-72", errs[1])
        end

        # An error fallback is a method too — the loophole this rule closes.
        @test occursin("defines a method",
                       only(check("""step_kind(::Val{n}) where {n} = error("no method")\n""")))

        # State, a concrete struct, and a macro are all implementation.
        @test occursin("binds a value", only(check("const Reference = Ref{Any}(nothing)\n")))
        @test occursin("concrete struct", only(check("struct Reference end\n")))
        @test occursin("defines a macro", only(check("macro is_up_to_date(x)\n    x\nend\n")))

        # Module plumbing is not implementation: a module wrapper, imports, an
        # `include` of the implementation fragment, and a docstring on a generic.
        @test isempty(check("""
            \"\"\"CellModule — the contract.\"\"\"
            module CellModule
            using ..Other
            import ..Other: thing
            export AbstractCell, is_up_to_date
            abstract type AbstractCell{T} end
            \"\"\"An open generic.\"\"\"
            function is_up_to_date end
            include("Defaults.jl")
            end
            """))

        # The export half: a declared name its module does not export.
        errs = check("abstract type AbstractCell{T} end\nfunction unexported_thing end\n")
        @test length(errs) == 1
        @test occursin("does not export it", errs[1]) && occursin("unexported_thing", errs[1])
    end
end
