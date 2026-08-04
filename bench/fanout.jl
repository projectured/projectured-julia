# Dependency-edge fanout measurement for the immutable-style work.
#
# Walks a live example pipeline, forces every cell, and reports:
#   • a census of cell KINDS reached (Reactive / Immutable / Mutable),
#   • the `dependents` fanout distribution of the reactive cells (the vector that
#     the linear register/invalidate scans pay for),
#   • the top cells by fanout ATTRIBUTED to the struct+field that holds them —
#     so we can see whether the shared high-fanout cells are TextString spans or
#     projection style config (ObjectToSyntax.style, …).

"""
    walk_cells(root) -> (cells, owner)

Every `AbstractCell` reachable from `root`, forced, collected once, in discovery
order — plus `owner`, mapping each cell's `objectid` to the `(struct, field)` that
holds it (first owner wins). The traversal descends arrays, sets, tuples, dicts
and struct fields, and stops at scalars and functions.

Separate from [`fanout_report`](@ref) because the census is useful on its own: it
answers "what cells does this object graph actually contain, and who owns them".
"""
function walk_cells(root)
    seen  = Set{UInt64}()
    cells = AbstractCell[]
    owner = Dict{UInt64, Tuple{Symbol,Symbol}}()
    work  = Any[root]
    while !isempty(work)
        x = pop!(work)
        (x === nothing || x isa Bool || x isa Number || x isa AbstractString ||
         x isa Symbol || x isa Function || x isa DataType || x isa Module) && continue
        id = objectid(x); (id in seen) && continue; push!(seen, id)
        if x isa AbstractCell
            push!(cells, x)
            v = try; x[]; catch; nothing; end
            push!(work, v)
        elseif x isa AbstractArray || x isa AbstractSet || x isa Tuple
            for el in x; push!(work, el); end
        elseif x isa AbstractDict
            for (k, v) in x; push!(work, k); push!(work, v); end
        else
            T = typeof(x)
            for fn in fieldnames(T)
                isdefined(x, fn) || continue
                fv = getfield(x, fn)
                fv isa AbstractCell && get!(owner, objectid(fv), (nameof(T), fn))
                push!(work, fv)
            end
        end
    end
    return cells, owner
end

_kindname(c) = c isa ReactiveCell ? :reactive :
               c isa ImmutableCell ? :immutable :
               c isa MutableCell ? :mutable : :other

# `dependents` is `Union{Nothing, Vector{WeakRef}}`, allocated on demand — a cell
# nothing reads keeps it `nothing` rather than an empty vector, which is the whole
# point of the lazy field. Fanout zero.
_fanout(c::ReactiveCell) = (d = getfield(c, :dependents); d === nothing ? 0 : length(d))

"""
    fanout_report(name = "workbench"; io = stdout, top = 20) -> NamedTuple

Print the cell-kind census and reactive `dependents` fanout distribution for the
named example's printed pipeline, with the `top` highest-fanout cells attributed
to the `struct.field` that holds each. Returns the measurements, so several
examples can be compared in one session:

    a = fanout_report("workbench"); b = fanout_report("json")
    a.census[:reactive] / b.census[:reactive]
"""
function fanout_report(name = "workbench"; io::IO = stdout, top::Integer = 20)
    ex = getproperty(@__MODULE__, Symbol(name, "_example"))
    doc, proj = ex.make_document(), ex.make_projection()
    iomap = print_document(proj, doc)
    cells, owner = walk_cells(iomap)

    # census
    census = Dict(:reactive => 0, :immutable => 0, :mutable => 0, :other => 0)
    for c in cells; census[_kindname(c)] += 1; end

    rcells = ReactiveCell[c for c in cells if c isa ReactiveCell]
    ndeps  = [_fanout(c) for c in rcells]
    s = sort(ndeps); n = length(s); q(p) = s[clamp(ceil(Int, p*n), 1, n)]

    println(io, "\n", "="^78)
    println(io, "$(name)_example   —   cells reached: $(length(cells))")
    println(io, "  kinds: reactive=$(census[:reactive])  immutable=$(census[:immutable])  mutable=$(census[:mutable])")
    println(io, "  dependents fanout (reactive cells, n=$n):  sum=$(sum(ndeps))  mean=$(round(mean(ndeps);digits=3))",
            "  median=$(median(ndeps))  p99=$(q(0.99))  max=$(maximum(ndeps))")
    println(io, "  cells with fanout >16: $(count(>(16), ndeps))    >64: $(count(>(64), ndeps))")

    println(io, "  ── top $(top) reactive cells by fanout, attributed to owner ──")
    println(io, "    ", rpad("fanout",7), rpad("value",22), "owner (struct.field)")
    order = sortperm(ndeps; rev=true)[1:min(top, n)]
    for i in order
        c = rcells[i]
        vt = try; string(typeof(getfield(c,:valid) ? getfield(c,:value) : nothing)); catch; "?"; end
        own = get(owner, objectid(c), (Symbol("<value>"), Symbol("-")))
        println(io, "    ", rpad(ndeps[i],7), rpad(vt,22), "$(own[1]).$(own[2])")
    end
    println(io, "="^78)

    return (; name = String(name), cells = length(cells), census = census,
              fanout = ndeps, owner = owner)
end
