# Fragment of `JsonModule` — `JsonFile`, the `.json` file on disk.
#
# A cross-file reference is written in JSON as a string whose whole value is a
# marker. The two directions are symmetric: on load `_substitute_markers`
# replaces each such `JsonString` with a `ReferenceStub`, and on save
# `JsonToSyntax` renders a `ReferenceStub` and an embedded `FileDocument` back
# as a marker string. Neither direction mutates the tree before it walks it.
"""
    JsonFile(filename, content)

A file document whose `content` is a `JsonDocument`.
"""
@document struct JsonFile <: FileDocument
    filename::String
    content::JsonDocument = JsonNothing()
end

# Emit runs the `JsonToSyntax → SyntaxToText → TextToString` chain.
emit_text(f::JsonFile) = print_natural_text(get_file_content(f))

# A stub carries `ctx`, so `resolve!` later shares an interned target with the
# sibling stubs of the same load session.
function populate_file!(f::JsonFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = parse_json(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

# Replace every marker-shaped `JsonString` with a `ReferenceStub`, in place, and
# return the root. A reactive slot cell is `Any`-typed at runtime, so a stub sits
# in a `JsonObjectEntry.value` slot declared `Document` and in a `JsonArray`
# element. Every other leaf is left alone.
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
