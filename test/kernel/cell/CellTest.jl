"""
`CellModule` — the reactive engine and the two non-reactive cell kinds.

The cell layer is exercised entirely from ProjecturedKernel — no domain
vocabulary is in scope, which is exactly the pressure that keeps `cell/`
dependency-free.
"""

using Test
using ProjecturedKernel.CellModule

# The readers of `cell` that are still alive.
function _count_live_dependents(cell)
    dependents = getfield(cell, :dependents)
    dependents === nothing ? 0 : count(reference -> reference.value !== nothing, dependents)
end

# A hundred computed cells that read `source`, each forced once, and then dropped:
# the count of live readers while they are held, and a `WeakRef` to the first. The
# cells live only in this frame. A caller that made them itself could hold one in
# a GC root after its last use, which Julia 1.11 does in `test_cell`, and a test of
# the collector would then measure the frame and not the edge.
@noinline function _make_discarded_readers(source)
    cells = [(cell = Cell(@computation source[] + 1); cell[]; cell) for _ in 1:100]
    (_count_live_dependents(source), WeakRef(cells[1]))
end

function test_cell()
@testset "Cell" begin

a = Cell(1)
b = Cell(2)
@test a[] == 1
@test b[] == 2
@test is_cell_valid(a)
@test is_cell_valid(b)

# computed cell
c = Cell(@computation a[] + b[])
@test !is_cell_valid(c)
@test c[] == 3
@test is_cell_valid(c)

# mutation invalidates dependents
a[] = 10
@test is_cell_valid(a)
@test !is_cell_valid(c)
@test c[] == 12

# deep chain
d = Cell(@computation c[] * 2)
@test d[] == 24
b[] = 3
@test !is_cell_valid(c)
@test !is_cell_valid(d)
@test d[] == 26  # (10+3)*2

# switch computation → value
c[] = 99
@test c[] == 99
@test is_cell_valid(c)
a[] = 50
@test is_cell_valid(c)  # no longer depends on a
@test c[] == 99

# switch value → computation
set_cell_computation!(c, () -> a[] * b[])
@test !is_cell_valid(c)
@test c[] == 150  # 50*3

# re-tracking after set_cell_computation!
a[] = 2
@test !is_cell_valid(c)
@test c[] == 6   # 2*3

# conditional dependency
flag = Cell(true)
x = Cell(10)
y = Cell(20)
cond = Cell(@computation flag[] ? x[] : y[])
@test cond[] == 10
flag[] = false
@test cond[] == 20
x[] = 999          # x is no longer a dep after last eval
@test is_cell_valid(cond)  # cond should still be valid

# ── the dependency edge must not own the reader ─────────────────────────

@testset "an upstream cell does not retain a discarded downstream cell" begin
    # `dependents` carries invalidation down to the readers. It must not keep a
    # reader alive. A reader removes its edges only when it computes again or is
    # written, and a discarded cell never does either, so a strong edge would keep
    # every discarded reader for ever: about 690 MB for one caret walk of the `json`
    # example. The measurements are in plan/done/reactive-dependents-leak.md.
    source = Cell(1)
    # `dependents` is allocated lazily — `nothing` until first read (no live readers).
    live = _count_live_dependents
    @test live(source) == 0

    # A throwaway "pipeline": computed cells that read `source` and are forced once.
    # They are held while the registration count is read, so nothing is collected
    # mid-build — otherwise the count is at the mercy of GC scheduling. A `WeakRef`
    # to the first one lets us later ask whether it was collected once every strong
    # reference is dropped.
    registered, discarded = _make_discarded_readers(source)
    @test registered == 100                       # all 100 registered

    # They are now unreachable and can never recompute, so nothing will ever detach
    # them. The only thing still pointing at them is `source.dependents` — weakly.
    GC.gc(true); GC.gc(true)
    @test discarded.value === nothing             # ...so the reader really was collected
    @test live(source) <= 1                       # nothing live remains behind it

    # The emptied slots are pruned by the next scan, which registration is doing anyway,
    # so dead `WeakRef`s never accumulate: no slot is left without a live reader in it.
    keep = Cell(@computation source[] + 1)
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
    tc = ReactiveCell{Int}(@computation t[] + 1) # computed: value starts undefined
    @test !is_cell_valid(tc)
    @test (@inferred tc[]) == 3
    t[] = 10
    @test !is_cell_valid(tc)
    @test tc[] == 11
    set_cell_computation!(tc, () -> t[] * 2)   # typed: keeps the stale value slot
    @test tc[] == 20
end

@testset "a write that does not convert leaves a typed computed cell as it was" begin
    t = ReactiveCell{Int}(1)
    tc = ReactiveCell{Int}(@computation t[] + 1)
    @test tc[] == 2
    @test_throws InexactError tc[] = 2.5
    @test is_computed_cell(tc)
    t[] = 5
    @test !is_cell_valid(tc)          # the cell still reads `t`
    @test tc[] == 6

    # A cell that nothing read keeps its computation too.
    unread = ReactiveCell{Int}(@computation t[] * 3)
    @test_throws InexactError unread[] = 2.5
    @test is_computed_cell(unread)
    @test unread[] == 15
end

@testset "a new computed cell holds nothing until its first read" begin
    # The stored value is what persistence reads, so it must be defined.
    fresh = Cell(@computation 1)
    @test getfield(fresh, :value) === nothing
    @test fresh[] == 1
    wide = ReactiveCell{Union{Nothing,Int}}(@computation 2)
    @test getfield(wide, :value) === nothing
    @test wide[] == 2
end

@testset "a MutableCell rejects a written Computation" begin
    m = MutableCell{Any}(0)
    @test_throws ArgumentError m[] = @computation 1
    @test m[] === 0
    typed = MutableCell{Int}(0)
    @test_throws ArgumentError typed[] = Computation(() -> 1)
    @test typed[] === 0
end

@testset "MutableCell" begin
    m = MutableCell(1)
    @test m isa AbstractCell{Int}
    @test !(m isa Cell)
    @test (@inferred m[]) == 1
    m[] = 2
    @test m[] == 2
    @test is_cell_valid(m)                   # trivially: nothing to recompute
    @test peek(m) == 2
    # no reactive bookkeeping: a computation reading a MutableCell registers nothing,
    # so a later write does NOT invalidate the computed cell (by design)
    obs = Cell(@computation m[] * 10)
    @test obs[] == 20
    m[] = 5
    @test is_cell_valid(obs)                 # unaware of the write
    @test obs[] == 20                        # stale until *reactive* invalidation
    w = MutableCell{Union{Nothing,Int}}(nothing)
    w[] = 3                                  # explicit wide type admits both
    @test w[] == 3
end

@testset "ImmutableCell" begin
    i = ImmutableCell("abc")
    @test i isa AbstractCell{String}
    @test (@inferred i[]) == "abc"
    @test is_cell_valid(i)
    @test peek(i) == "abc"
    @test_throws MethodError i[] = "xyz"  # read-only is the contract
    @test isbitstype(ImmutableCell{Int})  # zero-cost wrapper: the field inlines
end

@testset "get_cell_computation answers the computation, and a caller can wrap it" begin
    f = () -> 1
    @test get_cell_computation(Cell(Computation(f))) === f
    @test get_cell_computation(Cell(1)) === nothing
    @test get_cell_computation(MutableCell(1)) === nothing
    @test get_cell_computation(UntrackedCell{Int}(@computation 1)) === nothing
    c = Cell(@computation 2)
    inner = get_cell_computation(c)
    set_cell_computation!(c, () -> inner() + 1)
    @test c[] == 3
end

@testset "a new computation makes a reader that is valid invalid" begin
    s = Cell(1)
    r = Cell(@computation s[] + 1)
    @test r[] == 2
    @test set_cell_computation!(s, () -> 10) === s
    @test getfield(s, :value) === nothing
    @test !is_cell_valid(r)
    @test r[] == 11
    s[] = @computation 20
    @test !is_cell_valid(r)
    @test r[] == 21
end

@testset "a Computation shows its function, and the stored kinds refuse it" begin
    @test repr(Computation(identity)) == "Computation(identity)"
    @test_throws ArgumentError MutableCell{Int}(Computation(identity))
    @test_throws ArgumentError ImmutableCell{Int}(Computation(identity))
end

@testset "run_without_cell_tracking inside a computation records no reader" begin
    a = Cell(1)
    r = Cell(@computation run_without_cell_tracking(() -> a[]) + 1)
    @test r[] == 2
    @test !has_dependent_cells(a)
end

@testset "a write of the same plain data makes no reader invalid" begin
    x = Cell(1)
    y = Cell(@computation x[] + 1)
    @test y[] == 2
    x[] = 1
    @test is_cell_valid(y)
    for (old, same) in (("text", String(['t', 'e', 'x', 't'])), (:name, :name),
                        (nothing, nothing), ((1, 2.5), (1, 2.5)))
        source = Cell(old)
        reader = Cell(@computation source[])
        reader[]
        source[] = same
        @test is_cell_valid(reader)
    end
    # The check sees the value after the conversion to the value type.
    typed = ReactiveCell{Float64}(1.0)
    typed_reader = Cell(@computation typed[] + 1)
    typed_reader[]
    typed[] = 1
    @test is_cell_valid(typed_reader)
    # A value that is equal and not identical is a change.
    z = Cell(1)
    w = Cell(@computation z[] * 2)
    w[]
    z[] = 1.0
    @test !is_cell_valid(w)
    @test w[] == 2.0
end

@testset "a write of the same mutable value makes the readers invalid" begin
    rows = Cell([1, 2])
    total = Cell(@computation sum(rows[]))
    @test total[] == 3
    push!(peek(rows), 3)
    rows[] = peek(rows)
    @test !is_cell_valid(total)
    @test total[] == 6
end

@testset "a write of a value into a computed cell makes the readers invalid" begin
    x = Cell(@computation 1)
    y = Cell(@computation x[] + 1)
    @test y[] == 2
    x[] = 1                       # the same value, but the computation ends
    @test !is_computed_cell(x)
    @test !is_cell_valid(y)
end

@testset "invalidate_cell! makes the readers compute again" begin
    rows = Cell([1, 2])
    total = Cell(@computation sum(rows[]))
    doubled = Cell(@computation 2 * total[])
    @test doubled[] == 6
    push!(peek(rows), 3)
    @test invalidate_cell!(rows) === nothing
    @test is_cell_valid(rows)                 # a value cell keeps its value
    @test !is_cell_valid(total)
    @test !is_cell_valid(doubled)
    @test doubled[] == 12
    # A computed cell becomes invalid too, and computes again at its next read.
    runs = Ref(0)
    counted = Cell(@computation (runs[] += 1; length(peek(rows))))
    reader = Cell(@computation counted[] + 1)
    @test reader[] == 4
    invalidate_cell!(counted)
    @test !is_cell_valid(counted)
    @test !is_cell_valid(reader)
    @test reader[] == 4
    @test runs[] == 2
    # The kinds that record no reader do nothing.
    @test invalidate_cell!(MutableCell(1)) === nothing
    @test invalidate_cell!(ImmutableCell(1)) === nothing
    @test invalidate_cell!(UntrackedCell{Int}(@computation 1)) === nothing
end

@testset "a computation that gives the plain data that it had leaves its readers" begin
    runs = Ref(0)
    number = Cell(1)
    is_odd = Cell(@computation isodd(number[]))
    reader = Cell(@computation (runs[] += 1; is_odd[] ? "odd" : "even"))
    @test reader[] == "odd" && runs[] == 1
    number[] = 3
    @test !is_cell_valid(reader)              # maybe invalid until a read checks it
    @test reader[] == "odd" && runs[] == 1
    @test is_cell_valid(reader)
    number[] = 4
    @test reader[] == "even" && runs[] == 2
end

@testset "a value that is not plain data is new at each computation" begin
    runs = Ref(0)
    source = Cell(1)
    flags = Cell(@computation [source[] > 0])
    reader = Cell(@computation (runs[] += 1; flags[][1]))
    @test reader[] && runs[] == 1
    source[] = 2
    @test reader[] && runs[] == 2
end

@testset "a check does not compute a dependency that the new run does not read" begin
    flag = Cell(true)
    source = Cell(1)
    computed = Ref(0)
    gate = Cell(@computation flag[])
    doubled = Cell(@computation (computed[] += 1; source[] * 2))
    other = Cell(0)
    reader = Cell(@computation gate[] ? doubled[] : other[])
    @test reader[] == 2 && computed[] == 1
    flag[] = false
    source[] = 5
    @test reader[] == 0
    @test computed[] == 1
end

@testset "an exception in a check reaches the computation of the reader" begin
    source = Cell(1)
    risky = Cell(@computation source[] > 1 ? error("too big") : source[])
    reader = Cell(@computation try risky[] catch; -1 end)
    @test reader[] == 1
    source[] = 2
    @test reader[] == -1
    # The value of `risky` is the one that it had before it failed, and it is new
    # to the reader, which caught the exception.
    source[] = 1
    @test reader[] == 1
end

@testset "a cycle through a check throws CellCycleException" begin
    start = Cell(1)
    middle = Cell(@computation start[] + 1)
    tail = Cell(@computation middle[] + 1)
    @test tail[] == 3
    start[] = @computation tail[] + 1
    @test_throws CellCycleException tail[]
end

@testset "a write of the same value into a computed cell reaches the readers" begin
    runs = Ref(0)
    source = Cell(1)
    doubled = Cell(@computation source[] * 2)
    reader = Cell(@computation (runs[] += 1; doubled[] + 1))
    @test reader[] == 3 && runs[] == 1
    doubled[] = 2
    @test reader[] == 3 && runs[] == 2
end

@testset "invalidate_cell! makes the cells below compute when a value changes" begin
    values = Cell([1])
    total = Cell(@computation sum(values[]))
    reader = Cell(@computation total[] * 10)
    @test reader[] == 10
    push!(values[], 2)
    invalidate_cell!(values)
    @test reader[] == 30
end

@testset "a run keeps one edge for each cell it read, in the order of the first read" begin
    a, b, c = Cell(1), Cell(2), Cell(3)
    short = Cell(@computation a[] + b[] + a[] + c[] + b[])
    @test short[] == 9
    @test getfield(short, :dependencies) == [a, b, c]
    sources = [Cell(k) for k in 1:40]
    long = Cell(@computation sum(sources[k][] + sources[1][] for k in 1:40))
    @test long[] == sum(1:40) + 40
    @test getfield(long, :dependencies) == sources
    sources[40][] = 41
    @test long[] == sum(1:40) + 41
end

@testset "a read on another task records no reader" begin
    t = Cell(1)
    s = Cell(@computation fetch(Threads.@spawn t[]))
    @test s[] == 1
    @test !has_dependent_cells(t)
end

@testset "get_cell_value_type" begin
    @test get_cell_value_type(ImmutableCell{Int}(1)) === Int
    @test get_cell_value_type(MutableCell{String}("a")) === String
    @test get_cell_value_type(ReactiveCell{Float64}(1.0)) === Float64
    @test get_cell_value_type(Cell(1)) === Any
    # The answer comes from the type, so a computed cell does not compute.
    computed = Cell(@computation error("computed"))
    @test get_cell_value_type(computed) === Any
    @test !is_cell_valid(computed)
end

@testset "a function is a value" begin
    f() = 42
    c = Cell(f)
    @test c[] === f                      # stored, not called
    @test c[]() == 42                    # still callable through the cell
    @test is_cell_valid(c)          # a value cell, not an invalid computed one

    cc = Cell(Computation(f))              # the marker is what makes a cell compute
    @test cc[] == 42
    @test !is_cell_valid(Cell(Computation(f)))

    @test ReactiveCell{Function}(f)[] === f
    @test ReactiveCell{Int}(Computation(f))[] == 42

    # make_similar_cell makes the copy through the constructor, and the copy of a cell
    # that holds a function must hold the function, not compute with it.
    @test make_similar_cell(c, c[])[] === f

    w = Cell(1)                          # the write side agrees with construction
    w[] = f
    @test w[] === f
    w[] = Computation(f)
    @test w[] == 42

    # a computation belongs to the one kind that can run it
    @test_throws ArgumentError ImmutableCell(Computation(f))
    @test_throws ArgumentError MutableCell(Computation(f))
    @test ImmutableCell(f)[] === f       # but a plain callable is fine in any kind
    @test MutableCell(f)[] === f
end

@testset "has_dependent_cells" begin
    source = Cell(1)
    @test !has_dependent_cells(source)        # nothing read it inside a computation

    reader = Cell(@computation source[] + 1)
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

@testset "@computation and Computation" begin
    a = Cell(1)
    # The plain form, the parenthesized form in an argument list, and a block.
    plain = Cell(@computation a[] + 1)
    both = (@computation(a[] * 10), 7)
    block = Cell(@computation begin
        b = a[] + 1
        b * 2
    end)
    @test plain[] == 2
    @test Cell(both[1])[] == 10
    @test both[2] == 7
    @test block[] == 4
    a[] = 2
    @test (plain[], block[]) == (3, 6)

    # A typed cell, and a write.
    typed = ReactiveCell{Int}(@computation a[] * 3)
    @test (@inferred typed[]) == 6
    written = Cell(0)
    written[] = @computation a[] - 1
    @test written[] == 1
    @test is_computed_cell(written)

    # The macro makes the marker, and the marker of a named function runs it.
    @test (@computation 1) isa Computation
    doubled() = 2 * a[]
    @test Cell(Computation(doubled))[] == 4
    # `@computation f` computes the function as a value, and does not call it.
    @test Cell(@computation doubled)[] === doubled
end

@testset "show" begin
    @test repr(Cell(2)) == "Cell(value, 2)"
    @test repr(Cell(@computation 2)) == "Cell(computation, <invalid>)"
    # A typed cell is not a `Cell`, so it shows its type.
    @test repr(ReactiveCell{Int}(2)) == "ReactiveCell{$(Int)}(value, 2)"
    typed = ReactiveCell{Int}(@computation 3)
    typed[]
    @test repr(typed) == "ReactiveCell{$(Int)}(computation, 3)"
    @test repr(MutableCell(1)) == "MutableCell(1)"
    @test repr(ImmutableCell("a")) == "ImmutableCell(\"a\")"
end

@testset "unwrap_cell" begin
    source = Cell(3)
    @test unwrap_cell(source) == 3
    @test unwrap_cell(MutableCell(4)) == 4
    @test unwrap_cell(ImmutableCell(5)) == 5
    @test unwrap_cell(6) == 6                      # a plain value reads as itself
    @test unwrap_cell(nothing) === nothing
    # The read is an ordinary one, so a computation depends on the cell.
    reader = Cell(@computation unwrap_cell(source) + 1)
    @test reader[] == 4
    source[] = 10
    @test !is_cell_valid(reader)
    @test reader[] == 11
end

@testset "set_cell_value!" begin
    margin = Cell(5)
    width = Cell(@computation 2 * margin[])
    reader = Cell(@computation width[] + 1)
    @test reader[] == 11
    set_cell_value!(width, 80)
    @test !is_computed_cell(width)
    @test !is_cell_valid(reader)              # the write invalidates the reader
    @test reader[] == 81
    margin[] = 6                                   # the value does not follow `margin`
    @test is_cell_valid(width)
    @test width[] == 80
end

@testset "make_similar_cell keeps the kind and the value type" begin
    m = make_similar_cell(MutableCell{Union{Nothing,Int}}(1), 2)
    @test m isa MutableCell{Union{Nothing,Int}}
    @test m[] == 2
    i = make_similar_cell(ImmutableCell{Real}(1), 2.5)
    @test i isa ImmutableCell{Real}
    @test i[] == 2.5
    r = make_similar_cell(ReactiveCell{Int}(1), 3)
    @test r isa ReactiveCell{Int}
    @test r[] == 3
    # The copy is a new cell that holds the value, and it has no computation.
    computed = Cell(@computation 7)
    copied = make_similar_cell(computed, 8)
    @test copied !== computed
    @test !is_computed_cell(copied)
    @test copied[] == 8
end

@testset "is_computed_cell" begin
    @test !is_computed_cell(Cell(3))
    @test is_computed_cell(Cell(@computation 3))
    @test !is_computed_cell(MutableCell(3))
    @test !is_computed_cell(ImmutableCell(3))
end

@testset "peek inside a computation records no dependency" begin
    frames = Cell(1)
    title = Cell("a")
    drawn = Cell(@computation string(peek(frames), title[]))
    @test drawn[] == "1a"
    @test !has_dependent_cells(frames)
    frames[] = 2
    @test is_cell_valid(drawn)                # not a reader of `frames`
    @test drawn[] == "1a"
    title[] = "b"
    @test drawn[] == "2b"

    # A peek of an invalid computed cell computes it, and the reader of the peek
    # does not depend on it.
    inner = Cell(@computation frames[] + 100)
    outer = Cell(@computation peek(inner) + 1)
    @test outer[] == 103
    @test is_cell_valid(inner)
    @test !has_dependent_cells(inner)
    @test has_dependent_cells(frames)              # `inner` reads `frames`
end

@testset "a reader that caught a failed computation computes again after a write" begin
    a = Cell(0)
    b = Cell(@computation a[] == 0 ? error("zero") : 10 ÷ a[])
    c = Cell(@computation try b[] catch; -1 end)
    @test c[] == -1
    a[] = 2
    # The failed cell passes the walk of the write on to the reader that caught it.
    @test !is_cell_valid(c)
    @test c[] == 5
end

@testset "a computation that writes a cell that it made computes once" begin
    made = Ref{Any}(nothing)
    runs = Ref(0)
    c = Cell(@computation begin
        runs[] += 1
        items = Cell(Int[])
        items[] = vcat(items[], 1)       # reads the new cell, then writes it
        made[] = items
        length(items[])
    end)
    @test c[] == 1
    @test is_cell_valid(c)
    @test c[] == 1
    @test runs[] == 1
end

@testset "a cell that reads itself throws a CellCycleException" begin
    c = Cell(0)
    c[] = @computation c[] + 1
    @test_throws CellCycleException c[]
    @test !is_cell_valid(c)
    a = Cell(0)
    b = Cell(@computation a[] + 1)
    a[] = @computation b[] + 1
    exception = try a[] catch caught; caught end
    @test exception isa CellCycleException
    @test exception.cell === a
    @test sprint(showerror, exception) == "a Cell read itself while it computed"
    # A write that breaks the cycle reaches the readers of the cycle.
    a[] = 5
    @test b[] == 6
end

@testset "a cycle through run_without_cell_tracking or an UntrackedCell throws" begin
    a = Cell(0)
    b = Cell(@computation a[] + 1)
    a[] = @computation run_without_cell_tracking(() -> b[]) + 1
    @test_throws CellCycleException a[]
    p = Cell(0)
    u = UntrackedCell{Int}(@computation p[] + 1)
    p[] = @computation u[] + 1
    @test_throws CellCycleException p[]
    typed = ReactiveCell{Int}(0)
    typed[] = @computation typed[] + 1
    exception = try typed[] catch caught; caught end
    @test sprint(showerror, exception) == "a ReactiveCell{$(Int)} read itself while it computed"
end

@testset "a read of a computing cell from a task that its computation waits for is a cycle" begin
    c = Cell(0)
    runs = Ref(0)
    c[] = @computation (runs[] += 1; fetch(Threads.@spawn c[]) + 1)
    exception = try c[] catch caught; caught end
    @test exception isa TaskFailedException
    @test exception.task.result isa CellCycleException
    @test exception.task.result.cell === c
    @test runs[] == 1                     # the read on the other task ran no computation
    @test !is_cell_valid(c)
end

@testset "a typed cell keeps its value until the first read of a new computation" begin
    typed = ReactiveCell{Int}(5)
    set_cell_computation!(typed, () -> 6)
    @test getfield(typed, :value) == 5
    @test typed[] == 6
    optional = ReactiveCell{Union{Nothing,Int}}(5)
    set_cell_computation!(optional, () -> 6)
    @test getfield(optional, :value) === nothing   # a type that admits nothing clears it
    @test optional[] == 6
end

@testset "a write or a new computation during the computation of a cell stands" begin
    c = Cell(0)
    c[] = @computation (c[] = 5; 1)
    @test c[] == 5
    @test !is_computed_cell(c)
    d = Cell(0)
    d[] = @computation (set_cell_computation!(d, () -> 2); 1)
    d[]
    @test d[] == 2
end

@testset "a new computation of a failed cell runs at the next read" begin
    f = Cell(@computation error("x"))
    @test_throws ErrorException f[]
    set_cell_computation!(f, () -> 4)
    @test f[] == 4
end

@testset "the reactive cell has its docstring" begin
    @test Base.Docs.hasdoc(CellModule, :ReactiveCell)
end

@testset "a MethodError in a chain of ten computed cells" begin
    runs = Ref(0)
    top = Cell(@computation (runs[] += 1; throw(MethodError(identity, ()))))
    for _ in 2:10
        below = top
        top = Cell(@computation below[])
    end
    # In the latest world, no computation retries.
    @test_throws MethodError Base.invokelatest(getindex, top)
    @test runs[] == 1

    # In an older world, each level retries once in the latest world.
    world = Base.get_world_counter()
    @eval _get_cell_test_newer_value() = 42
    runs[] = 0
    @test_throws MethodError Base.invoke_in_world(world, getindex, top)
    @test runs[] == 11

    # A computation that calls a method newer than the world of its reader gets its
    # value through the retry.
    newer = Cell(@computation _get_cell_test_newer_value())
    @test Base.invoke_in_world(world, getindex, newer) == 42
end

end # @testset "Cell"
end # test_cell

# The method with one argument exists when the test starts, so the name is bound
# in every world. The test adds the method with no argument in a newer world.
_get_cell_test_newer_value(value::Int) = value
