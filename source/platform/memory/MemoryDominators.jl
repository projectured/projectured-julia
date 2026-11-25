# Fragment of `MemoryModule`.
#
# The holder of each object of a graph: its immediate dominator, the nearest object
# that every path from the root to it goes through. The iterative algorithm of
# Cooper, Harvey and Kennedy ("A Simple, Fast Dominance Algorithm", 2001) finds it.
# The graph numbers its objects in the order of a breadth-first walk, so the holder
# of an object has a smaller number than the object: every path to the object goes
# through the holder, and the shortest path does too.

# The edges into each object, in the form of the edges out of it.
function _make_predecessor_lists(graph::_MemoryGraph)
    count = length(graph.objects)
    starts = zeros(Int32, count + 1)
    for successor in graph.successors
        starts[successor + 1] += Int32(1)
    end
    starts[1] = Int32(1)
    for number in 1:count
        starts[number + 1] += starts[number]
    end
    places = starts[1:count]
    predecessors = Vector{Int32}(undef, length(graph.successors))
    for number in 1:count, edge in graph.successor_starts[number]:(graph.successor_starts[number + 1] - 1)
        successor = graph.successors[edge]
        predecessors[places[successor]] = Int32(number)
        places[successor] += Int32(1)
    end
    (starts, predecessors)
end

# The objects of `graph` in the order of a depth-first walk that lists an object
# after the objects below it, and the place of each object in that order.
function _make_postorder(graph::_MemoryGraph)
    count = length(graph.objects)
    order = Vector{Int32}(undef, count)
    places = zeros(Int32, count)
    entered = falses(count)
    stack = Int32[1]
    cursors = Int32[graph.successor_starts[1]]
    entered[1] = true
    filled = 0
    while !isempty(stack)
        number = stack[end]
        cursor = cursors[end]
        if cursor < graph.successor_starts[number + 1]
            cursors[end] = cursor + Int32(1)
            successor = graph.successors[cursor]
            if !entered[successor]
                entered[successor] = true
                push!(stack, successor)
                push!(cursors, graph.successor_starts[successor])
            end
        else
            pop!(stack)
            pop!(cursors)
            filled += 1
            order[filled] = number
            places[number] = Int32(filled)
        end
    end
    (order, places)
end

# The immediate dominator of each object of `graph`; the root holds itself.
function _compute_immediate_dominators(graph::_MemoryGraph)
    count = length(graph.objects)
    holders = zeros(Int32, count)
    count == 0 && return holders
    (order, places) = _make_postorder(graph)
    (starts, predecessors) = _make_predecessor_lists(graph)
    holders[1] = Int32(1)
    changed = true
    while changed
        changed = false
        # In reverse postorder, the root last in `order` and first here.
        for place in (count - 1):-1:1
            number = order[place]
            found = Int32(0)
            for edge in starts[number]:(starts[number + 1] - 1)
                predecessor = predecessors[edge]
                holders[predecessor] == 0 && continue
                found = found == 0 ? predecessor : _find_common_dominator(predecessor, found, holders, places)
            end
            if holders[number] != found
                holders[number] = found
                changed = true
            end
        end
    end
    holders
end

# The nearest object that dominates both `left` and `right`.
function _find_common_dominator(left::Int32, right::Int32, holders::Vector{Int32}, places::Vector{Int32})
    while left != right
        while places[left] < places[right]
            left = holders[left]
        end
        while places[right] < places[left]
            right = holders[right]
        end
    end
    left
end
