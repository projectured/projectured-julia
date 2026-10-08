"""
`CollectionModule` — the reactive collection documents. Covers the `CellVector`
container protocol and the lazy `ListNode` chain (thunks, `take_first`,
infinite lists). The seam method `child_reference_steps(::CellVector)` that
base registers onto the kernel's `OperationModule` generic is validated by the
kernel operation-layer test through the default fieldnames-walk.
"""

# A schema with typed list fields: the native layout holds a plain vector, and the
# cell layout holds the list of the field. A list of a schema holds its family.
@document [M, C] struct TypedListEntry
    label::String
end

@document [M, C] struct TypedListHolder
    names::Vector{String} = String[]
    entries::Vector{TypedListEntry} = TypedListEntry[]
end

# A field that names a kind that is not reactive keeps its plain vector in the cell
# layout, as a scratch buffer does.
@document [M, C] struct BufferHolder
    buffer::MutableCell{Vector{String}}
end

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
    set_cell_computation!(getfield(node, :next), next_thunk)
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

# ── The count of the links that exist ───────────────────────────────────────

counted = lazy_integers_from(1)
@test count_computed_nodes(counted) == 1
@test counted[5].value == 5                       # reads four links
@test count_computed_nodes(counted) == 5
# The count computes nothing: the `next` of the fifth link is still not run.
fifth = counted.next.next.next.next
@test !is_cell_up_to_date(getfield(fifth, :next))
@test count_computed_nodes(counted) == 5
# A link that holds its neighbour as a value counts too, in either direction:
# the fifth link counts itself and the one link back that it holds.
fifth.prev = counted.next.next.next
@test count_computed_nodes(fifth) == 2

# ── The primes around a number, both ways ───────────────────────────────────

# The primes that the tests expect, found by a test that shares no code with the
# example: no divisor from 2 to the number less one.
is_prime_by_all_divisors(n) = n >= 2 && all(d -> n % d != 0, 2:n-1)
around = make_primes_around(1000)
@test around.value.value == 1009
@test count_computed_nodes(around) == 1
@test around.next.value.value == 1013
@test around.prev.value.value == 997
# A link and the link back meet the same node.
@test around.next.prev === around
@test around.prev.next === around
@test count_computed_nodes(around) == 3
# Twenty links each way are the primes in order, and none is skipped.
forward, back = around, around
for _ in 1:20
    @test all(n -> !is_prime_by_all_divisors(n), forward.value.value+1:forward.next.value.value-1)
    @test all(n -> !is_prime_by_all_divisors(n), back.prev.value.value+1:back.value.value-1)
    forward, back = forward.next, back.prev
end
@test all(is_prime_by_all_divisors, [n.value.value for n in (forward, back)])
@test count_computed_nodes(around) == 41
# The chain ends at 2, whose `prev` is `nothing`.
low = make_primes_around(3)
@test low.value.value == 3
@test low.prev.value.value == 2
@test low.prev.prev === nothing
# A start far away costs the links that are read, and no prefix.
far = make_primes_around(10^12)
@test far.value.value == 1_000_000_000_039
@test far.prev.value.value == 999_999_999_989
@test count_computed_nodes(far) == 2

# ── Bidirectional lazy list (simple test) ───────────────────────────────────

# Note: Bidirectional lazy lists are not fully implemented/tested yet
# The make_lazy_bidirectional_document_example has issues with node chaining
# TODO: Add bidirectional tests once the implementation is fixed

@testset "a list is copied both ways from the node held, and its next is read" begin
    middle = ListNode(PrimitiveNumber(2))
    before = ListNode(PrimitiveNumber(1))
    set_cell_value!(getfield(before, :next), middle)
    set_cell_value!(getfield(middle, :prev), before)
    # The node after the middle one is built when it is read.
    set_cell_computation!(getfield(middle, :next), () -> ListNode(PrimitiveNumber(3)))
    copied = copy_document(middle)
    @test copied !== middle
    @test copied.value.value == 2 && copied.value !== middle.value
    @test copied.next.value.value == 3
    @test copied.next.prev === copied
    @test copied.prev.value.value == 1 && copied.prev !== before
    @test copied.prev.next === copied
    @test copied.next.next === nothing && copied.prev.prev === nothing
end

@testset "a copy of a list without an end ends, and copies a node when it is read" begin
    # Each `next` computes a new node when it is read, so the list has no end. A
    # read takes a millisecond, so a copy that walks the list does not end in the
    # bound below; `stop` then ends that walk at the next node it reads.
    stop = Threads.Atomic{Bool}(false)
    reads = Threads.Atomic{Int}(0)
    function make_endless_node(i)
        node = ListNode(PrimitiveNumber(i))
        set_cell_computation!(getfield(node, :next), () -> begin
            Threads.atomic_add!(reads, 1)
            sleep(0.001)
            stop[] ? nothing : make_endless_node(i + 1)
        end)
        node
    end
    head = make_endless_node(1)
    task = Threads.@spawn copy_document(head)
    finished = timedwait(() -> istaskdone(task), 5.0) === :ok
    finished || (stop[] = true)
    @test finished
    copied = fetch(task)
    @test reads[] == 0
    @test copied.value.value == 1 && copied.value !== head.value
    @test copied.next.next.value.value == 3
    @test copied.next.prev === copied
    @test copied.next.next.prev === copied.next
    @test reads[] == 2
    # A node of the copy, once read, does not follow a change of the original.
    head.next.value.value = 20
    @test copied.next.value.value == 2
end

@testset "a kinded copy of a list copies each node in the kind, and links it back" begin
    # Three nodes, held at the middle one. The node after the middle one is built
    # when `next` is read, and `reads` counts the reads.
    reads = Ref(0)
    function make_three_nodes()
        middle = ListNode(PrimitiveNumber(2))
        before = ListNode(PrimitiveNumber(1))
        set_cell_value!(getfield(before, :next), middle)
        set_cell_value!(getfield(middle, :prev), before)
        set_cell_computation!(getfield(middle, :next), () -> (reads[] += 1; ListNode(PrimitiveNumber(3))))
        middle
    end
    function test_links(copied, middle)
        @test copied.value.value == 2 && copied.value !== middle.value
        @test copied.next.value.value == 3 && copied.next.prev === copied
        @test copied.prev.value.value == 1 && copied.prev.next === copied
        @test copied.next.next === nothing && copied.prev.prev === nothing
    end

    @testset "a reactive copy copies a neighbour when it is read" begin
        middle = make_three_nodes()
        reads[] = 0
        copied = copy_document(ReactiveCell, middle)
        @test reads[] == 0
        @test getfield(copied, :next) isa ReactiveCell
        @test getfield(copied.value, :value) isa ReactiveCell
        test_links(copied, middle)
        @test reads[] == 1
    end

    @testset "a mutable copy copies every node" begin
        middle = make_three_nodes()
        copied = copy_document(MutableCell, middle)
        @test getfield(copied, :next) isa MutableCell
        @test getfield(copied.value, :value) isa MutableCell
        @test getfield(copied.next, :prev) isa MutableCell
        test_links(copied, middle)
    end

    @testset "an immutable copy copies a node with no neighbour, and refuses a chain" begin
        single = copy_document(ImmutableCell, ListNode(PrimitiveNumber(5)))
        @test getfield(single, :value) isa ImmutableCell
        @test single.value.value == 5 && single.next === nothing && single.prev === nothing
        @test_throws DocumentCopyException copy_document(ImmutableCell, make_three_nodes())
    end
end

@testset "a sync of a list shadow walks each way from the node held, and ends" begin
    # Three nodes, held at the middle one.
    function make_linked_nodes()
        before, middle, after = ListNode(PrimitiveNumber(1)), ListNode(PrimitiveNumber(2)), ListNode(PrimitiveNumber(3))
        set_cell_value!(getfield(before, :next), middle)
        set_cell_value!(getfield(middle, :prev), before)
        set_cell_value!(getfield(middle, :next), after)
        set_cell_value!(getfield(after, :prev), middle)
        (before, middle, after)
    end
    # The sync runs in a task, so a walk that does not end fails in five seconds.
    function sync_in_time(shadow, source)
        task = Threads.@spawn sync_document!(shadow, source)
        timedwait(() -> istaskdone(task), 5.0) === :ok || return nothing
        fetch(task)
    end

    @testset "each node of the shadow follows its source, both ways" begin
        for K in (ReactiveCell, MutableCell)
            before, middle, after = make_linked_nodes()
            shadow = copy_document(K, middle)
            shadow_before, shadow_after = shadow.prev, shadow.next
            before.value.value = 10; middle.value.value = 20; after.value.value = 30
            @test sync_in_time(shadow, middle) === shadow
            @test shadow.value.value == 20
            @test shadow.prev === shadow_before && shadow.prev.value.value == 10
            @test shadow.next === shadow_after && shadow.next.value.value == 30
            @test shadow.next.prev === shadow && shadow.prev.next === shadow
        end
    end

    @testset "a node that the source gained is copied, and one it lost is gone" begin
        for K in (ReactiveCell, MutableCell)
            before, middle, after = make_linked_nodes()
            shadow = copy_document(K, middle)
            shadow.prev; shadow.next
            push!(after, PrimitiveNumber(4))
            pushfirst!(before, PrimitiveNumber(0))
            @test sync_in_time(shadow, middle) === shadow
            @test shadow.next.next.value.value == 4 && shadow.next.next.prev === shadow.next
            @test shadow.prev.prev.value.value == 0 && shadow.prev.prev.next === shadow.prev
            middle.next = nothing
            @test sync_in_time(shadow, middle) === shadow
            @test shadow.next === nothing
        end
    end

    @testset "a shadow of a list without an end syncs the nodes that it holds" begin
        reads = Ref(0)
        function make_endless_node(i)
            node = ListNode(PrimitiveNumber(i))
            set_cell_computation!(getfield(node, :next), () -> (reads[] += 1; make_endless_node(i + 1)))
            node
        end
        head = make_endless_node(1)
        shadow = copy_document(ReactiveCell, head)
        @test shadow.next.next.value.value == 3
        @test reads[] == 2
        head.next.value.value = 20
        @test sync_in_time(shadow, head) === shadow
        @test shadow.next.value.value == 20
        @test reads[] == 2
        # A link that was not read copies its node when it is read, and no sooner.
        @test shadow.next.next.next.value.value == 4
    end

    @testset "a list in a document syncs through the walk of the document" begin
        before, middle, after = make_linked_nodes()
        source = CellVector([middle])
        shadow = copy_document(ReactiveCell, source)
        @test shadow[1].next.value.value == 3
        middle.value.value = 20
        @test sync_in_time(shadow, source) === shadow
        @test shadow[1].value.value == 20
    end
end

@testset "an index list builds a node when a walk reaches it, and stops at both ends" begin
    built = Int[]
    head = make_index_list(5, 3, i -> (push!(built, i); i * 10))
    @test head.value == 30
    @test built == [3]
    @test count_computed_nodes(head) == 1
    @test head.next.value == 40
    @test head.next.prev === head
    @test head.prev.prev.value == 10
    @test head.prev.prev.prev === nothing
    @test head.next.next.value == 50
    @test head.next.next.next === nothing
    @test sort(built) == [1, 2, 3, 4, 5]

    @testset "the index of a node counts from the head, both ways" begin
        @test find_list_index(head, head) == 1
        @test find_list_index(head, head.next.next) == 3
        @test find_list_index(head, head.prev.prev) == -1
        @test find_list_index(head, make_index_list(5, 3, identity)) === nothing
        @test find_list_index(CellVector(), head) === nothing
    end

    @testset "the head is clamped to the range" begin
        @test make_index_list(5, 9, identity).value == 5
        @test make_index_list(5, 0, identity).value == 1
    end

    @testset "a computed value follows its cell" begin
        factor = Cell(2)
        node = make_index_list(3, 1, i -> () -> i * factor[]; computed = true)
        @test node.next.value == 4
        factor[] = 3
        @test node.next.value == 6
    end
end

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

    @testset "a function is an element" begin
        # `CellVector(f)` used to call `f` and splat the result: a callback returning a
        # String became a vector of its characters, silently.
        callback() = "I am a callback"
        one = CellVector(callback)
        @test length(one) == 1
        @test one[1] === callback

        # every other way of putting one in agrees
        @test CellVector([callback])[1] === callback
        @test CellVector(1, 2, callback)[3] === callback   # 2-arg is (elements, selection)
        @test last(push!(CellVector([1]), callback)) === callback

        # deriving the element list is what the marker is for
        src = Cell(2)
        derived = CellVector(@computation [10i for i in 1:src[]])
        @test [x for x in derived] == [10, 20]
        src[] = 3
        @test [x for x in derived] == [10, 20, 30]   # re-derives on upstream change
        @test [x for x in CellVector(@computation [1, 2])] == [1, 2]
    end

    @testset "a list in a document copies in a kind by its own method" begin
        # The walk calls the four-argument form for a child. A list of the mutable
        # kind holds plain values, so a `push!` to the copy works.
        copied = copy_document(MutableCell, ListNode(CellVector([1, 2])))
        inner = copied.value
        @test !any(x -> x isa AbstractCell, getfield(inner, :elements)[])
        push!(inner, 3)
        @test collect(inner) == [1, 2, 3]
    end

    # A write of one element goes into the slot cell that is there, so the way
    # back of the write holds the old value and not that cell.
    @testset "the way back of an element overwrite puts back the old value" begin
        operation_module = ProjecturedKernel.OperationModule
        v = CellVector(["a", "b"])
        slot = get_cell_at(v, 2)
        editor = (document = nothing,)
        reference = Reference(RangeReferenceStep(1, 2))
        write = ReplaceReferencedValueOperation(v, reference, "z")
        inverse = operation_module.evaluate_invertible_operation!(editor, write)
        @test collect(v) == ["a", "z"]
        operation_module.evaluate_operation(editor, inverse)
        @test collect(v) == ["a", "b"]
        @test get_cell_at(v, 2) === slot
    end

    @testset "a kinded copy of a native layout holds the list of the field" begin
        native = TypedListHolder(; names = ["a", "b"], entries = [TypedListEntry("x")])
        @test getfield(native, :names) isa Vector{String}
        @test getfield(native, :entries) isa Vector{MTypedListEntry}
        for kind in (ReactiveCell, MutableCell, ImmutableCell)
            copied = copy_document(kind, native)
            @test getfield(copied, :names)[] isa CellVector{String}
            @test collect(copied.names) == ["a", "b"]
            @test getfield(copied, :entries)[] isa CellVector{ATypedListEntry}
            @test only(collect(copied.entries)) isa ACTypedListEntry
            @test only(collect(copied.entries)).label == "x"
        end
    end

    @testset "a native layout takes the list of a cell layout as a vector" begin
        shadow = copy_document(ReactiveCell, TypedListHolder(; names = ["a", "b"]))
        native = TypedListHolder(; names = shadow.names)
        @test getfield(native, :names) isa Vector{String}
        @test getfield(native, :names) == ["a", "b"]
        @test convert(Vector{String}, CellVector(Any["x"])) == ["x"]
    end

    @testset "a field that names a kind that is not reactive holds a plain vector" begin
        buffer = Vector{String}(undef, 2)
        shadow = ACBufferHolder(buffer, nothing)
        @test getfield(shadow, :buffer) isa MutableCell{Vector{String}}
        @test shadow.buffer === buffer
        shadow.buffer = ["a"]
        @test shadow.buffer isa Vector{String}
        @test shadow.buffer == ["a"]
    end

    @testset "a list finds an element by its index" begin
        list = CellVector(["a", "b", "b"])
        @test findfirst(==("b"), list) == 2
        @test findall(==("b"), list) == [2, 3]
        @test collect(keys(list)) == [1, 2, 3]
    end

end # @testset "CellVector protocol"
end # test_collection
