"""
    JsonModule

The JSON slice. One namespace holds the whole round trip for `.json`: the
document types, the parser that reads the text, the projection that renders and
edits the tree, and the file wrapper that writes it back.

Four fragments share the namespace:

- [`JsonDocument.jl`](JsonDocument.jl) — `@domain Json` and the document types,
  with the gestures that edit them.
- [`JsonParser.jl`](JsonParser.jl) — a recursive-descent reader from JSON text
  to a document tree.
- [`JsonToSyntax.jl`](JsonToSyntax.jl) — the projection to `SyntaxModule`, one
  rule per document type.
- [`JsonFile.jl`](JsonFile.jl) — `JsonFile`, a `FileDocument` whose content is a
  `JsonDocument`.

The slice depends on the engine packages and on no other domain. `__init__`
registers what the slice owns: the `.json` extension, and the natural notation
that starts at the syntax rung.
"""
module JsonModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventPatternModule
using ..GestureBindingModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content

export parse_json, parse_json_file
export JsonToSyntax, JsonInsertionToSyntaxLeaf


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
