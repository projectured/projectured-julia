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

@forward_vector_protocol on JsonArray to elements

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

@adapt_map_protocol on JsonObject to entries with JsonObjectEntry(key, value)

JsonObject(pairs::Pair{<:AbstractString}...) =
    JsonObject([JsonObjectEntry(String(k), v) for (k, v) in pairs])

# An object entry must stay a key/value pair — it is retyped through its value.
_json_replaceable(doc, sel) =
    !(try_evaluate_reference(doc, named_node_reference(sel)) isa Union{Nothing, JsonObjectEntry})

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion JsonBool        = @with_selection JsonBool(false)
@insertion JsonNumber      = @with_selection JsonNumber(nothing)
@insertion JsonString      = @with_selection JsonString("") value{0}
@insertion JsonArray       = @with_selection JsonArray([JsonInsertion()]) elements[1]
@insertion JsonObjectEntry = @with_selection JsonObjectEntry("", JsonInsertion()) key{0}
@insertion JsonObject      = @with_selection JsonObject([JsonObjectEntry("", JsonInsertion())]) entries[1].key{0}

@gestures JsonDocument begin
    when(_json_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => replace_selected_document(doc, @with_selection JsonNull())
    KeyPress('f') => "Replace with false"  => replace_selected_document(doc, make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => replace_selected_document(doc, @with_selection JsonBool(true))
    KeyPress('"') => "Replace with a string" => replace_selected_document(doc, make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => replace_selected_document(doc, make_insertion_document(JsonArray))
    KeyPress(':') => "Replace with an object entry" => replace_selected_document(doc, make_insertion_document(JsonObjectEntry))
    KeyPress('{') => "Replace with an object" => replace_selected_document(doc, make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        replace_selected_document(doc, @with_selection JsonNumber(parse(Int, string(c))) value{1})
end

@gestures JsonArray begin
    KeyPress(',') => "Insert a new element" => append_insertion_operation(doc, :elements, JsonInsertion)
end

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, JsonObjectEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc, :key, :value)
end

end # module
