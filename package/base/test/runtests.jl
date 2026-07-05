"""
Static layered-architecture guard for `ProjecturedBase`.

Uses the same discipline as `package/kernel/test/runtests.jl`: parse the
real `import ..Module` headers, walk the include tree, check that the
top-file include list is a topological order over the union of
own+fragment imports, that every on-disk `.jl` file is reached exactly
once, and that declared layers respect their index. Runs in ~1s without
loading the package.

`LAYERS` will grow as content lands here at P8/Q2 — starting empty at P7
since the package is a skeleton. The tests exercise the guard machinery
against the empty include list; per-layer runners will be added under
`test/<layer>/` as layers gain content.
"""

using Test

const BASE_SRC = normpath(joinpath(@__DIR__, "..", "src"))
const TOP_FILE = joinpath(BASE_SRC, "ProjecturedBase.jl")
const DOT      = Symbol(".")

const LAYERS = String[]                # populate at P8 with "document","projection"
const LAYER_EXEMPT_FILES = Set{String}()

# ── AST helpers (mirrors kernel/test/runtests.jl) ──────────────────────────

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

function relative_module(arg)
    path = (arg isa Expr && arg.head === :(:)) ? arg.args[1] : arg
    path isa Expr && path.head === :. || return nothing
    any(==(DOT), path.args) || return nothing
    for a in path.args
        a isa Symbol && a !== DOT && return a
    end
    nothing
end

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

function walk_includes(top_file, src_root)
    reached = String[]
    entries = Tuple{String, Symbol, Vector{Symbol}}[]

    function descend(file)
        rel = relpath(file, src_root)
        push!(reached, rel)
        ast = parse_file(file)
        mods = collect_exprs(e -> e.head === :module, ast)
        if length(mods) > 1
            error("$rel defines $(length(mods)) modules; expected 0 or 1")
        end
        body = length(mods) == 1 ? mods[1].args[3] : ast
        imports, includes = collect_edges(body)
        for inc in includes
            child = joinpath(dirname(file), inc)
            isfile(child) || error("$rel includes \"$inc\" but the file does not exist")
            child_imports = descend(child)
            append!(imports, child_imports)
        end
        if length(mods) == 1
            (nothing, mods[1].args[2]::Symbol, unique(imports))
        else
            unique(imports)
        end
    end

    push!(reached, relpath(top_file, src_root))
    top_ast = parse_file(top_file)
    top_mods = collect_exprs(e -> e.head === :module, top_ast)
    length(top_mods) == 1 ||
        error("$(relpath(top_file, src_root)) must define exactly 1 module (the top)")
    _, top_includes = collect_edges(top_mods[1].args[3])
    for inc in top_includes
        child = joinpath(dirname(top_file), inc)
        isfile(child) || error("top include \"$inc\" not found on disk")
        result = descend(child)
        result isa Tuple || error("$(relpath(child, src_root)) is a fragment — top-level includes must define a module")
        _, name, deps = result
        push!(entries, (relpath(child, src_root), name, deps))
    end
    reached, entries
end

function topo_errors(entries)
    all_mods = Set(m for (_, m, _) in entries)
    seen = Set{Symbol}()
    errs = String[]
    for (i, (label, mod, deps)) in enumerate(entries)
        for d in deps
            if d in seen
                continue
            elseif d in all_mods
                push!(errs, "[$i] $label ($mod) imports ..$d, which is included later")
            else
                push!(errs, "[$i] $label ($mod) imports ..$d, which no base file defines")
            end
        end
        push!(seen, mod)
    end
    errs
end

# ── the assertions ──────────────────────────────────────────────────────

@testset "base layered-architecture guard" begin
    reached, entries = walk_includes(TOP_FILE, BASE_SRC)

    @testset "every src file is included exactly once" begin
        @test length(reached) == length(unique(reached))
        on_disk = Set{String}()
        for (root, _, files) in walkdir(BASE_SRC), f in files
            endswith(f, ".jl") || continue
            push!(on_disk, relpath(joinpath(root, f), BASE_SRC))
        end
        @test Set(reached) == on_disk
    end

    @testset "each module is defined by exactly one file" begin
        names = [m for (_, m, _) in entries]
        @test length(names) == length(unique(names))
    end

    @testset "includes are a valid topological order" begin
        errs = topo_errors(entries)
        isempty(errs) || foreach(e -> println(stderr, "  ", e), errs)
        @test isempty(errs)
    end
end
