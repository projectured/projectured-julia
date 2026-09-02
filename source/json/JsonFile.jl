"""
    JsonFileModule

`JsonFile`: a `FileDocument` whose `content` is a `JsonDocument`.
Parse uses the existing `jsonparse`; emit runs the existing
`JsonToSyntax → SyntaxToText → TextToString` projection chain via
`print_natural_text`.

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

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: @document
import ..ReferenceModule: Reference, ConcreteReference
import ..CollectionModule: CellVector, ComputedCellVector
import ..JsonModule: JsonDocument, JsonNothing, JsonString, JsonArray,
                     JsonObject, JsonObjectEntry
import ..JsonParserModule: jsonparse
import ..NaturalNotationModule: print_natural_text
import ..FileProjectModule: FileDocument, emit_text, populate_file!, content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!

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

# Emit through the visual projection pipeline via `print_natural_text`.
# The `ReferenceStub` case registered in `JsonToSyntax.jl` renders
# stubs as marker strings when the projection walks over them, so no
# pre-emit AST mutation is needed.
emit_text(f::JsonFile) = print_natural_text(content(f))

# Load: parse the file with `jsonparse`, then substitute marker
# strings with `ReferenceStub` values in the parsed tree in place.
# The stubs carry `ctx` so `resolve!` later shares interned targets
# with sibling stubs from the same load session.
function populate_file!(f::JsonFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = jsonparse(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

# Descend the JSON AST replacing marker-shaped `JsonString` leaves in
# place with `ReferenceStub` values that carry `ctx`. Reactive slot
# cells are `Any`-typed at runtime, so a stub sits happily in a
# `JsonObjectEntry` value slot declared `Document` or in a
# `JsonArray`'s CellVector element. Non-marker JsonStrings and
# non-string leaves are untouched; only the compound containers are
# traversed and their slot cells rewritten. Returns the (possibly
# replaced) root node.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::JsonString, ctx::LoaderContext)
    src = parse_marker_text(node.value)
    src === nothing ? node : ReferenceStub(src, ctx)
end

function _substitute_markers(node::JsonArray, ctx::LoaderContext)
    v = getfield(node, :elements)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i], ctx)
    end
    node
end

function _substitute_markers(node::JsonObjectEntry, ctx::LoaderContext)
    getfield(node, :value)[] = _substitute_markers(node.value, ctx)
    node
end

function _substitute_markers(node::JsonObject, ctx::LoaderContext)
    v = getfield(node, :entries)[]
    for i in eachindex(v)
        _substitute_markers(v[i], ctx)
    end
    node
end

# Register `.json` so `resolve!` picks JsonFile for a `<<file("x.json")>>`
# marker. Done in `__init__` so the mutation survives precompilation.
function __init__()
    register_file_document_type!(".json", JsonFile)
end

end # module
