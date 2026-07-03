function test_copying_projection()
@testset "CopyingProjection CellVector" begin

# Identity mapping over CellVector using IdentityProjection
cv = CellVector(Cell[Cell(PrimitiveNumber(10)), Cell(PrimitiveNumber(20)), Cell(PrimitiveNumber(30))])
inner = IdentityProjection()
iomap = projection_print(CopyingProjection(), inner, cv, PrinterContext())

@test iomap.output isa CellVector
@test length(iomap.output) == 3
@test iomap.output[1] isa PrimitiveNumber
@test iomap.output[1].value == 10
@test iomap.output[2].value == 20
@test iomap.output[3].value == 30

end # @testset

@testset "CopyingProjection ListNode" begin

# Create a ListNode chain: 10 → 20 → 30
head = ListNode(PrimitiveNumber(10))
push!(head, PrimitiveNumber(20))
push!(head, PrimitiveNumber(30))

# Use IdentityProjection as inner recursion (identity mapping)
inner = IdentityProjection()
iomap = projection_print(CopyingProjection(), inner, head, PrinterContext())

@test iomap.output isa ListNode
# Head value is preserved
@test iomap.output.value isa PrimitiveNumber
@test iomap.output.value.value == 10

# Force next — lazily mapped
next_node = iomap.output.next
@test next_node !== nothing
@test next_node.value isa PrimitiveNumber
@test next_node.value.value == 20

# Force next.next
next2 = next_node.next
@test next2 !== nothing
@test next2.value.value == 30

# next.next.next should be nothing
@test next2.next === nothing

# Backward traversal: next_node.prev should be head
@test next_node.prev === iomap.output

end # @testset

@testset "CopyingProjection ListNode lazy" begin

# Create a lazy infinite-like chain (limited to 5 for testing)
counter = Ref(0)
function make_lazy_chain(n::Int)
    node = ListNode(PrimitiveNumber(1))
    counter[] += 1
    if n > 1
        set_function!(getfield(node, :next), () -> begin
            make_lazy_chain(n - 1)
        end)
    end
    node
end

head = make_lazy_chain(100)
counter[] = 0  # reset after head creation

inner = IdentityProjection()
iomap = projection_print(CopyingProjection(), inner, head, PrinterContext())

# Only head should be projected — no thunks forced yet
@test counter[] == 0

# Force first next
n1 = iomap.output.next
@test n1 !== nothing
# Forcing output.next forces input.next (1 thunk) and projects it
@test counter[] == 1

# Force second next
n2 = n1.next
@test n2 !== nothing
@test counter[] == 2

end # @testset

@testset "ListNode indexing" begin

head = ListNode(:a)
push!(head, :b)
push!(head, :c)
pushfirst!(head, :z)

# Forward indexing (1-based from head)
@test head[1] == :a
@test head[2] == :b
@test head[3] == :c

# Backward indexing (0 = head.prev, -1 = head.prev.prev)
@test head[0] == :z

# Bounds error
@test_throws BoundsError head[5]
@test_throws BoundsError head[-1]

end # @testset

@testset "CopyingProjection ListNode direct" begin

head = ListNode(PrimitiveNumber(42))
push!(head, PrimitiveNumber(99))

inner = IdentityProjection()
iomap = projection_print(CopyingProjection(), inner, head, PrinterContext())

@test iomap isa CopyingProjectionIoMap
@test iomap.output isa ListNode
@test iomap.output.value.value == 42
@test iomap.output.next.value.value == 99

end # @testset
end # test_copying_projection
