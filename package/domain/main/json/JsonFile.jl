"""
    JsonFileModule

`JsonFile`: a `FileDocument` whose `content` is a `JsonDocument`.
Parse uses the existing `jsonparse`; emit runs the existing
`JsonToSyntax → SyntaxToText → TextToString` projection chain via
`document_to_text`.

Cross-file references appear in JSON as **strings** whose whole value
matches the marker regex (see `parse_marker_text`). A post-parse walk
substitutes those strings with `ReferenceStub` values in the AST
(reactive slot cells are `Any`-typed at runtime, so a stub sits
happily in a `JsonObjectEntry.value` slot declared `Document`, or in a
`JsonArray` element). Emit is symmetric — an extension of
`JsonToSyntax` (in `JsonToSyntax.jl`) renders `ReferenceStub` and
embedded `FileDocument` values as marker strings, so no pre-save
mutation is required.
"""
module JsonFileModule

import ..CellModule: Cell
import ..DocumentModule: @document
import ..ReferenceModule: Reference, ConcreteReference
import ..CollectionModule: CellVector
import ..JsonModule: JsonDocument, JsonNothing, JsonString, JsonArray,
                     JsonObject, JsonObjectEntry
import ..JsonParserModule: jsonparse
import ..NaturalFormatModule: document_to_text
import ..FileProjectModule: FileDocument, emit_text, load_file, content,
                            parse_marker_text, ReferenceStub

export JsonFile

"""
    JsonFile(filename, content)

A file document whose `content` is a `JsonDocument`. See the module
docstring for the marker walk and the emit-side projection extension.
"""
@document struct JsonFile <: FileDocument
    filename::String
    content::JsonDocument = JsonNothing()
end

# Emit through the visual projection pipeline via `document_to_text`.
# The `ReferenceStub` case registered in `JsonToSyntax.jl` renders
# stubs as marker strings when the projection walks over them, so no
# pre-emit AST mutation is needed.
emit_text(f::JsonFile) = document_to_text(content(f))

# Load: parse the file with `jsonparse`, then substitute marker
# strings with `ReferenceStub` values in the parsed tree in place.
function load_file(::Type{JsonFile}, filename::AbstractString, base_dir::AbstractString)
    text = read(joinpath(base_dir, filename), String)
    ast = jsonparse(text)
    ast = _substitute_markers(ast)
    JsonFile(String(filename), ast)
end

# Descend the JSON AST replacing marker-shaped `JsonString` leaves in
# place with `ReferenceStub` values. Reactive slot cells are
# `Any`-typed at runtime, so a stub sits happily in a `JsonObjectEntry`
# value slot declared `Document` or in a `JsonArray`'s CellVector
# element. Non-marker JsonStrings and non-string leaves are untouched;
# only the compound containers are traversed and their slot cells
# rewritten. Returns the (possibly replaced) root node.
_substitute_markers(node) = node

function _substitute_markers(node::JsonString)
    ref = parse_marker_text(node.value)
    ref === nothing ? node : ReferenceStub(ref)
end

function _substitute_markers(node::JsonArray)
    v = getfield(node, :elements)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i])
    end
    node
end

function _substitute_markers(node::JsonObjectEntry)
    getfield(node, :value)[] = _substitute_markers(node.value)
    node
end

function _substitute_markers(node::JsonObject)
    v = getfield(node, :entries)[]
    for i in eachindex(v)
        _substitute_markers(v[i])
    end
    node
end

end # module
