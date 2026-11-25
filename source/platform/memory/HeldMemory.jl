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
  string, a symbol or a number, `["name"]`, and otherwise the place of the entry
  with the type of its key, `[#5 JsonObject]`; its key adds `.key`. The empty path
  is the root.
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
    holder_list = MemoryHolder[MemoryHolder(_describe_object_path(graph, number),
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

# The path from the root to the object `number`, along the objects that the walk
# reached each object from first.
function _describe_object_path(graph::_MemoryGraph, number::Integer)
    chain = Int32[]
    while number != 0
        push!(chain, number)
        number = graph.parents[number]
    end
    reverse!(chain)
    path = IOBuffer()
    for place in 2:length(chain)
        above = place > 2 ? graph.objects[chain[place - 2]] : nothing
        print(path, _describe_step(graph.objects[chain[place - 1]], graph.objects[chain[place]], above))
    end
    String(take!(path))
end

# The step from `parent` to `child`; `above` is the object that the walk reached
# `parent` from, or `nothing`. A cell, a box of a captured variable, a list, a
# dictionary and the memory that holds their elements give one step together.
function _describe_step(@nospecialize(parent), @nospecialize(child), @nospecialize(above))
    (parent isa AbstractCell || parent isa Core.Box || parent isa Array || parent isa Dict ||
     parent isa IdDict) && return ""
    parent isa GenericMemory && return _describe_memory_step(parent, child, above)
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
        step = name isa Symbol ? "." * String(name) : "[" * string(name) * "]"
        if !Base.allocatedinline(declared)
            getfield(x, field) === child && return step
        elseif declared isa DataType && !Base.datatype_pointerfree(declared)
            inner = _find_field_step(getfield(x, field), child)
            inner === nothing || return step * inner
        end
    end
    nothing
end

function _describe_memory_step(@nospecialize(memory::GenericMemory), @nospecialize(child), @nospecialize(above))
    (index, inner) = _find_memory_place(memory, child)
    index == 0 && return "[?]"
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

# The index of the element of `memory` that is `child` or points to it, and the
# fields from that element to `child`; `(0, "")` when no element does.
function _find_memory_place(@nospecialize(memory::GenericMemory), @nospecialize(child))
    inline = Base.allocatedinline(eltype(memory))
    for index in 1:length(memory)
        isassigned(memory, index) || continue
        element = memory[index]
        if !inline
            element === child && return (index, "")
        else
            inner = _find_field_step(element, child)
            inner === nothing || return (index, inner)
        end
    end
    (0, "")
end

# The words of the entry of `dict` at the place `index` of its table.
function _describe_dict_entry(dict::Dict, index::Integer)
    key = dict.keys[index]
    _is_plain_key(key) && return _format_plain_key(key)
    place = count(slot -> Base.isslotfilled(dict, slot), 1:index)
    "#" * string(place) * " " * _get_type_name(typeof(key))
end

# The words of the entry of an `IdDict` whose key is at `index` of its table.
function _describe_id_dict_entry(@nospecialize(table::GenericMemory), index::Integer)
    key = table[index]
    _is_plain_key(key) && return _format_plain_key(key)
    place = count(slot -> isassigned(table, slot), 1:2:index)
    "#" * string(place) * " " * _get_type_name(typeof(key))
end

_is_plain_key(@nospecialize(key)) = key isa Union{AbstractString, Symbol, Number, Char}

function _format_plain_key(@nospecialize(key))
    text = repr(key)
    length(text) > 40 ? first(text, 39) * "…" : text
end

# The name of `type` with the names of its parameters, without their modules.
function _get_type_name(@nospecialize(type))
    type isa DataType || return string(type)
    name = string(nameof(type))
    isempty(type.parameters) && return name
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

Use it when the person asks why the editor needs so much memory, or what keeps
it. Run it only when the person asks: the walk holds the window for its time,
some seconds for a large editor, and it needs about 100 bytes of memory for each
object that the editor reaches, so a few GB for a large editor.

# Example

    println(describe_held_memory())

For the assistant.
"""
function describe_held_memory end

function describe_held_memory(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "describe_held_memory") do
        sprint(show, MIME"text/plain"(), compute_held_memory(editor))
    end
end
