"""
    DocumentModule

Layer 2 of the kernel — the **document contract**: the `Document` abstract type,
the selection protocol, and the shared `@document` machinery. Interface and
machinery are one module because they are only ever imported together.

Three fragments share this namespace, each documented at its own definition:
[`Interface.jl`](Interface.jl) (the `Document` type and selection generics),
[`Document.jl`](Document.jl) (`@document` and the value protocol), and
[`Forward.jl`](Forward.jl) (the `@forward*` delegating-method helpers). The
kernel defines only this contract; it carries no concrete documents.
"""
module DocumentModule

import ..CellModule: Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
                     cell_struct_kw_params, cell_struct_kwctor

export Document, get_selection, clear_selection!, set_selection!, with_selection, read_gesture,
       copy_document, cell_kind, rekind, snapshot, hydrate, sync_document!,
       @document, @forward, @forward_vector, @forward_map

# Interface.jl first — the machinery in Document.jl and Forward.jl refers to what
# it declares.
include("Interface.jl")
include("Document.jl")
include("Forward.jl")

end # module
