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
registers what the slice owns: the `.json` extension, the natural notation
that starts at the syntax rung, and the document types that a model may name.
"""
module JsonModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..PrimitiveModule: make_incomplete_number_document
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content

export parse_json, parse_json_file
export JsonTheme, ScaledJsonTheme
export JsonToSyntax, JsonInsertionToSyntaxLeaf


include("JsonDocument.jl")
include("JsonParser.jl")
include("JsonTheme.jl")
include("JsonToSyntax.jl")
include("JsonFile.jl")


# What this slice registers when it loads: the file extensions it owns, the
# natural notation it reads and writes, and the names a model may use.
function __init__()
    register_natural_domain!(JsonDocument;
                             rung      = :syntax,
                             make      = (; appearance) -> JsonToSyntax(;
                                 theme = get_scaled_theme!(appearance, JsonTheme),
                                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                             format    = :json,
                             extension = ".json",
                             parse     = parse_json)

    register_file_document_type!(".json", JsonFile)

    # The shape of a JSON file, which a model reads to find the fields of a
    # record.
    register_assistant_api!(JsonModule => (:JsonArray, :JsonObject, :JsonObjectEntry,
                                           :JsonString, :JsonNumber, :JsonBool,
                                           :JsonNull))
end

end # module
