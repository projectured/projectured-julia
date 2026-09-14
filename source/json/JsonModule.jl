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
using ..CellModule
using ..ProjectionApiModule
using ..ProjectionModule
using ..SerializationModule
import ..SerializationModule: emit_text, populate_file!
using ..SyntaxModule
using ..TextModule
using ..StyleModule
using ..ProjectionAlgebraModule
using ..ProjectionTemplateModule
using ..PrimitiveModule
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonObjectEntryToSyntaxNode,
       ReferenceStubToJsonSyntaxLeaf, EmbeddedFileDocumentToJsonSyntaxLeaf,
       JsonToSyntax
import ..FileFormatModule: make_document_seed
using ..NaturalModule
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

include("JsonDocument.jl")
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
