"""
    DocumentModule

Layer 2 of the kernel — the **document contract**: the `Document` abstract
type, the `@document`/`@forward*` codegen macros, and the shared value
protocol every concrete document reuses (`copy_document`, `sync_document!`).
It also carries the reflection walk over a document tree (`search_documents`,
with the `is_element_collection` / `is_opaque` traits that steer it) — the
value-collecting search that needs no reference machinery. The kernel defines
only this contract; it carries no concrete documents.

The module is a set of fragments sharing this namespace, each documented at
its own definition:

| Fragment | Contract |
|---|---|
| [`Document.jl`](Document.jl) | the `Document` supertype |
| [`DocumentTrait.jl`](DocumentTrait.jl) | `is_element_collection` / `is_opaque` — the traits that steer a walk |
| [`DocumentKind.jl`](DocumentKind.jl) | the cell-kind vocabulary the value protocol is written against |
| [`DocumentCopy.jl`](DocumentCopy.jl) | `copy_document` — deep copy, kind-preserving or kind-converting |
| [`DocumentSync.jl`](DocumentSync.jl) | `sync_document!` — the double-buffer shadow sync |
| [`DocumentMacro.jl`](DocumentMacro.jl) | `@document` — the document codegen |
| [`DocumentSearch.jl`](DocumentSearch.jl) | `search_documents` — the value-collecting reflection walk |
| [`DocumentShow.jl`](DocumentShow.jl) | the depth-limited debug `show` |
| [`Forward.jl`](Forward.jl) | `@forward*` — delegating-method helpers |
"""
module DocumentModule

using ..CellModule

export Document, copy_document, sync_document!, is_element_collection,
       is_opaque, search_documents,
       @document, @forward, @forward_vector, @forward_map
# The shadow-sync seam: what a document of a different *shape* writes its own
# `sync_document!` method against (a positional collection matches slots by
# index, so it cannot reuse the record walk). Exported because it is a contract,
# not an internal — the module boundary is the API boundary.
export is_same_document_type, get_document_cell_kind, copy_shadow_element, copy_cell_as

# Document.jl first — every fragment below refers to the `Document` supertype.
include("Document.jl")
include("DocumentTrait.jl")
include("DocumentKind.jl")
include("DocumentCopy.jl")
include("DocumentSync.jl")
include("DocumentMacro.jl")
include("DocumentSearch.jl")
include("DocumentShow.jl")
include("Forward.jl")

end # module
