# Fragment of `MemoryModule`.
#
# The graph of the objects that a root reaches through strong references. The walk
# gives each object one number, in the order of a breadth-first walk from the root,
# so the root is 1 and an object has a larger number than the object that the walk
# reached it from. It records the edges of each object in that order.
#
# The walk follows each pointer of an object, as `Base.summarysize` does, with
# these rules:
#
# - It does not follow the value of a `WeakRef`.
# - It does not enter a module, a type, a method or compiled code. Each of these
#   counts by its own size, and a module counts no bytes. Their bytes are the
#   bytes that the walk does not walk into.
# - It enters a `Task` through its fields `code`, `result` and `storage` only.
# - A symbol and a value of a type that has one value, such as `nothing`, are no
#   objects of the graph: they belong to no holder.

# The objects that the walk counts by their own size and does not enter.
const _UnenteredObject = Union{Module, Type, Core.TypeName, Method, Core.MethodInstance,
                               Core.CodeInstance, Core.CodeInfo, Core.MethodTable,
                               Core.TypeMapEntry, Core.SimpleVector}

# The objects that a walk reached, and the edges between them. The object `i` is
# `objects[i]`; its edges go to `successors[successor_starts[i]:successor_starts[i + 1] - 1]`;
# `parents[i]` is the object that the walk reached it from first, 0 for the root.
# `kinds` holds the type of each object as an index of `types`.
mutable struct _MemoryGraph
    objects::Vector{Any}
    own_bytes::Vector{Int}
    parents::Vector{Int32}
    kinds::Vector{Int32}
    successor_starts::Vector{Int32}
    successors::Vector{Int32}
    types::Vector{DataType}
    type_numbers::IdDict{DataType, Int32}
    unwalked_bytes::Int
    # The number of the object whose edges the walk records now.
    current::Int32
    # The number of each object that the walk reached, by its address.
    numbers::Dict{UInt, Int32}
end

_MemoryGraph() = _MemoryGraph(Any[], Int[], Int32[], Int32[], Int32[], Int32[], DataType[],
                              IdDict{DataType, Int32}(), 0, Int32(0), Dict{UInt, Int32}())

# Whether `x` is an object of the graph.
_is_graph_object(@nospecialize(x)) = !(x isa Symbol) && !Base.issingletontype(typeof(x))

_get_object_address(@nospecialize(x)) = UInt(ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), x))

# The bytes of `x` itself, as `Base.summarysize` counts them.
function _get_own_bytes(@nospecialize(x))
    x isa String && return sizeof(Int) + sizeof(x)
    x isa GenericMemory && return 2 * sizeof(Int) + sizeof(x)
    x isa Array && return sizeof(typeof(x))
    x isa DataType && return sizeof(DataType)
    # Julia gives no size of a module.
    x isa Module && return 0
    (x isa UnionAll || x isa Union) && return 2 * sizeof(Int)
    try
        Core.sizeof(x)
    catch
        0
    end
end

# Give `x` the next number, and record that the walk reached it from `parent`.
function _add_graph_object!(graph::_MemoryGraph, @nospecialize(x), parent::Int32)
    length(graph.objects) < typemax(Int32) ||
        throw(ArgumentError("compute_held_memory: the root reaches more than $(typemax(Int32)) objects"))
    push!(graph.objects, x)
    bytes = _get_own_bytes(x)
    push!(graph.own_bytes, bytes)
    push!(graph.parents, parent)
    type = typeof(x)
    kind = get!(graph.type_numbers, type) do
        push!(graph.types, type)
        Int32(length(graph.types))
    end
    push!(graph.kinds, kind)
    x isa _UnenteredObject && (graph.unwalked_bytes += bytes)
    number = Int32(length(graph.objects))
    graph.numbers[_get_object_address(x)] = number
    number
end

# Record the edge from the current object to `child`.
struct _EdgeRecorder
    graph::_MemoryGraph
end

function (recorder::_EdgeRecorder)(@nospecialize(child))
    _is_graph_object(child) || return nothing
    graph = recorder.graph
    number = get(graph.numbers, _get_object_address(child), Int32(0))
    number == 0 && (number = _add_graph_object!(graph, child, graph.current))
    push!(graph.successors, number)
    nothing
end

# Call `visit` for each object that `x` points to, under the rules of the walk.
function _visit_pointed_objects(visit, @nospecialize(x))
    (x isa String || x isa WeakRef || x isa _UnenteredObject) && return nothing
    if x isa Task
        isdefined(x, :code) && visit(x.code)
        isdefined(x, :result) && visit(x.result)
        isdefined(x, :storage) && visit(x.storage)
        return nothing
    end
    x isa GenericMemory && return _visit_memory_elements(visit, x)
    for place in 1:Base.datatype_npointers(typeof(x))
        Base.nth_pointer_isdefined(x, place) && visit(Base.get_nth_pointer(x, place))
    end
    nothing
end

function _visit_memory_elements(visit, @nospecialize(memory::GenericMemory))
    element_type = eltype(memory)
    if !Base.allocatedinline(element_type)
        for index in 1:length(memory)
            isassigned(memory, index) && visit(memory[index])
        end
    elseif element_type isa DataType && !Base.datatype_pointerfree(element_type)
        # An element that the memory holds in place, with pointers of its own.
        count = Base.datatype_npointers(element_type)
        for index in 1:length(memory)
            isassigned(memory, index) || continue
            element = memory[index]
            for place in 1:count
                Base.nth_pointer_isdefined(element, place) && visit(Base.get_nth_pointer(element, place))
            end
        end
    end
    nothing
end

# The graph of the objects that `root` reaches.
function _make_memory_graph(@nospecialize(root))
    graph = _MemoryGraph()
    _is_graph_object(root) || return graph
    _add_graph_object!(graph, root, Int32(0))
    recorder = _EdgeRecorder(graph)
    number = 1
    while number <= length(graph.objects)
        graph.current = Int32(number)
        push!(graph.successor_starts, Int32(length(graph.successors) + 1))
        _visit_pointed_objects(recorder, graph.objects[number])
        number += 1
    end
    push!(graph.successor_starts, Int32(length(graph.successors) + 1))
    graph
end

# The bytes of the tables of `graph`.
_get_graph_table_bytes(graph::_MemoryGraph) =
    sum(sizeof, (graph.objects, graph.own_bytes, graph.parents, graph.kinds,
                 graph.successor_starts, graph.successors)) +
    sizeof(graph.numbers.slots) + sizeof(graph.numbers.keys) + sizeof(graph.numbers.vals)
