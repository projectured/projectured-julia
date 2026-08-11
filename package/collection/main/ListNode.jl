# ── ListNode ──────────────────────────────────────────────────────────────
# A doubly-linked list node. The node you hold IS the head (middle of the
# list). `prev` and `next` are the two tails growing in opposite directions.

@document struct ListNode
    value::Any
    prev::Union{ListNode, Nothing}
    next::Union{ListNode, Nothing}
end

ListNode(value) =
    ListNode(Cell(value), Cell(nothing), Cell(nothing), Cell(nothing))

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

# Walk to the leftmost node (far end of the prev tail).
function get_left_tail(n::ListNode)
    cur = n
    while cur.prev !== nothing; cur = cur.prev::ListNode end
    return cur
end

# Walk to the rightmost node (far end of the next tail).
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

# Take first n elements from a ListNode in specified direction
# direction = :next for forward, :prev for backward
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
