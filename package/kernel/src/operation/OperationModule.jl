"""
    OperationModule

Layer 4 of the kernel — **changing documents**. Operations are the reified
edits the reader side of the projection pipeline produces and
`evaluate_operation` applies. This module holds the abstract `Operation`
supertype and the `evaluate_operation` / `invalidate_projection!` generics
(from `Interface.jl`), the built-in concrete operations and their
`evaluate_operation` methods, the selection propagation
(`clear_selection!` / `set_selection!` / `update_selection!`), the
`splice_*` text-edit helpers, and the two open seams the container
projections and higher documents extend:

- **R1** — `child_reference_steps(node)` (in `Operations.jl`): the open
  traversal seam driving `SelectNextInsertionOperation`'s pre-order
  document walk. The default enumerates `fieldnames` as `FieldReference`
  steps; base's `Collection.jl` adds the `CellVector` method that yields
  `RangeReference(i-1, i)` per element. A new container document adds a
  method.

- **R2** — `reroot_operation(op, steps)` (in `Rerooting.jl`): the open
  reroot generic every path-bearing operation must add a method for.
  Base methods here for `Nothing`, catch-all,
  `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation`, and
  `CompoundOperation`; `document/Primitive.jl` adds
  `ReplaceStringRangeOperation` and `ReplaceNumberRangeOperation` (they
  leave with Primitive for base at P7).

Merged in kernel plan P4 from `OperationApiModule` (`api/OperationApi.jl`,
the interface), `OperationModule` (`common/Operation.jl`, the operations
and traversal), and `OperationRerootingModule`
(`common/OperationRerooting.jl`, the reroot seam) — three modules only
ever imported together. The three files remain as fragments sharing this
namespace.

`evaluate_operation` is duck-typed on `editor`: nothing in the layer
references a concrete editor type, so it loads well before the editor loop
and still works against any object carrying `editor.document`.
"""
module OperationModule

import ..CellModule: Cell, AbstractCell
import ..DocumentModule: Document, clear_selection!, set_selection!, with_selection
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                           FieldReference, RangeReference, TypeReference,
                           is_element_reference, evaluate_reference, is_reference_equal,
                           annotate_reference_types, strip_reference_types,
                           append_reference, concat_references, reference_steps

export Operation, evaluate_operation, invalidate_projection!,
       # from Operations.jl
       DoNothingOperation, ReplaceSelectionOperation, QuitEditorOperation,
       QuitEditorException, replace_selection!, ToggleCollapseOperation,
       ReplaceReferencedValueOperation, replace_document, insert_elements,
       delete_elements, SelectNextInsertionOperation, CompoundOperation,
       AdjustZoomOperation, AdjustFontZoomOperation, update_selection!,
       splice_string, splice_number, splice_value!,
       child_reference_steps,
       # from Rerooting.jl
       reroot_reference, reroot_operation

include("Interface.jl")   # Operation + evaluate_operation + invalidate_projection!
include("Operations.jl")  # concrete ops, splice helpers, R1 seam
include("Rerooting.jl")   # R2 seam + reroot_reference

end # module
