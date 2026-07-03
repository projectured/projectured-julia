# Cell-kind benchmark on a large JSON document — companion to
# package/kernel/demo/CellKindDemo.jl (the Phase 2 review gate of
# plan/pending/cell-kind-documents.md).
#
# The real JSON domain is still today's `@document` output (mutable structs,
# untyped Cells, CellVector children), so the kinds are measured on a HAND-WRITTEN
# parametric mirror of the JSON documents (string/number/bool/entry/object/array,
# faithful declared field types, loose bounds per the Phase 2 finding), against
# two baselines:
#
#   * "legacy mirror" — the same topology in today's emission shape (mutable
#     struct + untyped `Cell` fields), isolating struct-shape effects; and
#   * "real JsonObject" — the actual JSON documents, i.e. the full today-stack
#     including `CellVector` (which adds one slot-Cell per collection element
#     that the mirrors do not have — collection kinds are Phase 4).
#
# All five variants build the SAME tree and print through structurally identical
# printer bodies; the printed strings are asserted equal.
#
# Run standalone (light path — kernel + domain, no native stack):
#
#     julia --project=. package/domain/demo/CellKindJsonBench.jl

using Projectured
import Projectured: AbstractCell, Cell, ReactiveCell, MutableCell, ImmutableCell, Document
import Projectured: get_performance_counters, reset_performance_counters!
using Test
using Printf

const NumT = Union{Real, Nothing}   # JsonNumber's declared value type

# ── Parametric mirror of the JSON documents (as `@document` will emit them) ──
# Loose bounds (`<: AbstractCell`): the Phase 2 finding — `AbstractCell{T}` is
# invariant, so strict bounds would reject ad-hoc untyped cells.

struct MirStr{C1<:AbstractCell, C2<:AbstractCell} <: Document
    value::C1
    selection::C2
end
struct MirNum{C1<:AbstractCell, C2<:AbstractCell} <: Document
    value::C1
    selection::C2
end
struct MirBool{C1<:AbstractCell, C2<:AbstractCell} <: Document
    value::C1
    selection::C2
end
struct MirEntry{C1<:AbstractCell, C2<:AbstractCell, C3<:AbstractCell, C4<:AbstractCell} <: Document
    key::C1
    value::C2
    collapsed::C3
    selection::C4
end
struct MirObj{C1<:AbstractCell, C2<:AbstractCell, C3<:AbstractCell} <: Document
    entries::C1
    collapsed::C2
    selection::C3
end
struct MirArr{C1<:AbstractCell, C2<:AbstractCell, C3<:AbstractCell} <: Document
    elements::C1
    collapsed::C2
    selection::C3
end

const Mir = Union{MirStr, MirNum, MirBool, MirEntry, MirObj, MirArr}
Base.getproperty(d::Mir, f::Symbol) = getfield(d, f)[]

# One factory per kind K ∈ {ReactiveCell, MutableCell, ImmutableCell}: cells carry
# the mirror of the real declared field types. Children live in ONE cell holding a
# plain Vector{Document} (per-element slot cells are the collection story, Phase 4).
# `::Type{K}` keeps K a *static* parameter so `K{String}` etc. are resolved at
# compile time — the future macro emits concrete cell types in the value ctors; a
# runtime `K` value would instead do a dynamic type-application per node and
# dominate the build measurement (it did: ~30 ms instead of ~9 ms).
mirror_factory(::Type{K}) where {K<:AbstractCell} = (
    str   = v -> MirStr(K{String}(v), K{Any}(nothing)),
    num   = v -> MirNum(K{NumT}(v), K{Any}(nothing)),
    bool  = v -> MirBool(K{Bool}(v), K{Any}(nothing)),
    entry = (k, v) -> MirEntry(K{String}(k), K{Document}(v), K{Bool}(false), K{Any}(nothing)),
    obj   = v -> MirObj(K{Vector{Document}}(v), K{Bool}(false), K{Any}(nothing)),
    arr   = v -> MirArr(K{Vector{Document}}(v), K{Bool}(false), K{Any}(nothing)),
)

# ── Legacy mirror: byte-for-byte today's `@document` emission shape ──────────

mutable struct LStr <: Document;   value::Cell; selection::Cell; end
mutable struct LNum <: Document;   value::Cell; selection::Cell; end
mutable struct LBool <: Document;  value::Cell; selection::Cell; end
mutable struct LEntry <: Document; key::Cell; value::Cell; collapsed::Cell; selection::Cell; end
mutable struct LObj <: Document;   entries::Cell; collapsed::Cell; selection::Cell; end
mutable struct LArr <: Document;   elements::Cell; collapsed::Cell; selection::Cell; end

const Leg = Union{LStr, LNum, LBool, LEntry, LObj, LArr}
Base.getproperty(d::Leg, f::Symbol) = getfield(d, f)[]

legacy_factory() = (
    str   = v -> LStr(Cell(v), Cell(nothing)),
    num   = v -> LNum(Cell(v), Cell(nothing)),
    bool  = v -> LBool(Cell(v), Cell(nothing)),
    entry = (k, v) -> LEntry(Cell(k), Cell(v), Cell(false), Cell(nothing)),
    obj   = v -> LObj(Cell(v), Cell(false), Cell(nothing)),
    arr   = v -> LArr(Cell(v), Cell(false), Cell(nothing)),
)

# ── The real JSON documents (today's full stack, CellVector included) ─────────

# Closures (not raw constructor objects): a document name is a UnionAll after the
# kind parameterization, and storing it as a NamedTuple value makes every factory
# call a dynamic dispatch — real code calls ctors statically, which is what a
# closure models.
real_factory() = (
    str   = v -> JsonString(v),
    num   = v -> JsonNumber(v),
    bool  = v -> JsonBool(v),
    entry = (k, v) -> JsonObjectEntry(k, v),
    obj   = v -> JsonObject(v),   # Rule C: wraps the vector per-element in Cells
    arr   = v -> JsonArray(v),
)

# ── One tree topology for every variant ───────────────────────────────────────

function build_value(f, depth, fanout, i)
    if depth == 0
        r = i % 3
        r == 0 ? f.str("string-value-$i") :
        r == 1 ? f.num(i * 1.5) :
                 f.bool(iseven(i))
    elseif i % 3 == 0
        f.arr(Document[build_value(f, 0, fanout, j) for j in 1:fanout])
    else
        f.obj(Document[f.entry("key$(j)", build_value(f, depth - 1, fanout, j)) for j in 1:fanout])
    end
end
build_doc(f, depth, fanout) =
    f.obj(Document[f.entry("key$(j)", build_value(f, depth - 1, fanout, j)) for j in 1:fanout])

# ── Structurally identical printers (JSON serialization) per family ──────────

function print_json(d)
    io = IOBuffer()
    _pj(io, d)
    String(take!(io))
end

_pj(io, d::MirStr)  = print(io, '"', d.value, '"')
_pj(io, d::MirNum)  = print(io, d.value)
_pj(io, d::MirBool) = print(io, d.value)
_pj(io, d::MirEntry) = (print(io, '"', d.key, "\": "); _pj(io, d.value))
function _pj(io, d::MirObj)
    print(io, '{')
    for (n, e) in enumerate(d.entries)
        n > 1 && print(io, ", ")
        _pj(io, e)
    end
    print(io, '}')
end
function _pj(io, d::MirArr)
    print(io, '[')
    for (n, e) in enumerate(d.elements)
        n > 1 && print(io, ", ")
        _pj(io, e)
    end
    print(io, ']')
end

_pj(io, d::LStr)  = print(io, '"', d.value, '"')
_pj(io, d::LNum)  = print(io, d.value)
_pj(io, d::LBool) = print(io, d.value)
_pj(io, d::LEntry) = (print(io, '"', d.key, "\": "); _pj(io, d.value))
function _pj(io, d::LObj)
    print(io, '{')
    for (n, e) in enumerate(d.entries)
        n > 1 && print(io, ", ")
        _pj(io, e)
    end
    print(io, '}')
end
function _pj(io, d::LArr)
    print(io, '[')
    for (n, e) in enumerate(d.elements)
        n > 1 && print(io, ", ")
        _pj(io, e)
    end
    print(io, ']')
end

_pj(io, d::JsonString) = print(io, '"', d.value, '"')
_pj(io, d::JsonNumber) = print(io, d.value)
_pj(io, d::JsonBool)   = print(io, d.value)
_pj(io, d::JsonObjectEntry) = (print(io, '"', d.key, "\": "); _pj(io, d.value))
function _pj(io, d::JsonObject)
    print(io, '{')
    cv = d.entries
    for n in 1:length(cv)
        n > 1 && print(io, ", ")
        _pj(io, cv[n])
    end
    print(io, '}')
end
function _pj(io, d::JsonArray)
    print(io, '[')
    cv = d.elements
    for n in 1:length(cv)
        n > 1 && print(io, ", ")
        _pj(io, cv[n])
    end
    print(io, ']')
end

# ── Read walk: count nodes + a small checksum, per family ────────────────────

_wk(d::Union{MirStr, LStr, JsonString})   = (1, length(d.value))
_wk(d::Union{MirNum, LNum, JsonNumber})   = (1, Int(2d.value))
_wk(d::Union{MirBool, LBool, JsonBool})   = (1, Int(d.value))
function _wk(d::Union{MirEntry, LEntry, JsonObjectEntry})
    n, s = _wk(d.value)
    (n + 1, s + length(d.key))
end
function _wk_children(elems)
    n, s = 1, 0
    for e in elems
        dn, ds = _wk(e)
        n += dn; s += ds
    end
    (n, s)
end
_wk(d::Union{MirObj, LObj}) = _wk_children(d.entries)
_wk(d::Union{MirArr, LArr}) = _wk_children(d.elements)
_wk(d::JsonObject) = _wk_children(d.entries)    # CellVector iterates its values
_wk(d::JsonArray)  = _wk_children(d.elements)

# ── Bench ─────────────────────────────────────────────────────────────────────

const DEPTH, FANOUT = 4, 16

bench(f; reps = 5) = (f(); minimum(@elapsed(f()) for _ in 1:reps))

function measure(name, factory)
    GC.gc()
    t_build = bench(() -> build_doc(factory, DEPTH, FANOUT); reps = 3)
    a_build = @allocated build_doc(factory, DEPTH, FANOUT)
    doc     = build_doc(factory, DEPTH, FANOUT)
    t_read  = bench(() -> _wk(doc))
    t_print = bench(() -> print_json(doc))
    @printf("| %-26s | %8.2f | %8.1f | %8.2f | %8.2f |\n",
            name, t_build * 1e3, a_build / 1e6, t_read * 1e3, t_print * 1e3)
    doc
end

r_fac = mirror_factory(ReactiveCell)
m_fac = mirror_factory(MutableCell)
i_fac = mirror_factory(ImmutableCell)

# identical output across all five variants (same topology, same printer semantics)
let a = print_json(build_doc(real_factory(), 2, 4)),
    b = print_json(build_doc(legacy_factory(), 2, 4)),
    c = print_json(build_doc(r_fac, 2, 4)),
    d = print_json(build_doc(m_fac, 2, 4)),
    e = print_json(build_doc(i_fac, 2, 4))
    @test a == b == c == d == e
end

nodes, _ = _wk(build_doc(r_fac, DEPTH, FANOUT))
chars = length(print_json(build_doc(r_fac, DEPTH, FANOUT)))
println()
println("JSON tree: depth=$DEPTH fanout=$FANOUT → $nodes nodes, $(round(chars/1e6, digits=2)) MB printed")
println("(times in ms, min of 5 (build: 3); alloc in MB)")
println("| variant                    | build ms | build MB |  read ms | print ms |")
println("|----------------------------|----------|----------|----------|----------|")
rdoc = measure("real JsonObject (today)",  real_factory())
       measure("legacy mirror (mut+Cell)", legacy_factory())
rmir = measure("mirror ReactiveCell{T}",   r_fac)
mmir = measure("mirror MutableCell{T}",    m_fac)
       measure("mirror ImmutableCell{T}",  i_fac)

for (label, doc) in (("real JsonObject", rdoc), ("mirror R", rmir), ("mirror M", mmir))
    print_json(doc)   # warm
    reset_performance_counters!()
    print_json(doc)
    c = get_performance_counters()
    @printf("perf, one print pass, %-16s reads=%-8d computes=%-6d writes=%d\n",
            label * ":", c[:reads], c[:computes], c[:writes])
end

println()
println("CELL KIND JSON BENCH OK")
