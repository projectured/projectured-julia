# ── ListNode ──────────────────────────────────────────────────────────────
# The node you hold IS the head (middle of the list). `prev` and `next` are the
# two tails growing in opposite directions.

"""
    ListNode(value)

One link of a chain of values, which reaches in both directions.

Use it for a sequence that is read from the middle outward, and that may be
longer than anything a reader will look at: the rows of a file of results, a
log, a transcript. What is drawn is the part a viewport reaches, so a chain of a
million links costs what the screen shows.

# Example

    head = ListNode("the first row")
    tail = get_right_tail(head)

See also `get_left_tail` and `get_right_tail`, which walk it, `take_first`, and
`CellVector`, which holds every element at once.
"""
@document struct ListNode
    value::Any
    prev::Union{ListNode, Nothing}
    next::Union{ListNode, Nothing}
end

ListNode(value) =
    ListNode(Cell(value), Cell(nothing), Cell(nothing), Cell(nothing))

# A list is copied lazily, as `CopyingProjection` projects one. The node held is
# copied at once, and `prev` and `next` of each copy are cells that copy the
# neighbour when they are read, and link it back. A list can have no end in either
# direction, and a copy of it costs one node until it is read. The generic walk
# would follow `next` into `prev` and back without end.
function copy_document(policy::CopyPolicy, held::ListNode)
    is_descendable_for_copy(policy, held) || return make_copy_placeholder(policy, held)
    _copy_list_node(policy, held)
end

function _copy_list_node(policy::CopyPolicy, original::ListNode)
    copied = ListNode(copy_document(policy, original.value))
    set_cell_function!(getfield(copied, :next), () -> _copy_list_link(policy, original, copied, :next, :prev))
    set_cell_function!(getfield(copied, :prev), () -> _copy_list_link(policy, original, copied, :prev, :next))
    copied
end

# The copy of the node that `link` of `original` holds, with its `back` link set
# to `copied`, or `nothing` at the end of the list. The copy is made in a cell of
# its own that is read with `peek`, so the link of the copy depends on no cell of
# the original: once read, it keeps the node that it copied.
_copy_list_link(policy::CopyPolicy, original::ListNode, copied::ListNode, link::Symbol, back::Symbol) =
    peek(ComputedCell(() -> begin
        linked = unwrap_cell(getfield(original, link))
        linked === nothing && return nothing
        linked_copy = _copy_list_node(policy, linked)
        set_cell_value!(getfield(linked_copy, back), copied)
        linked_copy
    end))

Base.getindex(n::ListNode)      = n.value
Base.setindex!(n::ListNode, v)  = (n.value = v; v)

"""
    getindex(head::ListNode, i::Integer)

Access the value at index `i` relative to `head`:
- 1 = head, 2 = head.next, 3 = head.next.next, ...
- 0 = head.prev, -1 = head.prev.prev, ...
"""
function Base.getindex(head::ListNode, i::Integer)
    if i >= 1
        node = head
        for _ in 1:(i - 1)
            node.next === nothing && throw(BoundsError(head, i))
            node = node.next::ListNode
        end
        return node.value
    else
        node = head
        for _ in 1:(1 - i)
            node.prev === nothing && throw(BoundsError(head, i))
            node = node.prev::ListNode
        end
        return node.value
    end
end

# Append a new node at the end of the right (next) tail.
function Base.push!(head::ListNode, value)
    node = ListNode(value)
    cur = head
    while cur.next !== nothing
        cur = cur.next::ListNode
    end
    cur.next = node
    node.prev = cur
    return head
end

# Prepend a new node at the end of the left (prev) tail.
function Base.pushfirst!(head::ListNode, value)
    node = ListNode(value)
    cur = head
    while cur.prev !== nothing
        cur = cur.prev::ListNode
    end
    cur.prev = node
    node.next = cur
    return head
end

"""
    get_left_tail(node) -> node

The far end of a chain, walking back.

Use it to reach the first link of a chain from any link of it: the top of a
file whose middle is on the screen, the oldest entry of a log.

# Example

    first_link = get_left_tail(node)

See also `get_right_tail`, `take_first` and `ListNode`.
"""
function get_left_tail(n::ListNode)
    cur = n
    while cur.prev !== nothing; cur = cur.prev::ListNode end
    return cur
end

"""
    get_right_tail(node) -> node

The far end of a chain, walking forward.

Use it to reach the last link of a chain from any link of it: the end of a
transcript, the newest entry of a log.

# Example

    last_link = get_right_tail(node)

See also `get_left_tail`, `take_first` and `ListNode`.
"""
function get_right_tail(n::ListNode)
    cur = n
    while cur.next !== nothing; cur = cur.next::ListNode end
    return cur
end

Base.IteratorSize(::Type{ListNode}) = Base.SizeUnknown()
Base.eltype(::Type{ListNode})       = ListNode

# Iterate from get_left_tail through to get_right_tail.
function Base.iterate(n::ListNode, cur::Union{ListNode,Nothing} = get_left_tail(n))
    cur === nothing && return nothing
    return (cur, cur.next)
end

"""
    take_first(node, count, direction = :next) -> values
    take_first(node, back, forward) -> values

The values of a few links around one, without walking the whole chain.

Use it to read the part of a long chain that a reader will see: the rows a
viewport shows, the last few entries of a log, the lines around a match. The
first form walks one way, `:next` or `:prev`; the second takes some of each and
answers them in order, the ones behind first.

# Example

    shown = take_first(node, 20)          # this link and the nineteen after it
    around = take_first(node, 5, 5)       # five behind, this one, five ahead

See also `ListNode`, `get_left_tail` and `get_right_tail`.
"""
function take_first(node::ListNode, n::Int, direction::Symbol=:next)
    result = Any[]
    current = node
    for _ in 1:n
        push!(result, current.value)
        next_node = direction == :next ? current.next : current.prev
        next_node === nothing && break
        current = next_node
    end
    result
end

# Take n elements in prev direction and m elements in next direction from center node
# Returns a vector with prev elements first (in reverse order), then center, then next elements
function take_first(node::ListNode, n_prev::Int, n_next::Int)
    result = Any[]
    # Collect prev elements (in reverse order since we traverse from center outward)
    prev_elements = Any[]
    current = node
    for _ in 1:n_prev
        prev_node = current.prev
        prev_node === nothing && break
        push!(prev_elements, prev_node.value)
        current = prev_node
    end
    # Reverse prev elements to get correct order (farthest first)
    for i in length(prev_elements):-1:1
        push!(result, prev_elements[i])
    end
    # Add center
    push!(result, node.value)
    # Collect next elements
    current = node
    for _ in 1:n_next
        next_node = current.next
        next_node === nothing && break
        push!(result, next_node.value)
        current = next_node
    end
    result
end
