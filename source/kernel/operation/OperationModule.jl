"""
    OperationModule

**Changing documents**. An `Operation` is a reified edit — produced by a reader
and applied by `evaluate_operation`. This module holds the abstract `Operation`
supertype, the `evaluate_operation` / `invalidate_projection!` generics, the
`make_inverse_operation` seam that answers the way back, the
built-in cross-domain operations and their `evaluate_operation` methods, the
`splice_*` text-edit helpers, and two open seams higher layers extend:
`child_reference_steps` (per-container-document child traversal) and the
per-path-bearing-operation reference seams `reroot_operation`,
`operation_reference`, and `retarget_operation`. The
selection-changing operations drive the selection primitives in the layer below,
which is why the module sits above references and the selection contract.

The module lives in five fragments that share this namespace:

- [`Interface.jl`](Interface.jl) — the contract: the `Operation` supertype, the
  `WrappingOperation` supertype with its `get_wrapped_operation` /
  `rewrap_operation` pair, and the `evaluate_operation` /
  `invalidate_projection!` generics.
- [`Operations.jl`](Operations.jl) — the concrete operations, the `splice_*`
  text-edit helpers, and the `child_reference_steps` traversal seam.
- [`Rerooting.jl`](Rerooting.jl) — the reference-rewrite seams
  (`reroot_operation`, `operation_reference`, `retarget_operation`) and
  `reroot_reference`.
- [`Inversion.jl`](Inversion.jl) — the way back: `make_inverse_operation`,
  `evaluate_invertible_operation!` and the `get_slot_at` seam.
- [`Description.jl`](Description.jl) — `describe_operation`, one line about an
  operation for a human to read.

`evaluate_operation` is duck-typed on `editor`: nothing in the layer names a
concrete editor type, so it loads well before the editor loop and works against
any object carrying `editor.document`.
"""
module OperationModule

using ..FaultModule
using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..SelectionModule

export Operation, WrappingOperation, get_wrapped_operation, rewrap_operation,
       evaluate_operation, invalidate_projection!,
       # from Operations.jl
       DoNothingOperation, ReplaceSelectionOperation, QuitEditorOperation,
       QuitEditorException, ToggleCollapseOperation,
       ReplaceReferencedValueOperation, ReplaceViewStateOperation,
       replace_document, insert_elements,
       delete_elements, SelectNextInsertionOperation, CompoundOperation,
       AdjustZoomOperation, AdjustFontZoomOperation,
       splice_string, splice_number, splice_value!,
       child_reference_steps,
       # from Rerooting.jl
       reroot_reference, reroot_operation, operation_reference, retarget_operation,
       operation_travels_unchanged,
       # from Inversion.jl
       make_inverse_operation, evaluate_invertible_operation!, get_slot_at,
       # from Description.jl
       describe_operation

include("OperationInterface.jl")   # the operation contract (declaration-only)
include("OperationDefaults.jl")    # the fallback behaviours the contract supplies itself
include("Operations.jl")  # concrete ops, splice helpers, traversal seam
include("Rerooting.jl")   # reference-rewrite seams + reroot_reference
include("Inversion.jl")  # the way back: inverses + the slot seam
include("Description.jl") # one line about an operation, for a human

end # module
