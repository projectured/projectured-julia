"""
`CollectionModule` — the reactive collection documents. Covers the `CellVector`
container protocol and the lazy `ListNode` chain (thunks, `take_first`,
infinite lists). The seam method `child_reference_steps(::CellVector)` that
base registers onto the kernel's `OperationModule` generic is validated by the
kernel operation-layer test through the default fieldnames-walk.
"""

function test_collection()
@testset "ReactiveCollection" begin

# ── ListNode basics ───────────────────────────────────────────────────────

node1 = ListNode(PrimitiveNumber(10))
@test node1.value.value == 10
@test node1.next === nothing
@test node1.prev === nothing

# ── Lazy ListNode with thunks ────────────────────────────────────────────────

# Helper to create a lazy node with thunk for next direction
function lazy_node(value, next_thunk::Function)
    node = ListNode(value)
    set_cell_function!(getfield(node, :next), next_thunk)
    node
end

# Helper to force evaluation of next cell
function force_next(ln::ListNode)
    if ln.next isa Function
        ln.next = ln.next()
    end
    ln.next
end

# Create a lazy chain: 1 -> 2 -> 3 -> 4 -> 5
counter = Ref(1)
head = lazy_node(PrimitiveNumber(counter[]), function()
    counter[] += 1
    lazy_node(PrimitiveNumber(counter[]), function()
        counter[] += 1
        lazy_node(PrimitiveNumber(counter[]), function()
            counter[] += 1
            lazy_node(PrimitiveNumber(counter[]), function()
                counter[] += 1
                lazy_node(PrimitiveNumber(counter[]), () -> nothing)
            end)
        end)
    end)
end)

# Test traversal
current = head
@test current.value.value == 1
current = force_next(current)
@test current.value.value == 2
current = force_next(current)
@test current.value.value == 3
current = force_next(current)
@test current.value.value == 4
current = force_next(current)
@test current.value.value == 5

# ── take_first function ─────────────────────────────────────────────────

# Test take_first in :next direction
counter2 = Ref(1)
head2 = lazy_node(PrimitiveNumber(counter2[]), function()
    counter2[] += 1
    lazy_node(PrimitiveNumber(counter2[]), function()
        counter2[] += 1
        lazy_node(PrimitiveNumber(counter2[]), function()
            counter2[] += 1
            lazy_node(PrimitiveNumber(counter2[]), function()
                counter2[] += 1
                lazy_node(PrimitiveNumber(counter2[]), () -> nothing)
            end)
        end)
    end)
end)

result = take_first(head2, 3, :next)
@test length(result) == 3
@test result[1].value == 1
@test result[2].value == 2
@test result[3].value == 3

result5 = take_first(head2, 5, :next)
@test length(result5) == 5
@test result5[1].value == 1
@test result5[5].value == 5

# ── Infinite lazy integers (unidirectional) ───────────────────────────────

# Create infinite lazy integers starting from n
function lazy_integers_from(n)
    lazy_node(PrimitiveNumber(n), () -> lazy_integers_from(n + 1))
end

# Test infinite integers starting from 1
inf_ints = lazy_integers_from(1)
first_10 = take_first(inf_ints, 10, :next)
@test length(first_10) == 10
@test first_10[1].value == 1
@test first_10[2].value == 2
@test first_10[3].value == 3
@test first_10[4].value == 4
@test first_10[5].value == 5
@test first_10[6].value == 6
@test first_10[7].value == 7
@test first_10[8].value == 8
@test first_10[9].value == 9
@test first_10[10].value == 10

# Test infinite integers starting from 100
inf_ints_100 = lazy_integers_from(100)
first_5_from_100 = take_first(inf_ints_100, 5, :next)
@test length(first_5_from_100) == 5
@test first_5_from_100[1].value == 100
@test first_5_from_100[2].value == 101
@test first_5_from_100[3].value == 102
@test first_5_from_100[4].value == 103
@test first_5_from_100[5].value == 104

# ── Bidirectional lazy list (simple test) ───────────────────────────────────

# Note: Bidirectional lazy lists are not fully implemented/tested yet
# The make_lazy_bidirectional_document_example has issues with node chaining
# TODO: Add bidirectional tests once the implementation is fixed

end # @testset "ReactiveCollection"

@testset "CellVector protocol" begin

    @testset "CellVector constructs and iterates" begin
        v = CellVector([1, 2, 3])
        @test length(v) == 3
        @test v[1] == 1
        @test v[3] == 3
        @test collect(v) == [1, 2, 3]
    end

    @testset "CellVector push/pop mutates in place" begin
        v = CellVector(Any[])
        push!(v, 10)
        push!(v, 20)
        @test length(v) == 2
        @test v[2] == 20
        pop!(v)
        @test length(v) == 1
    end

end # @testset "CellVector protocol"
end # test_collection
