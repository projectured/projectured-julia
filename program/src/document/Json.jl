"""
    JsonModule

The JSON document domain provides reactive representations of JSON data structures.
Every JSON value is a Document with all mutable fields wrapped in reactive Cells,
enabling automatic dependency tracking and incremental updates.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonInsertion` for cursor positioning
- **Conversion**: `jsonvalue` converts plain Julia values to JSON documents

Primitive values expose their content through a single cell, while compound values
hold their children in a `CellVector` so structural changes (insertions, deletions)
invalidate only the affected container while leaving siblings intact.

Selection semantics:
- Primitives: `.value[k]` — character offset within the rendered text
- Arrays: `.elements[i]` — cursor within element i
- Objects: `.entries[i]` — cursor within entry i, then `.key[k]` or `.value` for key/value
"""
module JsonModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, PositionReference, RangeReference, FieldReference, EmptyReferencePath
import ..OperationApiModule: _apply_string_replace!, _apply_number_replace!
export JsonDocument, JsonInsertion, JsonForeign, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, jsonvalue, entries, setfn!,
       IJsonInsertion, IJsonForeign, IJsonNull, IJsonBool, IJsonNumber, IJsonString, IJsonArray, IJsonObject, IJsonObjectEntry

"""
    JsonDocument

Abstract base type for all JSON document types. Every concrete JSON type
subtypes `JsonDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type JsonDocument <: Document end

# ── Insertion cursor ─────────────────────────────────────────────────────

"""
    JsonInsertion

Represents an insertion cursor position in a JSON document. Used by the
editor to indicate where new content should be inserted.

# Fields

- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct JsonInsertion <: JsonDocument
    value::Any
    selection::Reference
end

JsonInsertion() = JsonInsertion(Cell(nothing), Cell(nothing))

@document struct JsonForeign <: JsonDocument
    value::Any
    selection::Reference
end
JsonForeign(value) = JsonForeign(Cell(value), Cell(nothing))

# ── Primitives ───────────────────────────────────────────────────────────

"""
    JsonNull

Represents the JSON `null` value. Selection semantics: `.value[k]` refers
to character k within the rendered text "null".

# Fields

- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct JsonNull <: JsonDocument
    selection::Reference
end

JsonNull() = JsonNull(Cell(nothing))

"""
    JsonBool

Represents a JSON boolean value (`true` or `false`). Selection semantics:
`.value[k]` refers to character k of the boolean text.

# Fields

- `value::Cell` — holds the `Bool` value
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `JsonBool(v::Bool)` — primitive cell with value `v`
- `JsonBool(f::Function)` — computed cell with thunk `f`
"""
@document struct JsonBool <: JsonDocument
    value::Bool
    selection::Reference
end

JsonBool(v::Bool) = JsonBool(Cell(v), Cell(nothing))
JsonBool(f::Function) = JsonBool(Cell(f), Cell(nothing))

"""
    JsonNumber

Represents a JSON number value. Selection semantics: `.value[k]` refers to
character k of the number text.

# Fields

- `value::Cell` — holds the numeric value (any `Real` type)
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `JsonNumber(v::Real)` — primitive cell with value `v`
- `JsonNumber(f::Function)` — computed cell with thunk `f`
"""
@document struct JsonNumber <: JsonDocument
    value::Real
    selection::Reference
end

JsonNumber(v::Real) = JsonNumber(Cell(v), Cell(nothing))
JsonNumber(f::Function) = JsonNumber(Cell(f), Cell(nothing))

"""
    JsonString

Represents a JSON string value. Selection semantics: `.value[k]` refers to
character k of the string value (excluding quotes).

# Fields

- `value::Cell` — holds the `String` value
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `JsonString(v::AbstractString)` — primitive cell with value `v`
- `JsonString(f::Function)` — computed cell with thunk `f`
"""
@document struct JsonString <: JsonDocument
    value::String
    selection::Reference
end

JsonString(v::AbstractString) = JsonString(Cell(v), Cell(nothing))
JsonString(f::Function) = JsonString(Cell(f), Cell(nothing))

# ── Compounds ────────────────────────────────────────────────────────────

"""
    JsonArray

Represents a JSON array (ordered list of values). Selection semantics:
`.elements[i]` refers to cursor within element i. Supports standard array
operations like indexing, push, insert, delete, sort, and reverse.

# Fields

- `elements::CellVector` — holds the array elements as reactive cells
- `collapsed::Cell` — holds `Bool` indicating if array is collapsed in UI
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `JsonArray()` — empty array
- `JsonArray(items::Vector{<:JsonDocument}) — array with initial items
- `JsonArray(items::JsonDocument...)` — array from variadic items
"""
@document struct JsonArray <: JsonDocument
    elements::CellVector
    collapsed::Bool
    selection::Reference
end

JsonArray() = JsonArray(CellVector(), Cell(false), Cell(nothing))
JsonArray(items::Vector{<:JsonDocument}) =
    JsonArray(CellVector(Cell[Cell(x) for x in items]), Cell(false), Cell(nothing))
JsonArray(items::JsonDocument...) =
    JsonArray(CellVector(Cell[Cell(x) for x in items]), Cell(false), Cell(nothing))

"""
    JsonObjectEntry

Represents a single key-value entry in a JSON object. Selection semantics:
`.key[k]` refers to character k of the key, `.value` refers to cursor within
the value document.

# Fields

- `key::String` — the entry key
- `value::Cell` — holds the value (any `Document` type)
- `collapsed::Cell` — holds `Bool` indicating if entry is collapsed in UI
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructor

- `JsonObjectEntry(key::AbstractString, value)` — creates entry with key and value
"""
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool
    selection::Reference
end

JsonObjectEntry(key::AbstractString, value) =
    JsonObjectEntry(String(key), Cell(value isa Document ? value : jsonvalue(value)), Cell(false), Cell(nothing))

"""
    JsonObject

Represents a JSON object (unordered collection of key-value pairs). Selection
semantics: `.entries[i]` refers to cursor within entry i. Supports dictionary-like
operations: `haskey`, `keys`, `values`, `getindex`, `setindex!`, `delete!`, `get`.

# Fields

- `entries::CellVector` — holds the object entries as reactive cells
- `collapsed::Cell` — holds `Bool` indicating if object is collapsed in UI
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `JsonObject()` — empty object
- `JsonObject(f::Function)` — object with entries produced by thunk `f`
- `JsonObject(pairs::Pair{<:AbstractString}...)` — object from key-value pairs
"""
@document struct JsonObject <: JsonDocument
    entries::CellVector
    collapsed::Bool
    selection::Reference
end

JsonObject() = JsonObject(CellVector(), Cell(false), Cell(nothing))
function JsonObject(f::Function)
    cv = CellVector(f)
    JsonObject(cv, Cell(false), Cell(nothing))
end

function JsonObject(pairs::Pair{<:AbstractString}...)
    cv = CellVector()
    for (k, v) in pairs
        push!(cv, Cell(JsonObjectEntry(String(k), v)))
    end
    JsonObject(cv, Cell(false), Cell(nothing))
end

# ── Conversion from plain Julia ─────────────────────────────────────────

"""
    jsonvalue(x)

Convert a plain Julia value into the corresponding `JsonDocument`.
Provides automatic conversion from Julia types to JSON representation.

# Conversions

- `JsonDocument` → returned unchanged
- `Nothing` → `JsonNull()`
- `Bool` → `JsonBool(v)`
- `Real` → `JsonNumber(v)`
- `AbstractString` → `JsonString(v)`
- `AbstractVector` → `JsonArray` with converted elements
- `AbstractDict` → `JsonObject` with converted key-value pairs
"""
jsonvalue(j::JsonDocument) = j
jsonvalue(::Nothing) = JsonNull()
jsonvalue(v::Bool) = JsonBool(v)
jsonvalue(v::Real) = JsonNumber(v)
jsonvalue(v::AbstractString) = JsonString(v)
jsonvalue(v::AbstractVector) = JsonArray(JsonDocument[jsonvalue(x) for x in v])
function jsonvalue(d::AbstractDict)
    cv = CellVector(Cell[Cell(JsonObjectEntry(string(k), jsonvalue(v))) for (k, v) in d])
    JsonObject(cv, Cell(false), Cell(nothing))
end

# ── Primitive read / write ───────────────────────────────────────────────

Base.getindex(::JsonNull) = nothing
Base.getindex(j::JsonBool)   = j.value::Bool
Base.getindex(j::JsonNumber) = j.value
Base.getindex(j::JsonString) = j.value::AbstractString

Base.setindex!(j::JsonBool,   v::Bool)          = (j.value = v)
Base.setindex!(j::JsonNumber, v::Real)          = (j.value = v)
Base.setindex!(j::JsonString, v::AbstractString) = (j.value = v)

# ── Switch cell to computation ───────────────────────────────────────────

setfn!(j::JsonBool,   f::Function) = (setfn!(getfield(j, :value),    f); j)
setfn!(j::JsonNumber, f::Function) = (setfn!(getfield(j, :value),    f); j)
setfn!(j::JsonString, f::Function) = (setfn!(getfield(j, :value),    f); j)
# setfn! for JsonArray is not supported with CellVector backing
setfn!(j::JsonObject, f::Function) = (setfn!(getfield(j.entries, :elements), () -> Cell[Cell(x) for x in f()]); j)
setval!(j::Union{JsonBool, JsonNumber, JsonString}, v) = (setval!(getfield(j, :value), v); j)

# ── Array internals ─────────────────────────────────────────────────────

_items(j::JsonArray) = j.elements   # CellVector

Base.length(j::JsonArray) = length(j.elements)
Base.size(j::JsonArray) = (length(j),)
Base.firstindex(j::JsonArray) = 1
Base.lastindex(j::JsonArray) = length(j)
Base.iterate(j::JsonArray, state...) = iterate(j.elements, state...)
Base.eachindex(j::JsonArray) = eachindex(j.elements)
Base.isempty(j::JsonArray) = isempty(j.elements)

Base.getindex(j::JsonArray, i::Integer) = j.elements[i]

function Base.setindex!(j::JsonArray, v, i::Integer)
    j.elements[i] = v isa JsonDocument ? v : jsonvalue(v)
    return v
end

function Base.push!(j::JsonArray, vs...)
    for v in vs
        push!(j.elements, Cell(v isa JsonDocument ? v : jsonvalue(v)))
    end
    return j
end

function Base.deleteat!(j::JsonArray, i)
    deleteat!(j.elements, i)
    return j
end

function Base.insert!(j::JsonArray, i::Integer, v)
    doc = v isa JsonDocument ? v : jsonvalue(v)
    insert!(j.elements, i, Cell(doc))
    return j
end

function Base.pop!(j::JsonArray)
    return pop!(j.elements)
end

Base.reverse(j::JsonArray) =
    JsonArray(CellVector(reverse(j.elements.elements)), getfield(j, :collapsed), Cell(nothing))

Base.sort(j::JsonArray; by=identity, lt=isless, rev=false) =
    JsonArray(sort(j.elements; by=by, lt=lt, rev=rev), getfield(j, :collapsed), Cell(nothing))

# ── Object internals ──────────────────────────────────────────────────────

"""
    entries(j::JsonObject)

Return the `CellVector` containing the object's entries. This is the underlying
storage for the object's key-value pairs.
"""
entries(j::JsonObject) = j.entries   # CellVector

Base.length(j::JsonObject)  = length(j.entries)
Base.isempty(j::JsonObject) = isempty(j.entries)

function Base.haskey(j::JsonObject, key::AbstractString)
    any(e -> e.key == key, j.entries)
end

Base.keys(j::JsonObject)   = [e.key    for e in j.entries]
Base.values(j::JsonObject) = [e.value for e in j.entries]

function Base.iterate(j::JsonObject, state=1)
    state > length(j.entries) && return nothing
    e = j.entries[state]
    return ((e.key, e.value), state + 1)
end

function Base.getindex(j::JsonObject, key::AbstractString)
    for e in j.entries
        e.key == key && return e.value
    end
    throw(KeyError(key))
end

function Base.setindex!(j::JsonObject, v, key::AbstractString)
    val = v isa JsonDocument ? v : jsonvalue(v)
    for i in eachindex(j.entries)
        e = j.entries[i]
        if e.key == key
            j.entries[i] = JsonObjectEntry(e.key, Cell(val), getfield(e, :collapsed), getfield(e, :selection))
            return v
        end
    end
    push!(j.entries, Cell(JsonObjectEntry(String(key), val)))
    return v
end

function Base.delete!(j::JsonObject, key::AbstractString)
    for i in length(j.entries):-1:1
        j.entries[i].key == key && deleteat!(j.entries, i)
    end
    return j
end

function Base.get(j::JsonObject, key::AbstractString, default)
    for e in j.entries
        e.key == key && return e.value
    end
    return default
end

# ── String / number replace operations ──────────────────────────────────

function _apply_string_replace!(target::JsonString, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "value" || error("JsonString supports only field 'value', got: $field_name")
    old = something(target.value, "")
    target.value = _slice_replace(old, s, e, replacement)
end

function _apply_string_replace!(target::JsonObjectEntry, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "key" || error("JsonObjectEntry supports only field 'key', got: $field_name")
    old = something(target.key, "")
    target.key = _slice_replace(old, s, e, replacement)
end

function _apply_number_replace!(target::JsonNumber, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "value" || error("JsonNumber supports only field 'value', got: $field_name")
    old_num = target.value
    old_str = old_num === nothing ? "" : string(old_num)
    new_str = _slice_replace(old_str, s, e, replacement)
    target.value = isempty(new_str) ? nothing : something(tryparse(Float64, new_str), nothing)
end

# Character-aware replacement helper (positions are 0-based char offsets).
function _slice_replace(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

# ── Display ──────────────────────────────────────────────────────────────

Base.show(io::IO, ::JsonNull) = print(io, "null")
Base.show(io::IO, j::JsonBool) = print(io, j[] ? "true" : "false")
Base.show(io::IO, j::JsonNumber) = print(io, j[])
Base.show(io::IO, j::JsonString) = show(io, j[])

function Base.show(io::IO, j::JsonArray)
    items = _items(j)
    print(io, "[")
    for (i, item) in enumerate(items)
        i > 1 && print(io, ", ")
        show(io, item)
    end
    print(io, "]")
end

function Base.show(io::IO, j::JsonObject)
    print(io, "{")
    first = true
    for e in j.entries
        first || print(io, ", ")
        first = false
        show(io, e.key)
        print(io, ": ")
        show(io, e.value)
    end
    print(io, "}")
end

end # module
