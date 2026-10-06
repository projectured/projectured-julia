# Fragment of `JsonModule` — the JSON document types, the document each
# insertion starts from, and the gestures that edit them.
#
# `@domain Json` declares the abstract `JsonDocument` type that every type below
# subtypes, and generates `JsonNothing` and `JsonInsertion`.

@domain Json

# ── Primitives ───────────────────────────────────────────────────────────

"""
The JSON `null` literal. It holds no value.
"""
@document struct JsonNull <: JsonDocument
end

"""
A JSON boolean literal. `value` is `true` or `false`.
"""
@document struct JsonBool <: JsonDocument
    value::Bool
end

"""
A JSON number literal. `value` is the number, or `nothing` while its text is empty.
"""
@document struct JsonNumber <: JsonDocument
    value::Union{Real, Nothing}
end

"""
A JSON string literal. `value` is the `String`.
"""
@document struct JsonString <: JsonDocument
    value::String
end

# ── Compounds ────────────────────────────────────────────────────────────

"""
A JSON array `[…]`. `elements` holds its values, each a JSON document. The array acts
as a vector of them: `array[1]`, `length(array)`, `for element in array`.
`collapsed` hides the elements behind a marker in the projection.

Use it to read the items of a JSON list, for example the records of a JSON file
that holds an array of objects.

# Example

    for item in items                 # each element, here a `JsonObject`
        println(item["name"].value)
    end
"""
@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on JsonArray to elements

"""
One `"key": value` member of a JSON object. `key` is the name, a `String`, and `value`
is the JSON document of its value.
"""
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool = false
end    

"""
A JSON object `{…}`: `entries` holds its members in order, each a `JsonObjectEntry`
with a `key` and a `value`. The object acts as a map from key to value:
`object["name"]` answers the value of that key, and `keys(object)`,
`haskey(object, key)` and `get(object, key, default)` work as for a `Dict`. A value
is a JSON document, so read the `value` field of a string, a number or a boolean for
the plain value. `collapsed` hides the members in the projection.

Use it to read the fields of a JSON record by their names.

# Example

    item["name"].value                # "lamp", the string of the key "name"
    keys(item)                        # the names of its fields
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
    !(try_evaluate_reference(doc, normalize_named_node_reference(sel)) isa Union{Nothing, JsonObjectEntry})

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion JsonBool        = @selected JsonBool(false)
@insertion JsonNumber      = @selected JsonNumber(nothing)
@insertion JsonString      = @selected JsonString("") value{0}
@insertion JsonArray       = @selected JsonArray([JsonInsertion()]) elements[1]
@insertion JsonObjectEntry = @selected JsonObjectEntry("", JsonInsertion()) key{0}
@insertion JsonObject      = @selected JsonObject([JsonObjectEntry("", JsonInsertion())]) entries[1].key{0}

# A number whose text does not parse yet, such as `-` or `1e`, is the insertion
# of the domain with that text, until a key makes a number of it again.
make_incomplete_number_document(::JsonNumber, text) = JsonInsertion(text)

@gestures JsonDocument begin
    when(_json_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => replace_selected_document(doc, @selected JsonNull())
    KeyPress('f') => "Replace with false"  => replace_selected_document(doc, make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => replace_selected_document(doc, @selected JsonBool(true))
    KeyPress('"') => "Replace with a string" => replace_selected_document(doc, make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => replace_selected_document(doc, make_insertion_document(JsonArray))
    KeyPress(':') => "Replace with an object entry" => replace_selected_document(doc, make_insertion_document(JsonObjectEntry))
    KeyPress('{') => "Replace with an object" => replace_selected_document(doc, make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        replace_selected_document(doc, @selected JsonNumber(parse(Int, string(c))) value{1})
end

# A `,` on the closing bracket or brace of a container is the parent's: the caret
# has left the container's content, so the container declines and its parent answers.
@gestures JsonArray begin
    KeyPress(',') => "Insert a new element" =>
        is_on_closing_delimiter(get_selection(doc)) ? nothing :
        append_insertion_operation(doc, :elements, JsonInsertion)
end

# The order of the entries in a sorted object: by key. An entry still under
# construction (a placeholder, not yet a key/value pair) keeps its place at the
# end, because the sort is stable.
_json_entry_sort_key(entry) = entry isa JsonObjectEntry ? (0, entry.key) : (1, "")

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" =>
        is_on_closing_delimiter(get_selection(doc)) ? nothing :
        append_insertion_operation(doc, :entries, JsonObjectEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc; from = :key, to = :value)
    # The way back has no key of its own. A rule with no gesture reaches the user by
    # name instead, through the command palette. The sort rule spends no key either.
    nothing       => "Move from value to key" => move_to_field(doc; from = :value, to = :key)
    nothing       => "Sort the entries by key" =>
        ReplaceReferencedValueOperation(doc, "entries", sort(doc.entries; by = _json_entry_sort_key))
end
