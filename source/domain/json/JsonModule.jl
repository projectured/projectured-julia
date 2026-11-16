"""
    JsonModule

JSON documents: objects, arrays, strings, numbers, true, false and null, read from a
file and written back as text. One namespace holds the whole round trip for `.json`:
the document types, the parser that reads the text, the projection that renders and
edits the tree, and the file wrapper that writes it back.

Five fragments share the namespace:

- [`JsonDocument.jl`](JsonDocument.jl) — `@domain Json` and the document types,
  with the gestures that edit them.
- [`JsonParser.jl`](JsonParser.jl) — a recursive-descent reader from JSON text
  to a document tree.
- [`JsonToSyntax.jl`](JsonToSyntax.jl) — the projection to `SyntaxModule`, one
  rule per document type.
- [`JsonFile.jl`](JsonFile.jl) — `JsonFileFormat`, the format of a `.json` file,
  and `JsonFile`, its file, whose content is a `JsonDocument`.
- [`JsonView.jl`](JsonView.jl) — the views of the JSON documents, which keep the
  state of one view of a document.

The slice depends on the engine packages and on no other domain. `__init__`
registers what the slice owns: the `.json` extension, the natural notation
that starts at the syntax rung, and the document types that a model may name.
"""
module JsonModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..PrimitiveModule: make_incomplete_number_document
import ..ProjectionAlgebraModule: make_content_view
import ..SerializationModule: make_reference_leaf, find_reference_marker, make_document_seed,
                              get_file_format_extensions, get_file_format_domain,
                              parse_document_string
import ..NaturalModule: make_syntax_projection, find_natural_file_format
import ..DisplayModule: make_workload_file

export parse_json, parse_json_file
export JsonTheme, ScaledJsonTheme
export JsonToSyntax, JsonInsertionToSyntaxLeaf
export JsonFileFormat, JsonFile
export JsonView, JsonNullView, JsonBoolView, JsonNumberView, JsonStringView, JsonArrayView


include("JsonDocument.jl")
include("JsonParser.jl")
include("JsonTheme.jl")
include("JsonToSyntax.jl")
include("JsonFile.jl")
include("JsonView.jl")


# What this slice registers when it loads: the sentence that tells a model what a
# JSON document is. A JSON document is written as its text, so the domain offers
# no name to a model.
function __init__()
    register_assistant_api!(Any[];
        description = "A JSON value is a document that is written and read as its JSON text.")
end

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{JsonFile}) =
    (; name = "a.json", text = "{\"name\": \"Alice\", \"age\": 7}\n", shown = r"Alice")

end # module
