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
@test is_cell_up_to_date(a)
@test is_cell_up_to_date(b)

# computed cell
c = Cell(() -> a[] + b[])
@test !is_cell_up_to_date(c)
@test c[] == 3
@test is_cell_up_to_date(c)

# mutation invalidates dependents
a[] = 10
@test is_cell_up_to_date(a)
@test !is_cell_up_to_date(c)
@test c[] == 12

# deep chain
d = Cell(() -> c[] * 2)
@test d[] == 24
b[] = 3
@test !is_cell_up_to_date(c)
@test !is_cell_up_to_date(d)
@test d[] == 26  # (10+3)*2

# switch computed → primitive
c[] = 99
@test c[] == 99
@test is_cell_up_to_date(c)
a[] = 50
@test is_cell_up_to_date(c)  # no longer depends on a
@test c[] == 99

# switch primitive → computed
set_cell_function!(c, () -> a[] * b[])
@test !is_cell_up_to_date(c)
@test c[] == 150  # 50*3

# re-tracking after set_cell_function!
a[] = 2
@test !is_cell_up_to_date(c)
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
@test is_cell_up_to_date(cond)  # cond should still be valid

# ── the dependency edge must not own the reader ─────────────────────────

@testset "an upstream cell does not retain a discarded downstream cell" begin
    # `dependents` exists to propagate INVALIDATION downstream. It must not keep the
    # downstream cell ALIVE — an upstream cell has no business owning its readers.
    #
    # It used to: `dependents` was a strong `Set{ReactiveCell}`, and the only place an
    # edge was ever removed is `recompute!`, which detaches a cell's own upstream links
    # before re-evaluating. A cell that is simply *discarded* never recomputes again, so
    # its edges were never removed and the upstream cell pinned it for ever. A document
    # thus held on to every pipeline it had ever been printed through (~690 MB per caret
    # walk of the `json` example), and to every span a printer shed while recomputing
    # (~100 kB per structural edit, for ever). See plan/pending/reactive-dependents-leak.md.
    #
    # The edge is now a `Vector{WeakRef}`, so a discarded reader is collectable.
    source = Cell(1)
    live(c) = count(w -> w.value !== nothing, getfield(c, :dependents))
    @test live(source) == 0

    # A throwaway "pipeline": computed cells that read `source`, are forced once, and are
    # then dropped. Built inside a function so that nothing roots them afterwards. A
    # `WeakRef` to the first one is handed back so we can ask whether it was collected —
    # a far sharper question than a count, which the *most recent* cell can spoil by
    # lingering in a stack slot after the function returns.
    function build_and_drop!(src)
        first_ref = nothing
        for i in 1:100
            c = Cell(() -> src[] + 1)
            c[]                       # forcing registers `c` as a dependent of `src`
            i == 1 && (first_ref = WeakRef(c))
        end
        first_ref::WeakRef
    end
    discarded = build_and_drop!(source)
    @test live(source) == 100                     # they registered

    # They are now unreachable and can never recompute, so nothing will ever detach them.
    # The only thing still pointing at them is `source.dependents` — weakly.
    GC.gc(true); GC.gc(true)
    @test discarded.value === nothing             # ...so the reader really was collected
    @test live(source) <= 1                       # (the last cell may linger in a stack slot)

    # The emptied slots are pruned by the next scan, which registration is doing anyway,
    # so dead `WeakRef`s never accumulate: no slot is left without a live reader in it.
    keep = Cell(() -> source[] + 1)
    keep[]
    @test length(getfield(source, :dependents)) == live(source)

    # And the weak edge still propagates invalidation to a reader that IS alive.
    source[] = 41
    @test keep[] == 42
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
    @test !is_cell_up_to_date(tc)
    @test (@inferred tc[]) == 3
    t[] = 10
    @test !is_cell_up_to_date(tc)
    @test tc[] == 11
    set_cell_function!(tc, () -> t[] * 2)      # typed set_cell_function! keeps the stale value slot
    @test tc[] == 20
end

@testset "MutableCell" begin
    m = MutableCell(1)
    @test m isa AbstractCell{Int}
    @test !(m isa Cell)
    @test (@inferred m[]) == 1
    m[] = 2
    @test m[] == 2
    @test is_cell_up_to_date(m)                   # trivially: nothing to recompute
    @test peek(m) == 2
    # no reactive bookkeeping: a thunk reading a MutableCell registers nothing,
    # so a later write does NOT invalidate the computed cell (by design)
    obs = Cell(() -> m[] * 10)
    @test obs[] == 20
    m[] = 5
    @test is_cell_up_to_date(obs)                 # unaware of the write
    @test obs[] == 20                        # stale until *reactive* invalidation
    w = MutableCell{Union{Nothing,Int}}(nothing)
    w[] = 3                                  # explicit wide type admits both
    @test w[] == 3
end

@testset "ImmutableCell" begin
    i = ImmutableCell("abc")
    @test i isa AbstractCell{String}
    @test (@inferred i[]) == "abc"
    @test is_cell_up_to_date(i)
    @test peek(i) == "abc"
    @test_throws MethodError i[] = "xyz"  # read-only is the contract
    @test isbitstype(typeof(ImmutableCell(1)).types[1]) # zero-cost wrapper: field inlines
end

end # @testset "Cell"
end # test_cell
