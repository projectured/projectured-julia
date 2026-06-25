"""
    JsonModule

The JSON document domain provides reactive representations of JSON data structures.
Every JSON value is a Document with all mutable fields wrapped in reactive Cells,
enabling automatic dependency tracking and incremental updates.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonInsertion` for cursor positioning

Primitive values expose their content through a single cell, while compound values
hold their children in a `CellVector` so structural changes (insertions, deletions)
invalidate only the affected container while leaving siblings intact.

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Primitives: `.value{k}` — cursor at boundary k of the rendered text; `.value[i]` its i-th character
- Arrays: `.elements[i]` — the i-th element; `.elements{k}` — cursor between elements
- Objects: `.entries[i]` — the i-th entry, then `.key{k}` (cursor in the key) or `.value` (the value document)
"""
module JsonModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, PositionReference, RangeReference, FieldReference, EmptyReferencePath, evaluate_reference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: replace_document, insert_elements, ReplaceSelectionOperation
import ..DocumentApiModule: with_selection
import ..KeyboardModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
export JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, entries, setfn!,
       IJsonInsertion, IJsonNull, IJsonBool, IJsonNumber, IJsonString, IJsonArray, IJsonObject, IJsonObjectEntry

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
"""
@document struct JsonInsertion <: JsonDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Primitives ───────────────────────────────────────────────────────────

"""
    JsonNull

Represents the JSON `null` value. Selection semantics: `.value{k}` is the
cursor at boundary k of the rendered text "null" (0-based).
"""
@document struct JsonNull <: JsonDocument
    selection::Reference = nothing
end

"""
    JsonBool

Represents a JSON boolean value (`true` or `false`). Selection semantics:
`.value{k}` is the cursor at boundary k of the boolean text (0-based).
"""
@document struct JsonBool <: JsonDocument
    value::Bool
    selection::Reference
end

JsonBool(v::Bool) = JsonBool(Cell(v), Cell(nothing))
JsonBool(f::Function) = JsonBool(Cell(f), Cell(nothing))

"""
    JsonNumber

Represents a JSON number value. The value becomes `nothing` once the text is
emptied. Selection semantics: `.value{k}` is the cursor at boundary k of the
number text (0-based); `.value[i]` is its i-th character.
"""
@document struct JsonNumber <: JsonDocument
    value::Union{Real, Nothing}
    selection::Reference
end

JsonNumber(v::Real) = JsonNumber(Cell(v), Cell(nothing))
JsonNumber(f::Function) = JsonNumber(Cell(f), Cell(nothing))

"""
    JsonString

Represents a JSON string value. Selection semantics: `.value{k}` is the cursor
at boundary k of the string value (0-based, excluding quotes); `.value[i]` is
its i-th character.
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
`.elements[i]` refers to cursor within element i. A `JsonArray` is *not* itself a
collection; mutate it through its `elements` CellVector
(`push!(arr.elements, x)`, `insert!(arr.elements, i, x)`, `deleteat!(arr.elements, i)`).
"""
@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end
JsonArray(items::Vector{<:JsonDocument}) =
    JsonArray(CellVector(Cell[Cell(x) for x in items]), Cell(false), Cell(nothing))
JsonArray(items::JsonDocument...) =
    JsonArray(CellVector(Cell[Cell(x) for x in items]), Cell(false), Cell(nothing))

"""
    JsonObjectEntry

Represents a single key-value entry in a JSON object. Selection semantics:
`.key{k}` is the cursor at boundary k of the key (0-based), `.value` descends
into the value document.
"""
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool
    selection::Reference
end

JsonObjectEntry(key::AbstractString, value::Document) =
    JsonObjectEntry(String(key), Cell(value), Cell(false), Cell(nothing))

"""
    JsonObject

Represents a JSON object (unordered collection of key-value pairs). Selection
semantics: `.entries[i]` refers to cursor within entry i. Supports dictionary-like
operations: `haskey`, `keys`, `values`, `getindex`, `setindex!`, `delete!`, `get`.
"""
@document struct JsonObject <: JsonDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end
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
#
# JsonArray is not a collection: mutate it through its `elements` CellVector
# (`push!(j.elements, x)`, `insert!(j.elements, i, x)`, `deleteat!(j.elements, i)`).
# Only the reference-indexing methods live here, because the JSON reference
# convention indexes the array directly (no `.elements` field step).

Base.size(j::JsonArray) = (length(j.elements),)

# Needed by evaluate_reference when a PositionReference navigates directly into
# a JsonArray (e.g. FocusingProjection with part=ReferencePath(PositionReference(n))).
Base.getindex(j::JsonArray, i::Integer) = j.elements[i]

# ── Object internals ──────────────────────────────────────────────────────

"""
    entries(j::JsonObject)

Return the `CellVector` containing the object's entries. This is the underlying
storage for the object's key-value pairs.
"""
entries(j::JsonObject) = j.entries   # CellVector

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

function Base.setindex!(j::JsonObject, v::Document, key::AbstractString)
    val = v
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

# Text/number replace edits are handled generically by `splice_value!` (see
# OperationApiModule): `JsonString.value` and `JsonObjectEntry.key` are plain
# strings (string representation); `JsonNumber.value` is a number (a string-domain
# edit threaded through a parent array/object reader reparses it via the number
# representation). No per-type method is needed.

# ── Authoring gestures (the projection-independent JSON reader) ─────────────
#
# The JSON authoring command set, declared as reified `@gestures` on the document
# types so it both *fires* operations and is *enumerable* by the gesture-help
# projection. Relocated from `JsonToSyntaxModule` (where it was duplicated across
# the leaf readers); the generic event fallback in `projection_read` now routes a
# raw key on a JSON value here via `document_read`. Only the structural
# flat-offset reader (delimiters/brackets/commas with no JSON pre-image) stays in
# the projection, since it is genuinely projection-specific.
#
# These are *root-relative*: each JSON projection works as the whole document, so
# the gesture reads `doc`'s own selection and emits a `doc`-relative operation.
# `evaluate_reference(doc, sel)` resolves the actual edit target (which may be a
# nested element). Modifiers are not matched on a `KeyPress` — the OS folds Shift
# into the character and Ctrl-combinations never produce text input — so the old
# defensive `ctrl` guard is dropped.

# Replace the currently-selected value with `newdoc` (whose cursor is pre-placed
# via `with_selection`).
_replace(doc, newdoc) = replace_document(getfield(doc, :selection)[], newdoc)

# A character cursor: a path ending in value{k} or key{k} (a RangeReference after a
# value/key field). A whole-element selection ends in ∅.
function _is_char_cursor(sel)
    prev = nothing
    cur = sel
    while cur isa ConcreteReferencePath
        if cur.tail isa EmptyReferencePath
            return cur.head isa RangeReference && prev isa FieldReference &&
                   (prev.name == "value" || prev.name == "key")
        end
        prev = cur.head
        cur = cur.tail
    end
    return false
end

# Block precondition for the type-to-replace set: a whole JSON value (not a
# character cursor) whose target exists and is replaceable (values / array
# elements / root — not a key/value entry wrapper).
function _json_replaceable(doc, sel)
    sel === nothing && return false
    _is_char_cursor(sel) && return false
    target = try evaluate_reference(doc, sel) catch; nothing end
    target === nothing && return false
    target isa JsonObjectEntry && return false
    return true
end

# A digit builds a fresh number, unless a whole number is already selected (that
# edit belongs to the typein path, which appends digits to the existing value).
function _replace_number(doc, c)
    target = try evaluate_reference(doc, getfield(doc, :selection)[]) catch; nothing end
    target isa JsonNumber && return nothing
    _replace(doc, with_selection(JsonNumber(parse(Int, string(c))), @reference value{1}))
end

# Append a JsonInsertion and select it whole, ready to type-to-replace.
function _array_insert(doc::JsonArray)
    n = length(doc.elements)
    insert_elements(@reference(elements), n, Any[JsonInsertion()],
                    @reference elements[n + 1])
end

# Append an empty entry and select its key for typing.
function _object_insert(doc::JsonObject)
    n = length(doc.entries)
    insert_elements(@reference(entries), n,
                    Any[JsonObjectEntry("", JsonInsertion())],
                    @reference entries[n + 1].key{0})
end

# Tab moves the cursor from an entry's key to its value, selected whole.
function _object_tab(doc::JsonObject)
    sel = getfield(doc, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        entries{s:e}.rest... => begin
            i = s + 1
            @reference_case rest begin
                key.inner... => ReplaceSelectionOperation(@reference entries[i].value)
            end
        end
    end
end

# Shared type-to-replace set: a printable key on a whole JSON value replaces it
# with a freshly-built value whose cursor is pre-placed for continued authoring.
@gestures JsonDocument begin
    when(_json_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => _replace(doc, with_selection(JsonNull(), EmptyReferencePath()))
    KeyPress('f') => "Replace with false"  => _replace(doc, with_selection(JsonBool(false), EmptyReferencePath()))
    KeyPress('t') => "Replace with true"   => _replace(doc, with_selection(JsonBool(true), EmptyReferencePath()))
    KeyPress('"') => "Replace with a string" => _replace(doc, with_selection(JsonString(""), @reference value{0}))
    KeyPress('[') => "Replace with an array" => _replace(doc, with_selection(JsonArray([JsonInsertion()]), @reference elements[1]))
    KeyPress(':') => "Replace with an object entry" => _replace(doc, with_selection(JsonObjectEntry("", JsonInsertion()), @reference key{0}))
    KeyPress('{') => "Replace with an object" => _replace(doc, with_selection(JsonObject(() -> [JsonObjectEntry("", JsonInsertion())]), @reference entries[1].key{0}))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" => _replace_number(doc, c)
end

# Arrays add `,`-insert; objects add `,`-insert and Tab (key → value). Both
# inherit the type-to-replace set from JsonDocument.
@gestures JsonArray begin
    KeyPress(',') => "Insert a new element" => _array_insert(doc)
end

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => _object_insert(doc)
    KeyDown(:tab) => "Move from key to value" => _object_tab(doc)
end

end # module
