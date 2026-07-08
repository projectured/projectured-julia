"""
    DocumentModule

Layer 2 of the kernel — the **document contract** every concrete document
subtypes and every projection consumes. The interface and the machinery are
one module, because the two are only ever imported together and separating
them just multiplied import headers.

The module lives in two fragments that share this namespace:

- [`Interface.jl`](Interface.jl) — the `Document` abstract type, the selection
  generics (`get_selection`, `clear_selection!`, `set_selection!`,
  `with_selection`), and the projection-independent `read_gesture` seam. This
  is the surface every higher layer implements against.
- [`Document.jl`](Document.jl) — the shared machinery: the generic
  `Base.show`, the `@document` macro and its `@forward*` family, and the value
  protocol `copy_document`/`cell_kind`/`rekind`/`snapshot`/`hydrate`/
  `sync_document!` that reactive syncing and rehydration ride on. `@document`
  builds its keyword-constructor support on the cell layer's exported
  Cell-struct codegen (`cell_kw_params` / `cell_kwctor`, beside `@cell_struct`
  in `cell/CellStruct.jl` — the same codegen `@iomap` and `@projection`
  delegate to wholesale).

The concrete documents (Collection, Primitive, ScreenDocument) live in the
base and visual packages, not the kernel.

The two contracts every concrete document must satisfy:

1. **Selection field.** A `selection::Cell{Reference}` field tracks the
   current selection (nil or a `ReferencePath`). The `@document`-generated
   `getproperty` unwraps the Cell.
2. **Field names ARE the reference vocabulary.** A `FieldReference("foo")`
   in a path resolves via `getfield(document, :foo)`; renaming a struct field
   silently breaks every stored reference. Struct fields are public API.
"""
module DocumentModule

import ..CellModule: Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
                     cell_kw_params, cell_kwctor

export Document, get_selection, clear_selection!, set_selection!, with_selection, read_gesture,
       copy_document, cell_kind, rekind, snapshot, hydrate, sync_document!,
       @document, @forward, @forward_vector, @forward_map

# The abstract type and selection generics first; the machinery in Document.jl
# refers to them.
include("Interface.jl")
include("Document.jl")

end # module
