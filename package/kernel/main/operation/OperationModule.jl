"""
    OperationModule

**Changing documents**. Operations are the reified
edits the reader side of the projection pipeline produces and
`evaluate_operation` applies. This module holds the abstract `Operation`
supertype and the `evaluate_operation` / `invalidate_projection!` generics
(from `Interface.jl`), the built-in concrete operations and their
`evaluate_operation` methods (the selection-changing ones —
`ReplaceSelectionOperation`, `SelectNextInsertionOperation` — drive the
selection primitives in the layer below), the `splice_*` text-edit helpers, and
the two open seams the container projections and higher documents extend:

- `child_reference_steps(node)` (in `Operations.jl`): the open
  traversal seam driving `SelectNextInsertionOperation`'s pre-order
  document walk. The default enumerates `fieldnames` as `FieldReference`
  steps; base's `Collection.jl` adds the `CellVector` method that yields
  `RangeReference(i-1, i)` per element. A new container document adds a
  method.

- `reroot_operation(op, steps)` (in `Rerooting.jl`): the open
  reroot generic every path-bearing operation must add a method for.
  Base methods here for `Nothing`, catch-all,
  `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation`, and
  `CompoundOperation`; `document/Primitive.jl` adds
  `ReplaceStringRangeOperation` and `ReplaceNumberRangeOperation` (they
  leave with Primitive for base).

This module aggregates three fragments — the interface (`Interface.jl`),
the concrete operations and traversal (`Operations.jl`), and the reroot
seam (`Rerooting.jl`) — since they are only ever imported together. The
three files remain as fragments sharing this namespace.

`evaluate_operation` is duck-typed on `editor`: nothing in the layer
references a concrete editor type, so it loads well before the editor loop
and still works against any object carrying `editor.document`.
"""
module OperationModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..SelectionModule

export Operation, evaluate_operation, invalidate_projection!,
       # from Operations.jl
       DoNothingOperation, ReplaceSelectionOperation, QuitEditorOperation,
       QuitEditorException, ToggleCollapseOperation,
       ReplaceReferencedValueOperation, replace_document, insert_elements,
       delete_elements, SelectNextInsertionOperation, CompoundOperation,
       AdjustZoomOperation, AdjustFontZoomOperation,
       splice_string, splice_number, splice_value!,
       child_reference_steps,
       # from Rerooting.jl
       reroot_reference, reroot_operation

include("Interface.jl")   # Operation + evaluate_operation + invalidate_projection!
include("Operations.jl")  # concrete ops, splice helpers, traversal seam
include("Rerooting.jl")   # reroot seam + reroot_reference

end # module
