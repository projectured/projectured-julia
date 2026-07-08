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
#    index ≤ the importer's (non-layers folders are exempt during transition).
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
Return the direct relative-module imports and the ordered list of `include(...)`
paths appearing at the top level of `body_expr`. Statements are considered
top-level within the passed expression: a module body (`:block`) or a bare
fragment body (`Meta.parseall` yields `:toplevel`).
"""
function collect_edges(body_expr)
    imports = Symbol[]
    includes = String[]
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
  **module file** reached, in include order: `(rel_path, module_name,
  agg_deps)`, where `agg_deps` is the union of that module's own
  `import ..X`s and every fragment file it (transitively) includes.

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
    entries = Tuple{String, Symbol, Vector{Symbol}}[]

    # Descend into `file`. `in_module` says whether a module-file ancestor
    # encloses it; returns the relative imports to fold into that ancestor
    # (always empty for module files, which emit an entry instead).
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
        imports, includes = collect_edges(body)
        if length(mods) == 0 && !in_module && !isempty(imports)
            error("$rel is a layer fragment with relative imports; only module files may import ..Xxx")
        end
        # Recurse into includes, aggregating fragment imports upward.
        for inc in includes
            child_path = joinpath(dirname(file), inc)
            isfile(child_path) || error("$rel includes \"$inc\" but the file does not exist")
            append!(imports, descend(child_path, in_module || length(mods) == 1))
        end
        if length(mods) == 1
            # Module file: emit an entry, but do not propagate deps upward.
            name = mods[1].args[2]::Symbol
            push!(entries, (rel, name, unique(imports)))
            Symbol[]
        else
            # Fragment: propagate imports to the enclosing module.
            unique(imports)
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

# ── the shared entry point ─────────────────────────────────────────────────

"""
    check_layering(src_root, top_file; name = "package",
                   layers = String[], exempt_files = Set{String}())

Run the full static layered-architecture guard for one main package inside
a `@testset`:

1. every on-disk `.jl` file under `src_root` is reached by `top_file`'s
   include tree exactly once,
2. every module is defined by exactly one file (top-level includes may be
   module files or per-layer fragments listing the layer's module files),
3. the module files' include order is a valid topological order over the real
   `import ..XxxModule` edges (module aliases to lower packages are exempt),
4. declared `layers` respect their index (skipped when `layers` is empty).
"""
function check_layering(src_root, top_file; name = "package",
                        layers = String[], exempt_files = Set{String}())
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
    end
end

# ── self-tests for the checkers ────────────────────────────────────────────

"""
    test_layering_checkers()

Self-tests for `topo_errors` / `layer_errors` on synthetic entry lists, and
for the `walk_includes` walker on a synthetic package tree.
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
            write(joinpath(root, "document/B.jl"), "module B\nimport ..A\ninclude(\"BFragment.jl\")\nend\n")
            write(joinpath(root, "document/BFragment.jl"), "import ..A\nusing ..C\n")
            write(joinpath(root, "document/C.jl"), "module C\nend\n")

            reached, entries = walk_includes(joinpath(root, "Top.jl"), root)
            # Every file reached exactly once, layer fragment included.
            @test sort(reached) == sort(["Top.jl", "cell/A.jl",
                                         "document/DocumentLayer.jl", "document/B.jl",
                                         "document/BFragment.jl", "document/C.jl"])
            # One entry per module file, in include order; the fragment's
            # imports fold into its enclosing module's deps.
            @test [(m, sort(d)) for (_, m, d) in entries] ==
                  [(:A, Symbol[]), (:B, [:A, :C]), (:C, Symbol[])]
            # B imports ..C, which the layer fragment includes later.
            @test length(topo_errors(entries)) == 1

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
end
