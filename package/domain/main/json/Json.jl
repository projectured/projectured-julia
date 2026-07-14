"""
    JsonModule

The JSON document domain.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonNothing` for an empty document, `JsonInsertion` for cursor positioning
"""
module JsonModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

export entries

@domain Json

# ── Primitives ───────────────────────────────────────────────────────────

"""
The JSON `null` literal.
"""
@document struct JsonNull <: JsonDocument
end

"""
A JSON boolean literal (`true` or `false`).
"""
@document struct JsonBool <: JsonDocument
    value::Bool
end

"""
A JSON number literal. `value` may be `nothing` while its text has been fully deleted.
"""
@document struct JsonNumber <: JsonDocument
    value::Union{Real, Nothing}
end

"""
A JSON string literal.
"""
@document struct JsonString <: JsonDocument
    value::String
end

# ── Compounds ────────────────────────────────────────────────────────────

"""
A JSON array `[…]`. `collapsed` hides its elements behind a marker in the projection.
"""
@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector JsonArray elements

"""
One `"key": value` member of a JSON object.
"""
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool = false
end    

"""
A JSON object `{…}` — an ordered sequence of `JsonObjectEntry` members.
`collapsed` hides them in the projection.
"""
@document struct JsonObject <: JsonDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
end    

@forward_map JsonObject entries key value JsonObjectEntry

# build an object from `key => value` pairs
JsonObject(pairs::Pair{<:AbstractString}...) =
    JsonObject([JsonObjectEntry(String(k), v) for (k, v) in pairs])

# Text/number replace edits need no per-type method: `JsonString.value` and
# `JsonObjectEntry.key` are plain strings, and `JsonNumber.value` is a number
# reparsed from its text representation.

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# The JSON authoring command set: type a printable key on a whole JSON value to
# replace it, `,` to insert an element/entry, Tab to move from a key to its value.
# Gestures are root-relative: each reads `doc`'s own selection and emits a
# `doc`-relative operation that resolves to the actual (possibly nested) target.
#
# A gesture here fires only on a key the *output* layers left unclaimed — the
# reader runs last-to-first, so a printable key that the text layer turned into a
# character edit never reaches the domain. That is why nothing below asks whether
# the caret sits inside a string: if it does, `,` was already a comma.

# Replace the currently-selected value with `newdoc` (whose cursor is pre-placed via
# `with_selection`).
_replace(doc, newdoc) =
    replace_document(named_node_reference(getfield(doc, :selection)[]), newdoc)

# Block precondition for the type-to-replace set: the caret names a whole JSON
# value whose target exists and is replaceable (values / array elements / root —
# not a key/value entry wrapper).
function _json_replaceable(doc, sel)
    sel === nothing && return false
    # An introduced caret names the focused node. Enable type-to-replace there for a
    # `JsonInsertion` placeholder or a container (you are on its bracket / brace), but
    # not on a concrete scalar's own quotes / keyword — a whole-element selection is
    # the way to retype an existing value.
    if is_introduced_reference(sel)
        return doc isa JsonInsertion || doc isa JsonArray || doc isa JsonObject
    end
    target = try_evaluate_reference(doc, sel)
    target === nothing && return false
    return !(target isa JsonObjectEntry)
end

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion JsonBool        = @with_selection JsonBool(false)
# An empty number's value is `nothing`, which has no text position, so it is selected
# whole; an empty string is `""` and does have position 0.
@insertion JsonNumber      = @with_selection JsonNumber(nothing)
@insertion JsonString      = @with_selection JsonString("") value{0}
@insertion JsonArray       = @with_selection JsonArray([JsonInsertion()]) elements[1]
@insertion JsonObjectEntry = @with_selection JsonObjectEntry("", JsonInsertion()) key{0}
@insertion JsonObject      = @with_selection JsonObject([JsonObjectEntry("", JsonInsertion())]) entries[1].key{0}

@gestures JsonDocument begin
    when(_json_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => _replace(doc, @with_selection JsonNull())
    KeyPress('f') => "Replace with false"  => _replace(doc, make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => _replace(doc, @with_selection JsonBool(true))
    KeyPress('"') => "Replace with a string" => _replace(doc, make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => _replace(doc, make_insertion_document(JsonArray))
    KeyPress(':') => "Replace with an object entry" => _replace(doc, make_insertion_document(JsonObjectEntry))
    KeyPress('{') => "Replace with an object" => _replace(doc, make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        _replace(doc, @with_selection JsonNumber(parse(Int, string(c))) value{1})
end

@gestures JsonArray begin
    KeyPress(',') => "Insert a new element" => append_insertion_operation(doc, :elements, JsonInsertion)
end

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, JsonObjectEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc, :key, :value)
end

end # module
