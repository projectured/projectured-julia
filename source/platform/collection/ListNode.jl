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
@document struct ListNode <: ListDocument
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
    _copy_list_node_lazily(node -> ListNode(copy_document(policy, node.value)), held)
end

# The kinded copy makes every cell of kind `K`. A reactive cell can compute its
# value, so the reactive copy is lazy, as the copy above is. A cell of another
# kind holds a value, so that copy copies and links every node at once, and it
# does not end for a list without an end. An immutable cell can not take the link
# back to a node that is made after it, so an immutable copy of a node with a
# neighbour raises a `DocumentCopyException`.
function copy_document(K::Type{<:AbstractCell}, held::ListNode, policy, depth::Int)
    copy_node = _make_list_node_copier(K, policy, depth)
    K === ReactiveCell && return _copy_list_node_lazily(copy_node, held)
    K === ImmutableCell && !(held.prev === nothing && held.next === nothing) &&
        throw(DocumentCopyException(held, "an immutable cell can not hold the link back to a node that is made after it"))
    copied = copy_node(held)
    _copy_list_tail!(copy_node, copied, held, :next, :prev)
    _copy_list_tail!(copy_node, copied, held, :prev, :next)
    copied
end

# A function that copies one node of a kinded copy, with no link.
_make_list_node_copier(K::Type{<:AbstractCell}, policy, depth::Int) =
    node -> _copy_unlinked_list_node(K, node, policy, depth)

# One node of a kinded copy with no link: the generic walk copies its value and
# its selection, and gives `prev` and `next` a cell of kind `K` that holds `nothing`.
function _copy_unlinked_list_node(K::Type{<:AbstractCell}, original::ListNode, policy, depth::Int)
    unlinked = _make_unlinked_list_node(original)
    invoke(copy_document, Tuple{Type{<:AbstractCell}, Document, Any, Int}, K, unlinked, policy, depth)
end

# A node that holds the `value` cell and the `selection` cell of `node`, and no
# link. A walk over it reaches everything of the node but the two links, and a
# write through it goes into the cells of the node.
_make_unlinked_list_node(node::ListNode) =
    ListNode(getfield(node, :value), Cell(nothing), Cell(nothing), getfield(node, :selection))

# Copies each node that follows `original` in the direction `link`, and links each
# copy after `copied`. A copy of a kind that holds a value reaches the end of the
# list this way.
function _copy_list_tail!(copy_node, copied::ListNode, original::ListNode, link::Symbol, back::Symbol)
    last = copied
    node = getproperty(original, link)
    while node !== nothing
        following = copy_node(node)
        _link_list_nodes!(last, following, link, back)
        last = following
        node = getproperty(node, link)
    end
end

# Links `after` behind `before` in the direction `link`, and `before` behind
# `after` in the direction `back`.
function _link_list_nodes!(before::ListNode, after::ListNode, link::Symbol, back::Symbol)
    getfield(before, link)[] = after
    getfield(after, back)[] = before
end

# `copy_node(original)` copies one node with no link. `prev` and `next` of the copy
# are cells that copy the neighbour when they are read.
function _copy_list_node_lazily(copy_node, original::ListNode)
    copied = copy_node(original)
    _set_list_link_lazily!(copy_node, original, copied, :next, :prev)
    _set_list_link_lazily!(copy_node, original, copied, :prev, :next)
    copied
end

# Makes `link` of `copied` a cell that copies the node that `link` of `original`
# holds, when it is read.
_set_list_link_lazily!(copy_node, original::ListNode, copied::ListNode, link::Symbol, back::Symbol) =
    set_cell_computation!(getfield(copied, link),
                       () -> _copy_list_link(copy_node, original, copied, link, back))

# The copy of the node that `link` of `original` holds, with its `back` link set
# to `copied`, or `nothing` at the end of the list. The copy is made in a cell of
# its own that is read with `peek`, so the link of the copy depends on no cell of
# the original: once read, it keeps the node that it copied.
_copy_list_link(copy_node, original::ListNode, copied::ListNode, link::Symbol, back::Symbol) =
    peek(Cell(@computation begin
        linked = unwrap_cell(getfield(original, link))
        linked === nothing && return nothing
        linked_copy = _copy_list_node_lazily(copy_node, linked)
        set_cell_value!(getfield(linked_copy, back), copied)
        linked_copy
    end))

# A list shadow is synced from the node that it holds outward, one direction at a
# time, so the walk never follows `next` back through `prev`. The generic walk
# syncs each node, without its links. A link of the shadow that nothing has read
# stays one that copies the neighbour of its source node when it is read, so a
# sync of a list without an end ends.
function sync_document!(shadow::ListNode, source::ListNode, policy, depth::Int)
    _sync_unlinked_list_node!(shadow, source, policy, depth)
    _sync_list_tail!(shadow, source, :next, :prev, policy, depth)
    _sync_list_tail!(shadow, source, :prev, :next, policy, depth)
    shadow
end

# The value and the selection of one node, through the generic walk.
_sync_unlinked_list_node!(shadow::ListNode, source::ListNode, policy, depth::Int) =
    invoke(sync_document!, Tuple{Document, Document, Any, Int},
           _make_unlinked_list_node(shadow), _make_unlinked_list_node(source), policy, depth)

# The nodes that follow `shadow` in the direction `link`, against the ones that
# follow `source`. The walk pairs the node of each place, and it ends at a link of
# the shadow that nothing has read, at the end of either list, or where the shadow
# grows. A shadow of a kind that holds a value grows to the end of the source at
# once; a reactive one grows when a reader reads the link.
function _sync_list_tail!(shadow::ListNode, source::ListNode, link::Symbol, back::Symbol, policy, depth::Int)
    K = get_cell_struct_kind(shadow)
    copy_node = _make_list_node_copier(K, policy, depth)
    shadow_node, source_node = shadow, source
    while true
        cell = getfield(shadow_node, link)
        if is_computed_cell(cell) && !is_cell_up_to_date(cell)
            _set_list_link_lazily!(copy_node, source_node, shadow_node, link, back)
            return
        end
        linked_shadow, linked_source = peek(cell), getproperty(source_node, link)
        if linked_source === nothing
            linked_shadow === nothing || (cell[] = nothing)
            return
        end
        if linked_shadow === nothing
            K === ReactiveCell ?
                _set_list_link_lazily!(copy_node, source_node, shadow_node, link, back) :
                _copy_list_tail!(copy_node, shadow_node, source_node, link, back)
            return
        end
        _sync_unlinked_list_node!(linked_shadow, linked_source, policy, depth)
        shadow_node, source_node = linked_shadow, linked_source
    end
end

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

"""
    find_list_node(head::ListNode, index::Integer) -> ListNode | Nothing

The node at `index` counted from `head`, as `getindex` counts: 1 is `head`, 2
the node after it, 0 the node before it. `nothing` when the chain ends first.

Use it to reach the node of an element that a reference names by its index: it
reads the links on the way, so a lazy chain builds the nodes up to that one.
"""
function find_list_node(head::ListNode, index::Integer)
    node = head
    link = index >= 1 ? :next : :prev
    for _ in 1:abs(index - 1)
        node = getproperty(node, link)
        node === nothing && return nothing
    end
    node
end

"""
    find_list_index(head, node; limit = 10_000) -> Int | Nothing

The index of `node` counted from `head`, as `find_list_node` counts: 1 is `head`,
2 the node after it, 0 the node before it. `nothing` when `head` is not a
`ListNode`, or when the chain does not hold `node` within `limit` links each way.

Use it to turn a node back into a place, such as the new head of a list that a
table writes, when the owner of the list keeps the place as an anchor. It walks
both ways from `head` and reads the links on the way, so a lazy chain builds the
nodes that it passes.
"""
function find_list_index(head, node; limit::Int = 10_000)
    head isa ListNode || return nothing
    forward, backward = head, head
    for k in 0:limit
        forward === node && return 1 + k
        backward === node && return 1 - k
        forward = forward === nothing ? nothing : forward.next
        backward = backward === nothing ? nothing : backward.prev
        forward === nothing && backward === nothing && return nothing
    end
    nothing
end

"""
    make_index_list(count, at, value_of; computed = false) -> ListNode

The list of the values of the indices `1:count`, with its head at the index
`at`, clamped to the range. `value_of(i)` makes the value of the index `i` when
a walk first reaches it. With `computed`, `value_of(i)` is instead a function
of no arguments, and the value of the node is a cell that computes it.

Each link builds its neighbour when it is first read, and the neighbour links
back, so a walk down and back up meets the same nodes. The first index has no
`prev` and the last has no `next`, so a viewport stops at both. `count` must be
at least 1.

Use it for a table of many rows that builds only the rows a viewport reaches,
with its head at the row its owner keeps as an anchor.

# Example

    squares = make_index_list(1000, 300, i -> i^2)
    squares.value         # 90000, the value of the head
    squares.prev.value    # 89401, built on this read
"""
make_index_list(count::Int, at::Int, value_of; computed::Bool = false) =
    _make_index_node(count, clamp(at, 1, count), value_of, nothing, nothing; computed)

# The node of the index `i`. A neighbour that is given is linked as a value, and
# the other link builds its neighbour when it is first read.
function _make_index_node(count::Int, i::Int, value_of, before, after; computed::Bool = false)
    node = computed ? ListNode(nothing) : ListNode(value_of(i))
    computed && set_cell_computation!(getfield(node, :value), value_of(i))
    if after === nothing
        set_cell_computation!(getfield(node, :next),
            () -> i < count ? _make_index_node(count, i + 1, value_of, node, nothing; computed) : nothing)
    else
        set_cell_value!(getfield(node, :next), after)
    end
    if before === nothing
        set_cell_computation!(getfield(node, :prev),
            () -> i > 1 ? _make_index_node(count, i - 1, value_of, nothing, node; computed) : nothing)
    else
        set_cell_value!(getfield(node, :prev), before)
    end
    node
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

See also `ListNode`, `get_left_tail`, `get_right_tail` and `count_computed_nodes`.
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

"""
    count_computed_nodes(node) -> Int

The number of links of a chain that exist now, the node itself too, counted
without computing one more.

Use it to show how far a lazy chain has been read: a `next` or a `prev` whose
computation has not run yet ends the count in that direction, and it stays not
run. A chain without an end, of which a viewport has read thirty links, counts
thirty.

# Example

    numbers = integers_from(1)       # each `next` computes the next number
    count_computed_nodes(numbers)    # 1: only the node itself
    numbers[5]                       # reads four links
    count_computed_nodes(numbers)    # 5

See also `take_first` and `ListNode`.
"""
count_computed_nodes(node::ListNode) =
    1 + _count_computed_links(node, :next) + _count_computed_links(node, :prev)

# The links that follow `node` in the direction `link` and exist now. A link whose
# computation has not run ends the walk, and `peek` reads the others, so the count
# computes nothing and depends on no cell of the chain.
function _count_computed_links(node::ListNode, link::Symbol)
    count = 0
    current = node
    while true
        cell = getfield(current, link)
        is_computed_cell(cell) && !is_cell_up_to_date(cell) && return count
        linked = peek(cell)
        linked isa ListNode || return count
        count += 1
        current = linked
    end
end
