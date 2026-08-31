"""
    OperationModule

**Changing documents**. An `Operation` is a reified edit — produced by a reader
and applied by `evaluate_operation`. This module holds the abstract `Operation`
supertype, the `evaluate_operation` / `invalidate_projection!` generics, the
built-in cross-domain operations and their `evaluate_operation` methods, the
`splice_*` text-edit helpers, and two open seams higher layers extend:
`child_reference_steps` (per-container-document child traversal) and the
per-path-bearing-operation reference seams `reroot_operation`,
`operation_reference`, and `retarget_operation`. The
selection-changing operations drive the selection primitives in the layer below,
which is why the module sits above references and the selection contract.

The module lives in three fragments that share this namespace:

- [`Interface.jl`](Interface.jl) — the contract: the `Operation` supertype and
  the `evaluate_operation` / `invalidate_projection!` generics.
- [`Operations.jl`](Operations.jl) — the concrete operations, the `splice_*`
  text-edit helpers, and the `child_reference_steps` traversal seam.
- [`Rerooting.jl`](Rerooting.jl) — the reference-rewrite seams
  (`reroot_operation`, `operation_reference`, `retarget_operation`) and
  `reroot_reference`.

`evaluate_operation` is duck-typed on `editor`: nothing in the layer names a
concrete editor type, so it loads well before the editor loop and works against
any object carrying `editor.document`.
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
       reroot_reference, reroot_operation, operation_reference, retarget_operation,
       operation_travels_unchanged

include("Interface.jl")   # Operation + evaluate_operation + invalidate_projection!
include("Operations.jl")  # concrete ops, splice helpers, traversal seam
include("Rerooting.jl")   # reference-rewrite seams + reroot_reference

end # module
