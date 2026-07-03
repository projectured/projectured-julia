# Cell-kind demo — the Phase 2 review gate of plan/pending/cell-kind-documents.md.
#
# A HAND-WRITTEN vertical slice of the kind-parameterized document design: one tiny
# document type written out exactly as the future `@document` macro will emit it
# (immutable parametric stem, one cell type-parameter per field, R/I/M aliases,
# bare-name ctor defaulting to the reactive kind), plus a kind-generic printer, a
# generic `rekind` walk, correctness tests, and a measurement table.
#
# Run standalone (light path, kernel only):
#
#     julia --project=. package/kernel/demo/CellKindDemo.jl
#
# Nothing includes this file; it exists to be reviewed and rerun.

using ProjecturedKernel
import ProjecturedKernel.CellModule: AbstractCell, Cell, ReactiveCell, MutableCell,
                                         ImmutableCell, set_function!, is_up_to_date
import ProjecturedKernel.DocumentApiModule: Document
import ProjecturedKernel.PerformanceCounterModule: get_performance_counters, reset_performance_counters!
using Test
using Printf

# ── The stem, as `@document struct DemoItem …` will emit it ──────────────────
#
#     @document struct DemoItem
#         label::String
#         count::Int = 0
#         child::Union{Nothing, Document} = nothing
#     end
#
# One immutable struct; the cell kind in the fields decides the behavior. The
# `C_i <: AbstractCell{T_i}` bounds keep the declared value types enforced for
# every kind. `selection` is on every document (the Document contract).

const ChildT = Union{Nothing, Document}

struct DemoItem{C1 <: AbstractCell{String},
                C2 <: AbstractCell{Int},
                C3 <: AbstractCell{ChildT},
                C4 <: AbstractCell} <: Document
    label::C1
    count::C2
    child::C3
    selection::C4
end

# Uniform kind-generic access: one getproperty/setproperty! for all kinds — kind
# dispatch happens in the cell. (The macro will emit the equivalent if-chain.)
Base.getproperty(d::DemoItem, f::Symbol) = getfield(d, f)[]
Base.setproperty!(d::DemoItem, f::Symbol, v) = (getfield(d, f)[] = v; v)

# The three uniform instantiations (macro-emitted aliases).
const RDemoItem = DemoItem{ReactiveCell{String},  ReactiveCell{Int},  ReactiveCell{ChildT},  ReactiveCell{Any}}
const IDemoItem = DemoItem{ImmutableCell{String}, ImmutableCell{Int}, ImmutableCell{ChildT}, ImmutableCell{Any}}
const MDemoItem = DemoItem{MutableCell{String},   MutableCell{Int},   MutableCell{ChildT},   MutableCell{Any}}

# FINDING (recorded in the plan): the untyped instantiation
# `DemoItem{ReactiveCell{Any}, …}` does NOT inhabit the bounded stem —
# `AbstractCell{Any}` is not `<: AbstractCell{String}` (invariance). So strict
# per-field bounds are incompatible with ad-hoc untyped cells (`Cell(x)`), which
# the projection machinery creates freely. The macro will therefore emit *loose*
# bounds (`C_i <: AbstractCell`) and enforce declared types via the value ctors
# instead; the strict bounds here stay as the demo of what strictness would mean.
# The measurement baseline below is a faithful copy of today's `@document`
# emission: a MUTABLE struct with untyped `Cell` fields.
mutable struct LegacyItem <: Document
    label::Cell
    count::Cell
    child::Cell
    selection::Cell
end
Base.getproperty(d::LegacyItem, f::Symbol) = getfield(d, f)[]
Base.setproperty!(d::LegacyItem, f::Symbol, v) = (getfield(d, f)[] = v; v)

# Value-accepting ctors (macro-emitted): the bare name builds the REACTIVE kind
# (backward compatibility); the aliases build their own kind. Julia's default
# 4-arg ctor (pass the cells directly) stays available — that is how ad-hoc
# mixed-kind nodes are constructed.
DemoItem(label::AbstractString, count::Integer = 0, child = nothing) =
    DemoItem(ReactiveCell{String}(label), ReactiveCell{Int}(count),
             ReactiveCell{ChildT}(child), ReactiveCell{Any}(nothing))
IDemoItem(label::AbstractString, count::Integer = 0, child = nothing) =
    DemoItem(ImmutableCell{String}(label), ImmutableCell{Int}(count),
             ImmutableCell{ChildT}(child), ImmutableCell{Any}(nothing))
MDemoItem(label::AbstractString, count::Integer = 0, child = nothing) =
    DemoItem(MutableCell{String}(label), MutableCell{Int}(count),
             MutableCell{ChildT}(child), MutableCell{Any}(nothing))
LegacyItem(label::AbstractString, count::Integer = 0, child = nothing) =
    LegacyItem(Cell(label), Cell(count), Cell(child), Cell(nothing))

# ── Kind trait + generic rekind (the future `cell_kind` / `rekind` core) ─────

_kind(::Type{<:ReactiveCell})  = ReactiveCell
_kind(::Type{<:MutableCell})   = MutableCell
_kind(::Type{<:ImmutableCell}) = ImmutableCell
cell_kind(d::DemoItem) = _kind(typeof(getfield(d, :label)))

_cell_T(::AbstractCell{T}) where {T} = T

"""Recursively rebuild `d` with every cell replaced by a `K` cell of the same
declared value type. This IS the generic fieldwise walk the real `rekind` will
use (over `Document` instead of `DemoItem`)."""
rekind(K, v) = v
rekind(K, d::DemoItem) =
    DemoItem((K{_cell_T(getfield(d, f))}(rekind(K, getfield(d, f)[]))
              for f in fieldnames(DemoItem))...)
snapshot(d) = rekind(ImmutableCell, d)
hydrate(d)  = rekind(ReactiveCell, d)

# ── A kind-generic "projection": one printer body serves all kinds ───────────

function print_demo(d)
    io = IOBuffer()
    _print_demo(io, d, 0)
    String(take!(io))
end
# Precomputed, depth-capped indents: naive `"  "^depth` would allocate O(n²)
# string data over a deep chain and swamp the cell-read cost being measured.
const _INDENTS = ["  "^k for k in 0:32]
function _print_demo(io, d, depth)
    print(io, _INDENTS[min(depth, 32) + 1], d.label, " = ", d.count, "\n")
    c = d.child
    c === nothing || _print_demo(io, c, depth + 1)
end

# Build a chain of `n` nodes: node1 → node2 → … → leaf.
function make_chain(make, n)
    node = make("leaf", n)
    for i in (n - 1):-1:1
        node = make("node$i", i, node)
    end
    node
end

# ── Correctness ───────────────────────────────────────────────────────────────

@testset "cell-kind demo" begin
    r = make_chain(DemoItem, 5)
    i = rekind(ImmutableCell, r)
    m = rekind(MutableCell, r)
    @test r isa RDemoItem && i isa IDemoItem && m isa MDemoItem
    @test cell_kind(r) === ReactiveCell && cell_kind(i) === ImmutableCell &&
          cell_kind(m) === MutableCell

    # one printer body, identical output across kinds
    @test print_demo(r) == print_demo(i) == print_demo(m)

    # R: write-through + reactive propagation into a render cell
    render = Cell(() -> print_demo(r))
    @test occursin("node1 = 1", render[])
    r.count = 42
    @test !is_up_to_date(render)
    @test occursin("node1 = 42", render[])

    # M: write-through works, but NO reactive propagation (by design)
    mrender = Cell(() -> print_demo(m))
    @test occursin("node1 = 1", mrender[])
    m.count = 99
    @test is_up_to_date(mrender)              # the render cell is unaware
    @test occursin("node1 = 99", print_demo(m))  # yet the value did change

    # I: writes refused; reads type-stable
    @test_throws MethodError i.count = 7
    @test (@inferred (d -> d.label)(i)) == "node1"
    @test (@inferred (d -> d.count)(i)) == 1

    # round-trip: I → R hydration is editable again and equal in content
    r2 = hydrate(i)
    @test r2 isa RDemoItem && print_demo(r2) == print_demo(i)
    r2.count = 8
    @test occursin("node1 = 8", print_demo(r2))

    # boundary cell: an R parent holds an I subtree as ONE value; swapping the
    # subtree (the only way to "change" it) invalidates the parent's render
    parent = DemoItem("parent", 0, snapshot(make_chain(DemoItem, 3)))
    prender = Cell(() -> print_demo(parent))
    @test occursin("leaf = 3", prender[])
    parent.child = IDemoItem("other", 7)
    @test !is_up_to_date(prender)
    @test occursin("other = 7", prender[])

    # ad-hoc mixed kind (expressible, not blessed): immutable content, reactive
    # selection — "selectable but not editable" (plan decision 11)
    mixed = DemoItem(ImmutableCell{String}("fixed"), ImmutableCell{Int}(1),
                     ImmutableCell{ChildT}(nothing), ReactiveCell{Any}(nothing))
    @test mixed.label == "fixed"
    @test_throws MethodError mixed.count = 2
    mixed.selection = :fake_path            # the one reactive field accepts writes
    @test mixed.selection === :fake_path
end

# ── Measurements ─────────────────────────────────────────────────────────────

const N = 10_000

_walk_sum(d) = begin                # a read-heavy pass: touch every node twice
    s = 0
    node = d
    while node !== nothing
        s += node.count
        node = node.child
    end
    s
end

bench(f; reps = 7) = (f(); minimum(@elapsed(f()) for _ in 1:reps))  # warm, then min

function measure(name, make)
    GC.gc()
    t_build = bench(() -> make_chain(make, N))
    a_build = @allocated make_chain(make, N)
    chain   = make_chain(make, N)
    t_read  = bench(() -> _walk_sum(chain))
    t_print = bench(() -> print_demo(chain))
    @printf("| %-24s | %8.3f | %8.1f | %8.3f | %8.3f |\n",
            name, t_build * 1e3, a_build / 1e6, t_read * 1e3, t_print * 1e3)
end

println()
println("Chain of $N nodes (times in ms, min of 7; alloc in MB):")
println("| kind                     | build ms | build MB |  read ms | print ms |")
println("|--------------------------|----------|----------|----------|----------|")
measure("today's Cell struct (base)", LegacyItem)
measure("ReactiveCell{T} (typed)",  DemoItem)
measure("MutableCell{T}",           MDemoItem)
measure("ImmutableCell{T}",         IDemoItem)

# Reactive traffic of one R print pass, from the engine's own counters.
rchain = make_chain(DemoItem, N)
print_demo(rchain)                   # warm
reset_performance_counters!()
print_demo(rchain)
c = get_performance_counters()
println()
println("perf counters for one reactive print pass over $N nodes: ",
        "reads=", c[:reads], " writes=", c[:writes],
        " computes=", c[:computes], " invalidations=", c[:invalidations])
mchain = rekind(MutableCell, rchain)
reset_performance_counters!()
print_demo(mchain)
c = get_performance_counters()
println("perf counters for the same pass on the M kind:          ",
        "reads=", c[:reads], " writes=", c[:writes],
        " computes=", c[:computes], " invalidations=", c[:invalidations])
println()
println("CELL KIND DEMO OK")
