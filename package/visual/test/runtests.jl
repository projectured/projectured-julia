"""
Static layered-architecture guard for `ProjecturedVisual`.

Mirrors the kernel / base / domain guards: fragment-aware include walker,
alias-name collector (so `..CellModule` etc. resolve to the ProjecturedKernel
alias declared at the top of `ProjecturedVisual.jl`), topo check.

`LAYERS` will grow as slices land: `["style"]` at Q1's first sub-commit,
extending to `["style","screen","graphics","layout","text","widget","syntax","backend"]`
by the end of Q1. Within-tier slice→slice edges (e.g. widget → layout) are
allowed provided the slice DAG is acyclic — the plan verifies this against
the target file inventory.
"""

using Test

const VISUAL_SRC = normpath(joinpath(@__DIR__, "..", "src"))
const TOP_FILE   = joinpath(VISUAL_SRC, "ProjecturedVisual.jl")
const DOT        = Symbol(".")

const LAYERS = String["style", "screen", "graphics", "layout", "text", "widget", "syntax", "backend"]
const LAYER_EXEMPT_FILES = Set{String}()

# ── AST helpers (mirror kernel/base) ───────────────────────────────────────

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
    length(top_mods) == 1 || error("top file must define exactly 1 module")
    _, top_includes = collect_edges(top_mods[1].args[3])
    for inc in top_includes
        child = joinpath(dirname(top_file), inc)
        isfile(child) || error("top include \"$inc\" not found on disk")
        result = descend(child)
        result isa Tuple || error("$(relpath(child, src_root)) is a fragment — top includes must be modules")
        _, name, deps = result
        push!(entries, (relpath(child, src_root), name, deps))
    end
    reached, entries
end

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

function topo_errors(entries, aliases = Set{Symbol}())
    all_mods = Set(m for (_, m, _) in entries)
    seen = Set{Symbol}()
    errs = String[]
    for (i, (label, mod, deps)) in enumerate(entries)
        for d in deps
            if d in seen
                continue
            elseif d in aliases
                continue
            elseif d in all_mods
                push!(errs, "[$i] $label ($mod) imports ..$d, which is included later")
            else
                push!(errs, "[$i] $label ($mod) imports ..$d, which no visual file defines")
            end
        end
        push!(seen, mod)
    end
    errs
end

# ── the assertions ──────────────────────────────────────────────────────

@testset "visual layered-architecture guard" begin
    reached, entries = walk_includes(TOP_FILE, VISUAL_SRC)

    @testset "every src file is included exactly once" begin
        @test length(reached) == length(unique(reached))
        on_disk = Set{String}()
        for (root, _, files) in walkdir(VISUAL_SRC), f in files
            endswith(f, ".jl") || continue
            push!(on_disk, relpath(joinpath(root, f), VISUAL_SRC))
        end
        @test Set(reached) == on_disk
    end

    @testset "each module is defined by exactly one file" begin
        names = [m for (_, m, _) in entries]
        @test length(names) == length(unique(names))
    end

    @testset "includes are a valid topological order" begin
        aliases = alias_names(TOP_FILE)
        errs = topo_errors(entries, aliases)
        isempty(errs) || foreach(e -> println(stderr, "  ", e), errs)
        @test isempty(errs)
    end
end
