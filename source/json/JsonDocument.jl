"""
    JsonModule

The JSON document domain.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonNothing` for an empty document, `JsonInsertion` for cursor positioning
"""
module JsonModule

export entries
export parse_json, parse_json_file
import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: print_document, Projection
import ..ProjectionModule: var"@projection"
import ..SerializationModule: FileDocument, ReferenceStub, format_marker_text, format_file_marker_text, get_filename
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString, make_hinted_text
import ..StyleModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..StyleModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: ReplaceNumberRangeOperation
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonObjectEntryToSyntaxNode,
       ReferenceStubToJsonSyntaxLeaf, EmbeddedFileDocumentToJsonSyntaxLeaf,
       JsonToSyntax
import ..FileFormatModule: make_document_seed
import ..NaturalModule: register_natural_domain!
import ..DocumentModule: @document
import ..ReferenceModule: Reference, ConcreteReference
import ..CollectionModule: CellVector, ComputedCellVector
import ..NaturalModule: print_natural_text
import ..SerializationModule: FileDocument, emit_text, populate_file!, get_file_content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!
export JsonFile
export JsonDocument, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonNothing, JsonInsertion, JsonObjectEntry


using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceStepModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule


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
    !(try_evaluate_reference(doc, normalize_named_node_reference(sel)) isa Union{Nothing, JsonObjectEntry})

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

# The order of the entries in a sorted object: by key. An entry still under
# construction (a placeholder, not yet a key/value pair) keeps its place at the
# end, because the sort is stable.
_json_entry_sort_key(entry) = entry isa JsonObjectEntry ? (0, entry.key) : (1, "")

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, JsonObjectEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc, :key, :value)
    # The way back has no key of its own. A rule with no gesture reaches the user by
    # name instead, through the command palette. The sort rule spends no key either.
    nothing       => "Move from value to key" => move_to_field(doc, :value, :key)
    nothing       => "Sort the entries by key" =>
        ReplaceReferencedValueOperation(doc, "entries", sort(doc.entries; by = _json_entry_sort_key))
end


include("JsonParser.jl")
include("JsonToSyntax.jl")
include("JsonFile.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_natural_domain!(JsonDocument;
                             rung      = :syntax,
                             make      = () -> JsonToSyntax(),
                             format    = :json,
                             extension = ".json",
                             parse     = parse_json)

    register_file_document_type!(".json", JsonFile)
end

end # module
