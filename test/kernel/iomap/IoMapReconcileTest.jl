"""
`IoMapModule` — the reconcilers that keep the IoMap of a child while its element
stays the same object at the same index. The elements are `Ref`s in a cell, so each
one is an object of its own, and the `make_iomap` of each test counts its calls.
"""

using Test
using ProjecturedKernel.CellModule: Cell
using ProjecturedKernel.IoMapModule

# The child list of the elements in `items`, and the count of the IoMaps it made.
function make_reconciled_children(items)
    made = Ref(0)
    children = reconcile_child_iomaps(() -> items[],
                                      (i, x) -> (made[] += 1; SimpleIoMap(nothing, x, i)))
    (children, made)
end

function test_iomap_reconcile()
@testset "IoMapReconcile" begin

    a, b, c, z = Ref(:a), Ref(:b), Ref(:c), Ref(:z)

    @testset "an append keeps each IoMap and makes one for the new slot" begin
        items = Cell(Any[a, b])
        children, made = make_reconciled_children(items)
        before = children[]
        @test made[] == 2
        @test get_iomap_input.(before) == [a, b]
        @test get_iomap_output.(before) == [1, 2]
        items[] = Any[a, b, c]
        after = children[]
        @test after[1] === before[1]
        @test after[2] === before[2]
        @test get_iomap_input(after[3]) === c
        @test made[] == 3
    end

    @testset "a delete or a front insert makes the later children again" begin
        items = Cell(Any[a, b, c])
        children, made = make_reconciled_children(items)
        before = children[]
        items[] = Any[b, c]
        deleted = children[]
        @test deleted[1] !== before[2]
        @test deleted[2] !== before[3]
        @test get_iomap_output.(deleted) == [1, 2]
        @test made[] == 5

        items[] = Any[z, b, c]
        inserted = children[]
        @test all(i -> inserted[i + 1] !== deleted[i], 1:2)
        @test get_iomap_input.(inserted) == [z, b, c]
        @test made[] == 8
    end

    @testset "an element that goes away leaves the cache" begin
        items = Cell(Any[a, b])
        children, made = make_reconciled_children(items)
        first_b = children[][2]
        items[] = Any[a]
        @test length(children[]) == 1
        # The slot of `b` comes back empty, so `b` gets a new IoMap.
        items[] = Any[a, b]
        @test children[][2] !== first_b
        @test made[] == 3
    end

    @testset "one object at two indexes gets two child IoMaps" begin
        items = Cell(Any[a, a])
        children, made = make_reconciled_children(items)
        both = children[]
        @test both[1] !== both[2]
        @test get_iomap_output.(both) == [1, 2]
        @test made[] == 2
    end

    @testset "a slot whose make_iomap answers nothing holds nothing" begin
        items = Cell(Any[a, b])
        children = reconcile_child_iomaps(() -> items[],
            (i, x) -> x === b ? nothing : SimpleIoMap(nothing, x, i))
        before = children[]
        @test before[1] isa SimpleIoMap
        @test before[2] === nothing
        items[] = Any[a, b, c]
        after = children[]
        @test after[1] === before[1]
        @test after[2] === nothing
        @test get_iomap_input(after[3]) === c
    end

    @testset "the single child keeps its IoMap while the value is the same object" begin
        slot = Cell(a)
        made = Ref(0)
        child = reconcile_child_iomap(
            () -> slot[], v -> (made[] += 1; SimpleIoMap(nothing, v, nothing)))
        first_iomap = child[]
        @test get_iomap_input(first_iomap) === a
        # A write of the same object computes the cell again and keeps the IoMap.
        slot[] = a
        @test child[] === first_iomap
        @test made[] == 1
        slot[] = b
        @test child[] !== first_iomap
        @test get_iomap_input(child[]) === b
        @test made[] == 2
    end

end
end # test_iomap_reconcile
