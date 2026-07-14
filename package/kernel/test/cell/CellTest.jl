"""
`CellModule` — the reactive engine and the two non-reactive cell kinds.

The cell layer is exercised entirely from ProjecturedKernel — no domain
vocabulary is in scope, which is exactly the pressure that keeps `cell/`
dependency-free.
"""

using Test
using ProjecturedKernel.CellModule

function test_cell()
@testset "Cell" begin

a = Cell(1)
b = Cell(2)
@test a[] == 1
@test b[] == 2
@test is_up_to_date(a)
@test is_up_to_date(b)

# computed cell
c = Cell(() -> a[] + b[])
@test !is_up_to_date(c)
@test c[] == 3
@test is_up_to_date(c)

# mutation invalidates dependents
a[] = 10
@test is_up_to_date(a)
@test !is_up_to_date(c)
@test c[] == 12

# deep chain
d = Cell(() -> c[] * 2)
@test d[] == 24
b[] = 3
@test !is_up_to_date(c)
@test !is_up_to_date(d)
@test d[] == 26  # (10+3)*2

# switch computed → primitive
c[] = 99
@test c[] == 99
@test is_up_to_date(c)
a[] = 50
@test is_up_to_date(c)  # no longer depends on a
@test c[] == 99

# switch primitive → computed
set_function!(c, () -> a[] * b[])
@test !is_up_to_date(c)
@test c[] == 150  # 50*3

# re-tracking after set_function!
a[] = 2
@test !is_up_to_date(c)
@test c[] == 6   # 2*3

# conditional dependency
flag = Cell(true)
x = Cell(10)
y = Cell(20)
cond = Cell(() -> flag[] ? x[] : y[])
@test cond[] == 10
flag[] = false
@test cond[] == 20
x[] = 999          # x is no longer a dep after last eval
@test is_up_to_date(cond)  # cond should still be valid

# ── the dependency edge must not own the reader ─────────────────────────

@testset "an upstream cell does not retain a discarded downstream cell" begin
    # `dependents` exists to propagate INVALIDATION downstream. It must not keep the
    # downstream cell ALIVE — an upstream cell has no business owning its readers.
    #
    # Today it does: `dependents` is a strong `Set{ReactiveCell}`, and the only place
    # an edge is ever removed is `recompute!`, which detaches a cell's own upstream
    # links before re-evaluating. A cell that is simply *discarded* never recomputes
    # again, so its edges are never removed and the upstream cell pins it for ever.
    #
    # That is a real leak, not a theoretical one, and it is not confined to tests.
    # Measured on the `json` example:
    #
    #   - a **structural edit** (insert a node, remove it again) leaves ~3.4 dead cells
    #     pinned and ~100 kB of live memory behind — every edit, for ever. The live
    #     pipeline's own cell count does not move; what grows is the number of dead cells
    #     hanging off it.
    #   - a **re-print** leaks the whole pipeline: `print_document` builds a fresh one and
    #     each of its cells registers itself in the `dependents` of every document cell it
    #     reads. One caret walk (which re-prints per keystroke) retains 36_317 edges and
    #     ~690 MB of live, post-GC memory, linearly per walk.
    #
    # Moving the *selection* through a live pipeline is flat — but only because the
    # printers go to deliberate lengths to reuse cells across a selection change
    # (`_DecoCache`, span stability, IoMap identity). That is an optimization, not a
    # property: every change it does not cover leaks.
    source = Cell(1)
    before = length(getfield(source, :dependents))

    # A throwaway "pipeline": computed cells that read `source`, are forced once, and
    # are then dropped. Built inside a function so that nothing roots them afterwards.
    function build_and_drop!(src)
        for _ in 1:100
            c = Cell(() -> src[] + 1)
            c[]                       # forcing registers `c` in `src.dependents`
        end
        nothing
    end
    build_and_drop!(source)
    @test length(getfield(source, :dependents)) == before + 100   # they registered

    # They are now unreachable and can never recompute, so nothing will ever detach
    # them. The only thing still pointing at them is `source.dependents` itself.
    GC.gc(true); GC.gc(true)

    # @broken: `dependents` strongly owns its readers, so a discarded pipeline is pinned
    # by the document for ever; the edge needs to be weak. See plan/pending/reactive-dependents-leak.md
    @test_broken length(getfield(source, :dependents)) == before
end

# ── cell kinds ──────────────────────────────────────────────────────────

@testset "typed ReactiveCell" begin
    t = ReactiveCell{Int}(1)
    @test t isa ReactiveCell              # `Cell` is the concrete ReactiveCell{Any}
    @test Cell === ReactiveCell{Any}
    @test (@inferred t[]) == 1            # typed read is type-stable
    t[] = 2.0                             # converts to the field type
    @test t[] === 2
    @test_throws InexactError t[] = 2.5
    tc = ReactiveCell{Int}(() -> t[] + 1) # computed: value starts undefined
    @test !is_up_to_date(tc)
    @test (@inferred tc[]) == 3
    t[] = 10
    @test !is_up_to_date(tc)
    @test tc[] == 11
    set_function!(tc, () -> t[] * 2)      # typed set_function! keeps the stale value slot
    @test tc[] == 20
end

@testset "MutableCell" begin
    m = MutableCell(1)
    @test m isa AbstractCell{Int}
    @test !(m isa Cell)
    @test (@inferred m[]) == 1
    m[] = 2
    @test m[] == 2
    @test is_up_to_date(m)                   # trivially: nothing to recompute
    @test peek(m) == 2
    # no reactive bookkeeping: a thunk reading a MutableCell registers nothing,
    # so a later write does NOT invalidate the computed cell (by design)
    obs = Cell(() -> m[] * 10)
    @test obs[] == 20
    m[] = 5
    @test is_up_to_date(obs)                 # unaware of the write
    @test obs[] == 20                        # stale until *reactive* invalidation
    w = MutableCell{Union{Nothing,Int}}(nothing)
    w[] = 3                                  # explicit wide type admits both
    @test w[] == 3
end

@testset "ImmutableCell" begin
    i = ImmutableCell("abc")
    @test i isa AbstractCell{String}
    @test (@inferred i[]) == "abc"
    @test is_up_to_date(i)
    @test peek(i) == "abc"
    @test_throws MethodError i[] = "xyz"  # read-only is the contract
    @test isbitstype(typeof(ImmutableCell(1)).types[1]) # zero-cost wrapper: field inlines
end

end # @testset "Cell"
end # test_cell
