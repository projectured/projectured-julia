# Fragment of `MemoryModule`.
#
# The report of what holds the memory of a root: the holders that keep the most
# bytes, each with its path from the root, and the bytes of each type.

"""
    MemoryHolder(path, type, bytes, object_count)

One holder of a report of [`compute_held_memory`](@ref): an object, and the
objects that it keeps. A holder keeps an object when every path from the root to
the object goes through the holder.

- `path` is the shortest path from the root to the holder. A step is the name of
  a field, `.back`, or an index of a list, `[3]`. A field of a cell gives no step.
  An entry of a `Dict` or an `IdDict` gives the step of its key when the key is a
  string, a symbol, a number or a type, `["name"]`, and otherwise the type of its
  key with a mark of the identity of the key, `[#3fa91c JsonObject]`, which stays
  while the key lives; its key adds `.key`. The empty path is the root.
- `type` is the type of the holder.
- `bytes` are the bytes of the holder and of the objects that it keeps.
- `object_count` is the count of those objects, with the holder.
"""
struct MemoryHolder
    path::String
    type::Type
    bytes::Int
    object_count::Int
end

"""
    HeldType(type, bytes, object_count)

The objects of one type that the root of a report reaches: the count of them, and
the bytes of each of them alone.
"""
struct HeldType
    type::Type
    bytes::Int
    object_count::Int
end

"""
    HeldMemory

The report of [`compute_held_memory`](@ref):

- `root_type`, the type of the root;
- `total_bytes`, the bytes of the objects that the root reaches through strong
  references, and `object_count`, the count of them;
- `holders`, the holders that keep the most bytes, largest first
  ([`MemoryHolder`](@ref));
- `types`, the bytes and the count of the objects of each type, largest first
  ([`HeldType`](@ref));
- `unwalked_bytes`, the bytes of the modules, the types, the methods and the
  compiled code that the root reaches. The walk counts each of them by its own
  size and does not walk into it;
- `walk_bytes`, the bytes of the tables that the walk made, at their largest.
"""
struct HeldMemory
    root_type::Type
    total_bytes::Int
    object_count::Int
    holders::Vector{MemoryHolder}
    types::Vector{HeldType}
    unwalked_bytes::Int
    walk_bytes::Int
end

"""
    compute_held_memory(root; minimum_bytes = 1 MiB, minimum_share = 0.01, limit = 40) -> HeldMemory

**What holds the memory of `root`**: the objects that `root` reaches through
strong references, with the holders that keep the most of them.

The walk does not follow the value of a `WeakRef`. It does not walk into a
module, a type, a method or compiled code, and counts each of them by its own
size; a module counts no bytes. It walks into a closure through its captured fields, and into a `Task`
through its fields `code`, `result` and `storage`.

A holder keeps an object when every path from `root` to the object goes through
the holder, so no object counts two times, and a growth goes to the store that
keeps it. The report lists each holder that keeps at least `minimum_bytes`, or at
least the share `minimum_share` of the total, when no object that it keeps holds
90 % of its bytes. So a line names a store, and not each object on the path to
it. It lists at most `limit` holders, largest first.

The walk holds the process for its time, and it needs about 100 bytes for each
object that `root` reaches: `walk_bytes` says how many it needed.

# Example

    report = compute_held_memory(editor)
    report.total_bytes            # the bytes that the editor reaches
    first(report.holders).path    # ".document.windows[1].navigator.back", for example
"""
function compute_held_memory(@nospecialize(root); minimum_bytes::Integer = 1 << 20,
                             minimum_share::Real = 0.01, limit::Integer = 40)
    graph = _make_memory_graph(root)
    walk_bytes = _get_graph_table_bytes(graph)
    # The numbers by address are for the walk only.
    graph.numbers = Dict{UInt, Int32}()
    count = length(graph.objects)
    count == 0 && return HeldMemory(typeof(root), 0, 0, MemoryHolder[], HeldType[], 0, walk_bytes)
    holders = _compute_immediate_dominators(graph)
    (kept_bytes, kept_counts, largest_parts) = _compute_kept_sums(graph, holders)
    walk_bytes = max(walk_bytes, _get_graph_table_bytes(graph) + sizeof(holders) + sizeof(kept_bytes) +
                                 sizeof(kept_counts) + sizeof(largest_parts) +
                                 _get_dominator_table_bytes(graph))
    total = kept_bytes[1]
    smallest = min(minimum_bytes, minimum_share * total)
    listed = [number for number in 1:count
              if kept_bytes[number] >= smallest && largest_parts[number] < 0.9 * kept_bytes[number] &&
                 !_is_held_storage(graph, number, holders[number])]
    sort!(listed; by = number -> -kept_bytes[number])
    length(listed) > limit && resize!(listed, limit)
    cache = _PathCache()
    holder_list = MemoryHolder[MemoryHolder(_describe_object_path(graph, number, cache),
                                            graph.types[graph.kinds[number]],
                                            kept_bytes[number], kept_counts[number])
                               for number in listed]
    HeldMemory(typeof(root), total, count, holder_list, _make_held_types(graph),
               graph.unwalked_bytes, walk_bytes)
end

# The bytes and the count of the objects that each object keeps, and the bytes of
# the largest part that one object below it keeps. An object has a larger number
# than its holder, so a walk from the last object adds each object to its holder
# after the objects below it. The memory of the elements of a list or of a
# dictionary is a part of its owner, and no part below it: the largest part of the
# owner is the largest element.
function _compute_kept_sums(graph::_MemoryGraph, holders::Vector{Int32})
    count = length(graph.objects)
    kept_bytes = copy(graph.own_bytes)
    kept_counts = ones(Int, count)
    largest_parts = zeros(Int, count)
    for number in count:-1:2
        holder = holders[number]
        kept_bytes[holder] += kept_bytes[number]
        kept_counts[holder] += kept_counts[number]
        part = _is_held_storage(graph, number, holder) ? largest_parts[number] : kept_bytes[number]
        largest_parts[holder] = max(largest_parts[holder], part)
    end
    (kept_bytes, kept_counts, largest_parts)
end

# Whether the object `number` is the memory that holds the elements of its holder,
# a list or a dictionary, which the walk reached it from.
_is_held_storage(graph::_MemoryGraph, number::Integer, holder::Integer) =
    graph.objects[number] isa GenericMemory && graph.parents[number] == holder &&
    graph.objects[holder] isa Union{Array, Dict, IdDict}

# The bytes of the tables that `_compute_immediate_dominators` makes for `graph`.
_get_dominator_table_bytes(graph::_MemoryGraph) =
    4 * (5 * length(graph.objects) + length(graph.successors)) + length(graph.objects) ÷ 8

function _make_held_types(graph::_MemoryGraph)
    bytes = zeros(Int, length(graph.types))
    counts = zeros(Int, length(graph.types))
    for number in eachindex(graph.objects)
        kind = graph.kinds[number]
        bytes[kind] += graph.own_bytes[number]
        counts[kind] += 1
    end
    types = HeldType[HeldType(graph.types[kind], bytes[kind], counts[kind]) for kind in eachindex(graph.types)]
    sort!(types; by = type -> -type.bytes)
end

# ── The path of a holder ─────────────────────────────────────────────────────

# What the paths of one report have found: the path of each object on the way to a
# holder, by its number, and the place of each element of a large memory. So a path
# goes on from the path of the object before it, and a memory is searched once.
struct _PathCache
    paths::Dict{Int32, String}
    places::IdDict{Any, IdDict{Any, Int}}
end

_PathCache() = _PathCache(Dict{Int32, String}(Int32(1) => ""), IdDict{Any, IdDict{Any, Int}}())

# The path from the root to the object `number`, along the objects that the walk
# reached each object from first.
function _describe_object_path(graph::_MemoryGraph, number::Integer, cache::_PathCache)
    chain = Int32[]
    while !haskey(cache.paths, number)
        push!(chain, number)
        number = graph.parents[number]
    end
    path = cache.paths[number]
    for child in Iterators.reverse(chain)
        parent = graph.parents[child]
        above = graph.parents[parent]
        path *= _describe_step(graph.objects[parent], graph.objects[child],
                               above == 0 ? nothing : graph.objects[above], cache)
        cache.paths[child] = path
    end
    path
end

# The step from `parent` to `child`; `above` is the object that the walk reached
# `parent` from, or `nothing`. A cell, a box of a captured variable, a list, a
# dictionary and the memory that holds their elements give one step together.
function _describe_step(@nospecialize(parent), @nospecialize(child), @nospecialize(above), cache::_PathCache)
    (parent isa AbstractCell || parent isa Core.Box || parent isa Array || parent isa Dict ||
     parent isa IdDict) && return ""
    parent isa GenericMemory && return _describe_memory_step(parent, child, above, cache)
    if parent isa Task
        for field in (:code, :result, :storage)
            isdefined(parent, field) && getfield(parent, field) === child && return "." * String(field)
        end
        return ".?"
    end
    something(_find_field_step(parent, child), ".?")
end

# The fields from `x` to `child`, when `x` or a value that it holds in place
# points to `child`; `nothing` otherwise.
function _find_field_step(@nospecialize(x), @nospecialize(child))
    type = typeof(x)
    for field in 1:fieldcount(type)
        isdefined(x, field) || continue
        declared = fieldtype(type, field)
        name = fieldname(type, field)
        if !Base.allocatedinline(declared)
            getfield(x, field) === child && return _describe_field_name(name)
        elseif declared isa DataType && !Base.datatype_pointerfree(declared)
            inner = _find_field_step(getfield(x, field), child)
            inner === nothing || return _describe_field_name(name) * inner
        end
    end
    nothing
end

_describe_field_name(name::Symbol) = "." * String(name)
_describe_field_name(name::Integer) = "[" * string(name) * "]"

function _describe_memory_step(@nospecialize(memory::GenericMemory), @nospecialize(child), @nospecialize(above),
                               cache::_PathCache)
    index = _find_memory_place(memory, child, cache)
    index == 0 && return "[?]"
    inner = Base.allocatedinline(eltype(memory)) ? something(_find_field_step(memory[index], child), "") : ""
    if above isa Array && above.ref.mem === memory
        return "[" * string(index - Base.memoryrefoffset(above.ref) + 1) * "]" * inner
    elseif above isa Dict && memory === above.vals
        return "[" * _describe_dict_entry(above, index) * "]" * inner
    elseif above isa Dict && memory === above.keys
        return "[" * _describe_dict_entry(above, index) * "].key" * inner
    elseif above isa IdDict && memory === above.ht
        key = isodd(index) ? index : index - 1
        return "[" * _describe_id_dict_entry(memory, key) * "]" * (isodd(index) ? ".key" : "") * inner
    end
    "[" * string(index) * "]" * inner
end

# The index of the element of `memory` that is `child` or points to it, or 0 when
# no element does. A small memory is searched; a large one gets a table of the
# places of what its elements point to, once.
function _find_memory_place(@nospecialize(memory::GenericMemory), @nospecialize(child), cache::_PathCache)
    if length(memory) <= 32
        for index in 1:length(memory)
            isassigned(memory, index) && _is_pointed_by(memory[index], child, memory) && return index
        end
        return 0
    end
    places = get!(() -> _make_memory_places(memory), cache.places, memory)
    get(places, child, 0)
end

# Whether `element`, an element of `memory`, is `child` or holds a pointer to it.
function _is_pointed_by(@nospecialize(element), @nospecialize(child), @nospecialize(memory::GenericMemory))
    Base.allocatedinline(eltype(memory)) || return element === child
    _find_field_step(element, child) !== nothing
end

# The index of the first element of `memory` that is each object, or that points
# to it.
function _make_memory_places(@nospecialize(memory::GenericMemory))
    places = IdDict{Any, Int}()
    element_type = eltype(memory)
    inline = Base.allocatedinline(element_type)
    count = inline && element_type isa DataType ? Base.datatype_npointers(element_type) : 0
    for index in 1:length(memory)
        isassigned(memory, index) || continue
        element = memory[index]
        if !inline
            haskey(places, element) || (places[element] = index)
        else
            for place in 1:count
                Base.nth_pointer_isdefined(element, place) || continue
                pointed = Base.get_nth_pointer(element, place)
                haskey(places, pointed) || (places[pointed] = index)
            end
        end
    end
    places
end

# The words of the entry of `dict` at the place `index` of its table.
_describe_dict_entry(dict::Dict, index::Integer) = _describe_entry_key(dict.keys[index])

# The words of the entry of an `IdDict` whose key is at `index` of its table.
_describe_id_dict_entry(@nospecialize(table::GenericMemory), index::Integer) = _describe_entry_key(table[index])

# The words of the key of an entry: the key itself when it is plain, and otherwise
# the type of the key with a mark of its identity, which stays while the key lives.
# The place of the entry would change when the table grows, and so would the path
# of each holder below it.
function _describe_entry_key(@nospecialize(key))
    _is_plain_key(key) && return _format_plain_key(key)
    "#" * string(objectid(key) % 0x1000000; base = 16, pad = 6) * " " * _get_short_type_name(typeof(key))
end

# A key that the step shows as it is: a string, a symbol, a number, a character or
# a type.
_is_plain_key(@nospecialize(key)) = key isa Union{AbstractString, Symbol, Number, Char, Type}

function _format_plain_key(@nospecialize(key))
    text = key isa Type ? _get_type_name(key) : repr(key)
    length(text) > 40 ? first(text, 39) * "…" : text
end

# The name of `type` without its parameters and its module.
_get_short_type_name(@nospecialize(type)) = type isa DataType ? string(nameof(type)) : string(type)

# The name of `type` with the names of its parameters, without their modules. A
# type of more than three parameters, such as a document with a cell for each
# field, shows `{…}`.
function _get_type_name(@nospecialize(type))
    type isa DataType || return string(type)
    name = string(nameof(type))
    isempty(type.parameters) && return name
    length(type.parameters) > 3 && return name * "{…}"
    words = [parameter isa DataType ? string(nameof(parameter)) : string(parameter)
             for parameter in type.parameters]
    name * "{" * join(words, ", ") * "}"
end

# ── The text of a report ─────────────────────────────────────────────────────

function _format_byte_count(bytes::Integer)
    bytes < 1024 && return string(bytes, " B")
    for (unit, size) in (("GiB", 1 << 30), ("MiB", 1 << 20), ("KiB", 1 << 10))
        bytes >= size && return string(round(bytes / size; digits = 1), " ", unit)
    end
end

Base.show(io::IO, report::HeldMemory) =
    print(io, "HeldMemory(", _format_byte_count(report.total_bytes), " in ", report.object_count, " objects)")

function Base.show(io::IO, ::MIME"text/plain", report::HeldMemory)
    println(io, "The ", _get_type_name(report.root_type), " reaches ", _format_byte_count(report.total_bytes),
            " in ", report.object_count, " objects.")
    report.unwalked_bytes > 0 &&
        println(io, _format_byte_count(report.unwalked_bytes), " of them are modules, types, methods and ",
                "compiled code, which the walk counts and does not walk into.")
    if !isempty(report.holders)
        println(io, "\nThe holders that keep the most, largest first:")
        for holder in report.holders
            println(io, lpad(_format_byte_count(holder.bytes), 11), lpad(holder.object_count, 10), " objects  ",
                    isempty(holder.path) ? "(the root)" : holder.path, "  ", _get_type_name(holder.type))
        end
    end
    if !isempty(report.types)
        println(io, "\nThe types with the most bytes:")
        for type in first(report.types, 15)
            println(io, lpad(_format_byte_count(type.bytes), 11), lpad(type.object_count, 10), " objects  ",
                    _get_type_name(type.type))
        end
    end
    print(io, "\nThe walk needed ", _format_byte_count(report.walk_bytes), " for its tables.")
end

"""
    describe_held_memory(; editor = get_evaluation_editor()) -> String

**What holds the memory of the editor**, as text: the bytes that the editor
reaches, the holders that keep the most of them with the path of each from the
editor, and the types with the most bytes. It is the report of
[`compute_held_memory`](@ref) for the editor.

Use it to answer why the editor needs so much memory, or what keeps it. Run it
only when the person asks: the walk holds the window for its time, some seconds
for a large editor, and it needs about 100 bytes of memory for each object that
the editor reaches, so a few GB for a large editor.

# Example

    println(describe_held_memory())

See also `describe_undo_history`, the changes that the history of the window keeps.

For the assistant.
"""
function describe_held_memory end

function describe_held_memory(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "describe_held_memory") do
        sprint(show, MIME"text/plain"(), compute_held_memory(editor))
    end
end
