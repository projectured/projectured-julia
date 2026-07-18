"""
    BinarySerializationModule

Exact, lossless binary persistence for documents — `save_document` /
`load_document` — independent of any domain's text format.

A document is written with Julia's `Serialization` stdlib. The only
customization is that a [`Cell`](@ref) serializes as **just its value**: a cell's
reactive wiring (`deps`/`dependents`) and its computing `thunk` are *runtime
state*, not data. That single rule prunes the reactive graph at every cell
boundary, so serializing a live document stays within the document's own data and
never traverses `dependents` out into the projection output graph (computed cells
and their closures). It also means documents, `CellVector`s, and the selection
`Reference` (whose steps are themselves `Cell`-backed) are all handled
uniformly — so the saved **selection is restored** on load.

Targets *structural* documents. A document that holds a live external resource
(a database adapter, an open socket) is not serializable this way; for a
portable, human-readable format use the natural import/export
(`NaturalFormatModule`). The binary format is tied to the in-memory struct
layout, so it is a *same-version* persistence format, not an interchange format.
"""
module BinarySerializationModule

import ..CellModule: Cell, ReactiveCell
import ..DocumentModule: Document
import ..OperationModule: Operation, evaluate_operation
using Serialization

export save_document, load_document, SaveDocumentOperation, LoadDocumentOperation

# ── Cell: serialize the value only ─────────────────────────────────────────
#
# Writing `getfield(c, :value)` (never `c[]`, which would trigger a reactive read
# and register a spurious dependency) keeps serialization from following
# `dependents` into the projection graph. Deserialization rebuilds a fresh value
# cell: valid, no thunk, empty dep sets.
#
# We deliberately do *not* call `serialize_cycle`: that would register the cell in
# the writer's backref table without a matching read-side registration here,
# desyncing the shared-object counter and corrupting the stream. The cost is that
# cell *sharing* (the shared selection chain, where `child.selection ===
# parent.selection.tail`) is not preserved — the chain reloads as an equal value
# tree and is re-shared by the next `set_selection!`/`replace_selection!`, a
# perf nuance, not a correctness issue. Document trees are acyclic, so dropping
# cycle tracking cannot loop.
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

end # module
