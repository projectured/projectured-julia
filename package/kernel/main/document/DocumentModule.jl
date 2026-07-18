"""
    DocumentModule

The **document contract**: the `Document` abstract type, the `@document`
codegen, the protocol forward/adapt macros, and the shared value protocol every
concrete document reuses (`copy_document`, `sync_document!`).
It also carries the reflection walk over a document tree (`search_documents`,
with the `is_element_collection` / `is_walk_opaque` traits that steer it) — the
value-collecting search that needs no reference machinery. The kernel defines
only this contract; it carries no concrete documents.

The module is a set of fragments sharing this namespace, each documented at
its own definition:

| Fragment | Contract |
|---|---|
| [`DocumentInterface.jl`](DocumentInterface.jl) | the `Document` supertype + the contract generics (`is_element_collection` / `is_walk_opaque` / `copy_document` / `sync_document!` / `search_documents`) |
| [`DocumentDefaults.jl`](DocumentDefaults.jl) | the default answers for the `is_element_collection` / `is_walk_opaque` traits |
| [`DocumentKind.jl`](DocumentKind.jl) | the cell-kind vocabulary the value protocol is written against |
| [`DocumentCopy.jl`](DocumentCopy.jl) | `copy_document` — deep copy, kind-preserving or kind-converting |
| [`DocumentSync.jl`](DocumentSync.jl) | `sync_document!` — the double-buffer shadow sync |
| [`DocumentMacro.jl`](DocumentMacro.jl) | `@document` — the document codegen |
| [`DocumentWalk.jl`](DocumentWalk.jl) | `walk_document` — the one reflection walk, parameterized by how it names a node (`DocumentWalk`) |
| [`DocumentSearch.jl`](DocumentSearch.jl) | `search_documents` — the value-collecting walk |
| [`DocumentShow.jl`](DocumentShow.jl) | the depth-limited debug `show` |
| [`ForwardProtocol.jl`](ForwardProtocol.jl) | `@forward_protocol` / `@forward_vector_protocol` / `@adapt_map_protocol` — give a wrapper another type's protocol |
"""
module DocumentModule

using ..CellModule
using ..CellStructModule

export Document, copy_document, copy_cell_as, sync_document!,
       is_element_collection, is_walk_opaque, search_documents,
       @document, @forward_protocol, @forward_vector_protocol, @adapt_map_protocol
export DocumentWalk, walk_document, text_predicate

include("DocumentInterface.jl")  # the contract; every fragment below extends it
include("DocumentDefaults.jl")
include("DocumentKind.jl")
include("DocumentCopy.jl")
include("DocumentSync.jl")
include("DocumentMacro.jl")
include("DocumentWalk.jl")
include("DocumentSearch.jl")
include("DocumentShow.jl")
include("ForwardProtocol.jl")

end # module
