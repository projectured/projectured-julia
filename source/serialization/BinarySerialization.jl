# Fragment of `SerializationModule` — the binary round trip of a reactive cell.
# The concrete type is the tag, so a typed cell keeps its value-type parameter,
# and reading one back builds a fresh primitive cell.

function Serialization.serialize(s::AbstractSerializer, c::ReactiveCell)
    # The concrete type (`ReactiveCell{T}`) is the tag, so typed cells round-trip
    # their value-type parameter. Deserialization rebuilds a fresh primitive cell.
    Serialization.serialize_type(s, typeof(c))
    Serialization.serialize(s, getfield(c, :value))
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ReactiveCell{T}}) where {T}
    value = Serialization.deserialize(s)
    ReactiveCell{T}(value)
end

# ── On-disk format ─────────────────────────────────────────────────────────
# A small header precedes the document so `load_document` can reject foreign or
# future-version files instead of returning a garbled object.
const _MAGIC = "PROJECTURED-DOC"
# v2: `Cell` became the parametric `ReactiveCell{T}`; cells are tagged with their
# concrete type. v1 files (untyped `Cell` tag) are rejected by the version check.
const _VERSION = 2

"""
    save_document(document, path) -> path

Serialize `document` to `path` in the exact binary format (header + payload).
Returns `path`. See the module docstring for what "exact" covers (full structure
plus selection) and the structural-only limitation.
"""
function save_document(document::Document, path::AbstractString)
    open(path, "w") do io
        serialize(io, _MAGIC)
        serialize(io, _VERSION)
        serialize(io, document)
    end
    path
end

"""
    load_document(path) -> Document

Read a document written by [`save_document`](@ref). Validates the header and
returns a fresh document tree whose cells are all detached value cells (empty
reactive graph), ready to be set as `editor.document`.
"""
function load_document(path::AbstractString)
    open(path, "r") do io
        magic = deserialize(io)
        magic == _MAGIC ||
            error("load_document: $(repr(path)) is not a ProjecturEd document")
        version = deserialize(io)
        version == _VERSION ||
            error("load_document: unsupported format version $version (expected $_VERSION)")
        doc = deserialize(io)
        doc isa Document ||
            error("load_document: payload is not a Document (got $(typeof(doc)))")
        doc
    end
end

# ── Editor operations ──────────────────────────────────────────────────────

"""
    SaveDocumentOperation(path)

Write `editor.document` to `path` in the binary format (see [`save_document`](@ref)).
A pure side effect: the document is not mutated. The `path` is carried on the
operation, so it is drivable from the REPL, tests, MCP tools, and timelines.
"""
struct SaveDocumentOperation <: Operation
    path::String
end

SaveDocumentOperation(path::AbstractString) = SaveDocumentOperation(String(path))

# The file on disk changes, the document does not, so the way back is to do
# nothing. A history steps over it rather than stopping at it.
make_inverse_operation(document, ::SaveDocumentOperation) = DoNothingOperation()

evaluate_operation(editor, op::SaveDocumentOperation) =
    save_document(editor.document, op.path)

"""
    LoadDocumentOperation(path)

Replace `editor.document` with the document read from `path` (see
[`load_document`](@ref)). A **whole-root swap**, identical to the empty-path
branch of `ReplaceReferencedValueOperation`: rebind `editor.document` and drop the cached
`editor.iomap` so the next print rebuilds the projection on the freshly loaded
root.
"""
struct LoadDocumentOperation <: Operation
    path::String
end

LoadDocumentOperation(path::AbstractString) = LoadDocumentOperation(String(path))

function evaluate_operation(editor, op::LoadDocumentOperation)
    editor.document = load_document(op.path)
    editor.iomap = nothing
end
