"""
    JsonModule

The JSON document domain.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonInsertion` for cursor positioning
"""
module JsonModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document, @forward_vector, @forward_map
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, PositionReference, RangeReference, FieldReference, EmptyReferencePath, evaluate_reference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: replace_document, insert_elements, ReplaceSelectionOperation
import ..DocumentApiModule: with_selection
import ..KeyboardModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
export JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, entries,
       IJsonInsertion, IJsonNull, IJsonBool, IJsonNumber, IJsonString, IJsonArray, IJsonObject, IJsonObjectEntry

abstract type JsonDocument <: Document end

# ── Insertion cursor ─────────────────────────────────────────────────────

@document struct JsonInsertion <: JsonDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Primitives ───────────────────────────────────────────────────────────

@document struct JsonNull <: JsonDocument
    selection::Reference = nothing
end

@document struct JsonBool <: JsonDocument
    value::Bool
    selection::Reference = nothing
end

@document struct JsonNumber <: JsonDocument
    value::Union{Real, Nothing}
    selection::Reference = nothing
end

@document struct JsonString <: JsonDocument
    value::String
    selection::Reference = nothing
end

# ── Compounds ────────────────────────────────────────────────────────────

@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector JsonArray elements

@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool = false
    selection::Reference = nothing
end    

@document struct JsonObject <: JsonDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end    

@forward_map JsonObject entries key value JsonObjectEntry

function JsonObject(pairs::Pair{<:AbstractString}...)
    cv = CellVector()
    for (k, v) in pairs
        push!(cv, Cell(JsonObjectEntry(String(k), v)))
    end    
    JsonObject(cv, Cell(false), Cell(nothing))
end    

# Text/number replace edits need no per-type method: `JsonString.value` and
# `JsonObjectEntry.key` are plain strings, and `JsonNumber.value` is a number
# reparsed from its text representation.

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# The JSON authoring command set: type a printable key on a whole JSON value to
# replace it, `,` to insert an element/entry, Tab to move from a key to its value.
# Gestures are root-relative: each reads `doc`'s own selection and emits a
# `doc`-relative operation that resolves to the actual (possibly nested) target.

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
    KeyPress('{') => "Replace with an object" => _replace(doc, with_selection(JsonObject([JsonObjectEntry("", JsonInsertion())]), @reference entries[1].key{0}))
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
