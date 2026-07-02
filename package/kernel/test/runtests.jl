"""
Kernel include-order guard rail (Phase 1 of plan/pending/kernel-cleanup.md).

`package/kernel/src/ProjecturedKernel.jl` is a hand-maintained topological sort:
each `include("…")` must appear *after* the files defining every `..XxxModule`
it imports. Julia enforces this only implicitly (an out-of-order include throws
`UndefVarError` deep inside precompilation); this test enforces it **statically,
without loading the package**, so a reordering regression is caught in ~1s with a
message naming the offending file and the module it references too early.

The check parses each file's AST (not a regex) so `import ..Foo` example text
inside docstrings is ignored — only real top-level `import`/`using` statements
count. The core `topo_errors` is a pure function over `(file, module, deps)`
triples, exercised below on a synthetic bad ordering so the guard is itself
guarded.
"""

using Test

const KERNEL_SRC = normpath(joinpath(@__DIR__, "..", "src"))
const TOP_FILE   = joinpath(KERNEL_SRC, "ProjecturedKernel.jl")
const DOT        = Symbol(".")

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

"Ordered list of relative include paths in `ProjecturedKernel.jl`."
function extract_includes(topfile)
    ast = parse_file(topfile)
    calls = collect_exprs(ast) do e
        e.head === :call && length(e.args) >= 2 &&
            e.args[1] === :include && e.args[2] isa AbstractString
    end
    String[c.args[2] for c in calls]
end

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

"Return `(module_name::Symbol, deps::Vector{Symbol})` for a kernel source file."
function module_and_deps(path)
    ast = parse_file(path)
    mods = collect_exprs(e -> e.head === :module, ast)
    length(mods) == 1 ||
        error("$path defines $(length(mods)) modules; expected exactly 1")
    m = mods[1]
    name = m.args[2]::Symbol
    body = m.args[3]
    deps = Symbol[]
    for stmt in body.args
        stmt isa Expr && stmt.head in (:import, :using) || continue
        for arg in stmt.args
            d = relative_module(arg)
            d === nothing || push!(deps, d)
        end
    end
    name, unique(deps)
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

# ── the actual assertions ──────────────────────────────────────────────────

@testset "kernel include order" begin
    includes = extract_includes(TOP_FILE)

    @testset "every src file is included exactly once" begin
        @test length(includes) == length(unique(includes))
        on_disk = Set{String}()
        for (root, _, files) in walkdir(KERNEL_SRC), f in files
            endswith(f, ".jl") || continue
            rel = relpath(joinpath(root, f), KERNEL_SRC)
            rel == "ProjecturedKernel.jl" && continue
            push!(on_disk, rel)
        end
        @test Set(includes) == on_disk
    end

    entries = map(includes) do rel
        name, deps = module_and_deps(joinpath(KERNEL_SRC, rel))
        (rel, name, deps)
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
    @test occursin("no kernel file defines", topo_errors(dangling)[1])
end
