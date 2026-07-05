"""
Kernel layered-architecture guard rail
(plan/pending/kernel-layered-architecture.md, phase P0).

`package/kernel/src/ProjecturedKernel.jl` is a hand-maintained topological sort:
each top-level `include("…")` must appear *after* the files defining every
`..XxxModule` it imports. This test enforces the layering **statically, without
loading the package**, in ~1s, so a regression is caught with a message naming
the offending file and the module it references too early.

The guard is **fragment-aware**: a `Module.jl` aggregator can `include(…)`
0-module *fragment* files that share its namespace. The walker recursively
follows every `include(...)` from the top file, collects each fragment's imports
under its nearest module-defining ancestor, and asserts:

1. every on-disk `.jl` file is reached by the include tree exactly once,
2. every top-level include names a module defined by exactly one file,
3. the top-level include list is a valid topological order over the union of
   own+fragment imports,
4. for files that live under a declared `LAYERS` folder, every `..XxxModule`
   dep resolves to a module whose file also lives under a LAYERS folder of
   index ≤ the importer's (non-LAYERS folders are exempt during transition).

After the static checks, per-layer test suites under `test/<layer>/` are run.
Filter with `Pkg.test(test_args=["cell","projection"])` (or run a layer's
`test/<layer>/runtests.jl` directly).
"""

using Test

const KERNEL_SRC = normpath(joinpath(@__DIR__, "..", "src"))
const TOP_FILE   = joinpath(KERNEL_SRC, "ProjecturedKernel.jl")
const DOT        = Symbol(".")

# Declared layers, in order of increasing index. Non-LAYERS folders are exempt
# from the layer-index check during transition; the final phase forbids them.
const LAYERS = String["cell", "document", "reference", "operation", "device", "backend", "agent"]

# Transitional file-level exemptions: concrete engine documents currently live
# under `document/` but leave the kernel entirely at P7 (base package). Until
# then, they import from higher layers (Reference/Operation/…) which the layer
# rule would flag. They are exempted by relpath here; the P7 phase removes both
# the files and this list.
const LAYER_EXEMPT_FILES = Set{String}([
    "document/Collection.jl",
    "document/Primitive.jl",
    "document/ScreenDocument.jl",
])

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
intra-kernel ordering edge.
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
Return the direct relative-module imports and the ordered list of `include(...)`
paths appearing at the top level of `body_expr`. Statements are considered
top-level within the passed expression (a module body, or a bare fragment body).
"""
function collect_edges(body_expr)
    imports = Symbol[]
    includes = String[]
    stmts = body_expr isa Expr ?
        (body_expr.head === :block ? body_expr.args : (body_expr,)) :
        ()
    for stmt in stmts
        stmt isa Expr || continue
        if stmt.head === :call && length(stmt.args) >= 2 &&
                stmt.args[1] === :include && stmt.args[2] isa AbstractString
            push!(includes, stmt.args[2])
        elseif stmt.head in (:import, :using)
            for arg in stmt.args
                d = relative_module(arg)
                d === nothing || push!(imports, d)
            end
        end
    end
    imports, includes
end

# ── fragment-aware include walker ──────────────────────────────────────────

"""
Walk the include tree rooted at `top_file`, recursively following each
`include(...)` relative to the including file's directory. Return
`(reached, entries)`:

- `reached::Vector{String}` — every file reached (relpath to `src_root`), in
  visit order; used to check every on-disk file is included exactly once.
- `entries::Vector{Tuple{String,Symbol,Vector{Symbol}}}` — one entry per
  **top-level** include in `top_file`: `(rel_path, module_name, agg_deps)`,
  where `agg_deps` is the union of that module's own `import ..X`s and every
  fragment file it (transitively) includes.

A file whose AST defines exactly one `module` is a *module file*; its
`agg_deps` includes descendant fragments' imports. A file with zero `module`s
is a *fragment*: its imports are folded into the nearest module ancestor's
`agg_deps`. A file with 2+ modules is an error.
"""
function walk_includes(top_file, src_root)
    reached = String[]
    entries = Tuple{String, Symbol, Vector{Symbol}}[]

    # Recursively collect (imports_below, includes_visited) rooted at `file`,
    # where `imports_below` is the set of module-symbol deps that belong to
    # the nearest *module* ancestor.
    function descend(file)
        rel = relpath(file, src_root)
        push!(reached, rel)
        ast = parse_file(file)
        mods = collect_exprs(e -> e.head === :module, ast)
        if length(mods) > 1
            error("$rel defines $(length(mods)) modules; expected 0 (fragment) or 1 (module)")
        end
        body = length(mods) == 1 ? mods[1].args[3] : ast
        imports, includes = collect_edges(body)
        # Recurse into includes, aggregating fragment imports upward.
        for inc in includes
            child_path = joinpath(dirname(file), inc)
            isfile(child_path) || error("$rel includes \"$inc\" but the file does not exist")
            child_imports = descend(child_path)
            append!(imports, child_imports)
        end
        if length(mods) == 1
            # Module file: emit an entry, but do not propagate deps upward.
            name = mods[1].args[2]::Symbol
            (nothing, name, unique(imports))
        else
            # Fragment: propagate imports to the enclosing module.
            unique(imports)
        end
    end

    # The top file itself is `module ProjecturedKernel ... end`. We do NOT
    # emit an entry for it, but we do emit one per top-level include.
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
        child_rel = relpath(child_path, src_root)
        result = descend(child_path)
        result isa Tuple || error("$child_rel is a fragment — top-level includes must define a module")
        _, name, deps = result
        push!(entries, (child_rel, name, deps))
    end
    reached, entries
end

# ── pure topological checker ───────────────────────────────────────────────

"""
    topo_errors(entries) -> Vector{String}

`entries` is an ordered `Vector` of `(label, module_name, deps)`. Returns a
human-readable error for every dependency that is not satisfied by an *earlier*
entry — either a forward edge (the module is defined later) or a dangling
reference (no entry defines it at all). Empty result ⇒ valid topological order.
"""
function topo_errors(entries)
    all_mods = Set(m for (_, m, _) in entries)
    seen = Set{Symbol}()
    errs = String[]
    for (i, (label, mod, deps)) in enumerate(entries)
        for d in deps
            if d in seen
                continue
            elseif d in all_mods
                push!(errs, "[$i] $label ($mod) imports ..$d, which is included later — move $label after it")
            else
                push!(errs, "[$i] $label ($mod) imports ..$d, which no kernel file defines")
            end
        end
        push!(seen, mod)
    end
    errs
end

# ── layer checker ──────────────────────────────────────────────────────────

"""Return the top-level folder name for a relpath (`"cell/CellModule.jl"` → `"cell"`).
Returns `""` if the file lives directly under `src/`."""
function layer_of(rel::AbstractString)
    parts = splitpath(rel)
    length(parts) >= 2 ? parts[1] : ""
end

"""
    layer_errors(entries, layers) -> Vector{String}

Assert that for every entry whose file lives under a declared LAYERS folder,
every dep resolves to a module whose file is also under a LAYERS folder of
index ≤ the importer's. Non-LAYERS folders are exempt (a dep pointing into a
non-LAYERS folder does not constrain the importer, and an importer in a
non-LAYERS folder skips the check). This is the transition-safe form; the
final phase removes the exemption.
"""
function layer_errors(entries, layers, exempt_files = Set{String}())
    # Build module → layer index (or `nothing` if outside LAYERS).
    idx_of_layer = Dict(l => i for (i, l) in enumerate(layers))
    mod_layer = Dict{Symbol, Union{Int, Nothing}}()
    for (rel, mod, _) in entries
        mod_layer[mod] = get(idx_of_layer, layer_of(rel), nothing)
    end
    errs = String[]
    for (rel, mod, deps) in entries
        rel in exempt_files && continue         # transitional per-file exemption
        my_idx = get(idx_of_layer, layer_of(rel), nothing)
        my_idx === nothing && continue          # importer exempt (non-LAYERS folder)
        for d in deps
            dep_idx = get(mod_layer, d, nothing)
            dep_idx === nothing && continue     # dep exempt (non-LAYERS)
            if dep_idx > my_idx
                push!(errs,
                    "$rel ($mod, layer \"$(layers[my_idx])\") imports ..$d " *
                    "which lives in higher layer \"$(layers[dep_idx])\"")
            end
        end
    end
    errs
end

# ── the actual assertions ──────────────────────────────────────────────────

@testset "kernel layered-architecture guard" begin
    reached, entries = walk_includes(TOP_FILE, KERNEL_SRC)

    @testset "every src file is included exactly once" begin
        @test length(reached) == length(unique(reached))
        on_disk = Set{String}()
        for (root, _, files) in walkdir(KERNEL_SRC), f in files
            endswith(f, ".jl") || continue
            rel = relpath(joinpath(root, f), KERNEL_SRC)
            push!(on_disk, rel)
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

    @testset "includes are a valid topological order" begin
        errs = topo_errors(entries)
        if !isempty(errs)
            println(stderr, "\nInclude-order violations in ProjecturedKernel.jl:")
            foreach(e -> println(stderr, "  ", e), errs)
        end
        @test isempty(errs)
    end

    @testset "declared layers respect the LAYERS index" begin
        errs = layer_errors(entries, LAYERS, LAYER_EXEMPT_FILES)
        if !isempty(errs)
            println(stderr, "\nLayer-index violations (LAYERS = $LAYERS):")
            foreach(e -> println(stderr, "  ", e), errs)
        end
        @test isempty(errs)
    end
end

# ── self-tests for the checkers ────────────────────────────────────────────

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
    @test occursin("no kernel file defines", topo_errors(dangling)[1])
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

    # An importer under a non-LAYERS folder is exempt.
    exempt_importer = [("document/B.jl", :B, Symbol[]),
                       ("common/A.jl",   :A, [:B])]
    @test isempty(layer_errors(exempt_importer, layers))

    # A dep pointing into a non-LAYERS folder is exempt.
    exempt_dep = [("common/B.jl", :B, Symbol[]),
                  ("cell/A.jl",   :A, [:B])]
    @test isempty(layer_errors(exempt_dep, layers))

    # A per-file exemption suppresses the upward-edge error for that importer.
    upward = [("document/B.jl", :B, Symbol[]),
              ("cell/A.jl",     :A, [:B])]
    @test length(layer_errors(upward, layers)) == 1
    @test isempty(layer_errors(upward, layers, Set(["cell/A.jl"])))
end

# ── per-layer runner ───────────────────────────────────────────────────────

"""
Run per-layer test suites under `test/<layer>/runtests.jl`.

Filter with `Pkg.test(test_args=["cell","projection"])` — an empty filter runs
every declared layer whose folder exists. Each `test/<layer>/runtests.jl` is
also directly runnable via `julia --project=. test/<layer>/runtests.jl`.
"""
function run_layer_tests(layers, filter)
    for layer in layers
        isempty(filter) || (layer in filter) || continue
        dir = joinpath(@__DIR__, layer)
        runner = joinpath(dir, "runtests.jl")
        isfile(runner) || continue
        @testset "$layer" begin
            include(runner)
        end
    end
end

# `Pkg.test(test_args=[…])` forwards `ARGS` here; empty ARGS ⇒ run every layer.
run_layer_tests(LAYERS, ARGS)
