"""
    DocumentModule

Layer 2 of the kernel — the **document contract**: the `Document` abstract
type, the `@document`/`@forward*` codegen macros, and the shared value
protocol every concrete document reuses (`copy_document`, `sync_document!`).
It also carries the reflection walk over a document tree (`search_documents`,
with the `is_element_collection` / `is_opaque` traits that steer it) — the
value-collecting search that needs no reference machinery. The kernel defines
only this contract; it carries no concrete documents.

Three fragments share this namespace, each documented at its own definition:
[`Interface.jl`](Interface.jl) (the `Document` type + selection-field
obligation), [`Document.jl`](Document.jl) (`@document` and the value
protocol), and [`Forward.jl`](Forward.jl) (the `@forward*` delegating-method
helpers).
"""
module DocumentModule

import ..CellModule: Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
                     cell_struct_kw_params, cell_struct_kwctor

export Document, copy_document, sync_document!, is_element_collection,
       is_opaque, search_documents,
       @document, @forward, @forward_vector, @forward_map

# Interface.jl first — the machinery in Document.jl and Forward.jl refers to
# the `Document` supertype it declares.
include("Interface.jl")
include("Document.jl")
include("Forward.jl")

end # module
