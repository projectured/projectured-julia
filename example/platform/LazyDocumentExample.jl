# Helper to create a ListNode with lazy thunk for next direction
function lazy_node(value, next_thunk::Function)
    node = ListNode(value)
    set_cell_computation!(getfield(node, :next), next_thunk)
    node
end

# Force evaluation of next cell
function force_next(ln::ListNode)
    if ln.next isa Function
        ln.next = ln.next()
    end
    ln.next
end

# Force evaluation of prev cell
function force_prev(ln::ListNode)
    if ln.prev isa Function
        ln.prev = ln.prev()
    end
    ln.prev
end

# Classic lazy Sieve of Eratosthenes
# sieve(stream, transform) returns a lazy stream of primes
# where stream is a ListNode of integers starting from 2
# transform is applied to each prime (e.g., identity for positive, negate for negative)
#
# parent is the previous prime in the chain (nothing for the head).  We link
# the child's `prev` back to its parent so the chain is a proper doubly-linked
# list — walkers that cache by objectid converge after one traversal instead
# of materialising a fresh prev-chain at every node.
# @optional: the transform and the parent link follow the stream, in the order the
# recursive step builds the next node.
function sieve(stream, transform::Function = identity, parent=nothing)
    head_val = stream.value  # PrimitiveNumber
    head_num = head_val.value  # Extract actual integer
    # Filter out multiples of head from the rest of the stream
    filtered = lazy_filter(stream, x -> x.value % head_num != 0)
    transformed_head = transform(head_val)
    node = ListNode(transformed_head)
    set_cell_computation!(getfield(node, :next), () -> sieve(filtered, transform, node))
    parent !== nothing && set_cell_value!(getfield(node, :prev), parent)
    node
end

# Lazy filter: returns a new ListNode containing only elements matching predicate
function lazy_filter(stream::ListNode, predicate::Function)
    current = stream
    # Skip elements that don't match predicate
    while current.next !== nothing
        if current.next isa Function
            current.next = force_next(current)
        end
        if current.next === nothing
            break
        end
        next_node = current.next::ListNode
        if predicate(next_node.value)
            # Found matching element, return lazy node with filtered tail
            return lazy_node(next_node.value, () -> lazy_filter(next_node, predicate))
        end
        current = next_node
    end
    nothing
end

# Create infinite stream of integers starting from n
function integers_from(n)
    lazy_node(PrimitiveNumber(n), () -> integers_from(n + 1))
end

function make_lazy_document_example()
    # Create infinite lazy list of primes using Sieve of Eratosthenes
    # Start with integers from 2, then apply sieve
    natural_numbers = integers_from(2)
    primes = sieve(natural_numbers)
    primes
end

# ── Bidirectional lazy sieve using ListNode ─────────────────────────────────

# Helper to create a ListNode with lazy thunks for both directions
function lazy_bidirectional_node(value, prev_thunk::Function, next_thunk::Function)
    node = ListNode(value)
    set_cell_computation!(getfield(node, :prev), prev_thunk)
    set_cell_computation!(getfield(node, :next), next_thunk)
    node
end

# Classic lazy Sieve of Eratosthenes for bidirectional streams
# sieve(stream, direction) returns a lazy stream of primes
# direction = :next for positive, :prev for negative
function sieve_bidirectional(stream, direction)
    val = stream.value  # PrimitiveNumber
    num = val.value      # Extract actual integer
    # Filter out multiples of val from the rest of the stream
    filtered = lazy_filter_bidirectional(stream, x -> x.value % num != 0, direction)
    # Return current value followed by sieve of filtered stream
    lazy_bidirectional_node(
        val,
        direction == :prev ? () -> sieve_bidirectional(filtered, :prev) : () -> stream.prev,
        direction == :next ? () -> sieve_bidirectional(filtered, :next) : () -> stream.next
    )
end

# Lazy filter for bidirectional streams
function lazy_filter_bidirectional(stream::ListNode, predicate::Function, direction)
    current = stream
    while (direction == :next ? current.next : current.prev) !== nothing
        if direction == :next
            if current.next isa Function
                current.next = force_next(current)
            end
        else
            if current.prev isa Function
                current.prev = force_prev(current)
            end
        end
        next_node = direction == :next ? current.next : current.prev
        if next_node === nothing
            break
        end
        next_ln = next_node::ListNode
        if predicate(next_ln.value)
            return lazy_bidirectional_node(
                next_ln.value,
                direction == :prev ? () -> lazy_filter_bidirectional(next_ln, predicate, :prev) : () -> next_ln.prev,
                direction == :next ? () -> lazy_filter_bidirectional(next_ln, predicate, :next) : () -> next_ln.next
            )
        end
        current = next_ln
    end
    nothing
end

# Create infinite stream of integers starting from n in a direction
function integers_from_bidirectional(n, direction)
    lazy_bidirectional_node(
        PrimitiveNumber(n),
        direction == :prev ? () -> integers_from_bidirectional(n - 1, :prev) : () -> nothing,
        direction == :next ? () -> integers_from_bidirectional(n + 1, :next) : () -> nothing
    )
end

# Like `sieve`, but each successive prime is linked via `.prev` instead of
# `.next`.  Used to build the negative half of the bidirectional example so
# that walking `.prev` from one neg-prime node reaches the next neg-prime.
# `child` is the node further toward the head (in the `.next` direction);
# linking `node.next = child` makes the chain a proper doubly-linked list.
# @optional: the transform and the child link follow the stream, in the order the
# recursive step builds the next node.
function sieve_prev(stream, transform::Function = identity, child=nothing)
    head_val = stream.value
    head_num = head_val.value
    filtered = lazy_filter(stream, x -> x.value % head_num != 0)
    transformed_head = transform(head_val)
    node = ListNode(transformed_head)
    set_cell_computation!(getfield(node, :prev),
                          () -> sieve_prev(filtered, transform, node))
    child !== nothing && set_cell_value!(getfield(node, :next), child)
    node
end

function make_lazy_bidirectional_document_example()
    # Center on 2.
    #   Positive direction: 2, 3, 5, 7, 11, ...  (linked via .next)
    #   Negative direction: -2, -3, -5, -7, ...  (linked via .prev)

    pos_primes = sieve(integers_from(2), identity)
    neg_primes = sieve_prev(integers_from(2), x -> PrimitiveNumber(-x.value))

    # `pos_primes` already has value=2 and a lazy `.next` chain — use it
    # directly as the head, then graft the neg chain onto its `.prev`.
    head = pos_primes
    set_cell_value!(getfield(head, :prev), neg_primes)
    set_cell_value!(getfield(neg_primes, :next), head)

    head
end

# ── The primes around a number ──────────────────────────────────────────────

# Whether `n` is prime, by trial division by 2 and by the odd numbers up to its
# square root. It reads nothing but `n`, so a number near one trillion costs the
# same whatever was computed before it.
function is_prime_number(n::Integer)
    n < 2 && return false
    n < 4 && return true
    iseven(n) && return false
    divisor = 3
    while divisor * divisor <= n
        n % divisor == 0 && return false
        divisor += 2
    end
    true
end

# The smallest prime greater than `n`.
function compute_next_prime(n::Integer)
    candidate = n + 1
    while !is_prime_number(candidate)
        candidate += 1
    end
    candidate
end

# The largest prime less than `n`, or `nothing` when there is none.
function find_previous_prime(n::Integer)
    candidate = n - 1
    while candidate >= 2
        is_prime_number(candidate) && return candidate
        candidate -= 1
    end
    nothing
end

"""
    make_primes_around(n) -> ListNode

The primes around `n`, as a chain that reaches both ways. The node is the first
prime that is not less than `n`, each `next` is the next prime, and each `prev` is
the prime before it, down to 2. A link is computed when it is first read, and each
prime is found by a test of that number alone, so the chain around one trillion
costs only the links that a reader reads.

# Example

    around = make_primes_around(10^12)
    around.value.value           # 1000000000039, the first prime after one trillion
    around.prev.value.value      # 999999999989, the last one before it
"""
make_primes_around(n::Integer) =
    _make_prime_node(is_prime_number(n) ? n : compute_next_prime(n), nothing, nothing)

# The node of the prime `p`. A neighbour that is given is linked as a value; the
# other link computes its neighbour when it is first read, and the neighbour links
# back to this node, so a walk forward and back meets the same nodes.
function _make_prime_node(p::Integer, before, after)
    node = ListNode(PrimitiveNumber(p))
    if after === nothing
        set_cell_computation!(getfield(node, :next),
                              () -> _make_prime_node(compute_next_prime(p), node, nothing))
    else
        set_cell_value!(getfield(node, :next), after)
    end
    if before === nothing
        set_cell_computation!(getfield(node, :prev), () -> begin
            q = find_previous_prime(p)
            q === nothing ? nothing : _make_prime_node(q, nothing, node)
        end)
    else
        set_cell_value!(getfield(node, :prev), before)
    end
    node
end
