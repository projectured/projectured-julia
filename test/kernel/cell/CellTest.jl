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
c = ComputedCell(() -> a[] + b[])
@test !is_cell_up_to_date(c)
@test c[] == 3
@test is_cell_up_to_date(c)

# mutation invalidates dependents
a[] = 10
@test is_cell_up_to_date(a)
@test !is_cell_up_to_date(c)
@test c[] == 12

# deep chain
d = ComputedCell(() -> c[] * 2)
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
cond = ComputedCell(() -> flag[] ? x[] : y[])
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
    # `dependents` is allocated lazily — `nothing` until first read (no live readers).
    live(c) = (d = getfield(c, :dependents); d === nothing ? 0 : count(w -> w.value !== nothing, d))
    @test live(source) == 0

    # A throwaway "pipeline": computed cells that read `source` and are forced once.
    # They are kept in a vector while we assert the registration count, so nothing is
    # collected mid-build — otherwise the count is at the mercy of GC scheduling (the
    # edge containers are now allocated lazily, so a build allocates less and GC fires
    # at different points). A `WeakRef` to the first one lets us later ask whether it
    # was collected once every strong reference is dropped.
    cells = [(c = ComputedCell(() -> source[] + 1); c[]; c) for _ in 1:100]
    @test live(source) == 100                     # all 100 registered
    discarded = WeakRef(cells[1])
    empty!(cells); cells = nothing                # drop every strong reference to them

    # They are now unreachable and can never recompute, so nothing will ever detach
    # them. The only thing still pointing at them is `source.dependents` — weakly.
    GC.gc(true); GC.gc(true)
    @test discarded.value === nothing             # ...so the reader really was collected
    @test live(source) <= 1                       # nothing live remains behind it

    # The emptied slots are pruned by the next scan, which registration is doing anyway,
    # so dead `WeakRef`s never accumulate: no slot is left without a live reader in it.
    keep = ComputedCell(() -> source[] + 1)
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
    tc = ReactiveCell{Int}(Computed(() -> t[] + 1)) # computed: value starts undefined
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
    obs = ComputedCell(() -> m[] * 10)
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

@testset "a function is a value" begin
    f() = 42
    c = Cell(f)
    @test c[] === f                      # stored, not called
    @test c[]() == 42                    # still callable through the cell
    @test is_cell_up_to_date(c)          # a value cell, not an invalid computed one

    cc = ComputedCell(f)                 # the marker is what makes a cell compute
    @test cc[] == 42
    @test !is_cell_up_to_date(ComputedCell(f))

    @test ReactiveCell{Function}(f)[] === f
    @test ReactiveCell{Int}(Computed(f))[] == 42

    # copy_cell_as re-boxes through the constructor, so a function-valued cell used to
    # come back as a thunk — and a copied document would call its own callbacks.
    @test copy_cell_as(c, c[])[] === f

    w = Cell(1)                          # the write side agrees with construction
    w[] = f
    @test w[] === f
    w[] = Computed(f)
    @test w[] == 42

    # a computation belongs to the one kind that can run it
    @test_throws ArgumentError ImmutableCell(Computed(f))
    @test_throws ArgumentError MutableCell(Computed(f))
    @test ImmutableCell(f)[] === f       # but a plain callable is fine in any kind
    @test MutableCell(f)[] === f
end

@testset "has_dependent_cells" begin
    source = Cell(1)
    @test !has_dependent_cells(source)        # nothing read it inside a computation

    reader = ComputedCell(() -> source[] + 1)
    @test reader[] == 2                  # the read forms the downstream edge
    @test has_dependent_cells(source)
    @test !has_dependent_cells(reader)        # nothing reads the reader

    @test !has_dependent_cells(MutableCell(1))     # no downstream edges by kind
    @test !has_dependent_cells(ImmutableCell(1))

    # A swept reader no longer counts. The WeakRef is cleared by hand here,
    # because a test must not depend on when the collector runs.
    getfield(source, :dependents)[1].value = nothing
    @test !has_dependent_cells(source)
end

@testset "a MethodError in a chain of ten computed cells" begin
    runs = Ref(0)
    top = ComputedCell(() -> (runs[] += 1; throw(MethodError(identity, ()))))
    for _ in 2:10
        below = top
        top = ComputedCell(() -> below[])
    end
    # In the latest world, no thunk retries.
    @test_throws MethodError Base.invokelatest(getindex, top)
    @test runs[] == 1

    # In an older world, each level retries once in the latest world.
    world = Base.get_world_counter()
    @eval _get_cell_test_newer_value() = 42
    runs[] = 0
    @test_throws MethodError Base.invoke_in_world(world, getindex, top)
    @test runs[] == 11

    # A thunk that calls a method newer than the world of its reader gets its
    # value through the retry.
    newer = ComputedCell(() -> _get_cell_test_newer_value())
    @test Base.invoke_in_world(world, getindex, newer) == 42
end

end # @testset "Cell"
end # test_cell

# The method with one argument exists when the test starts, so the name is bound
# in every world. The test adds the method with no argument in a newer world.
_get_cell_test_newer_value(value::Int) = value
