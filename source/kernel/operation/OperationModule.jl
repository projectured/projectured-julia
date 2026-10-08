"""
    OperationModule

**Changing documents**. An `Operation` is a reified edit — produced by a reader
and applied by `evaluate_operation`. This module holds the abstract `Operation`
supertype, the `evaluate_operation` / `invalidate_projection!` generics, the
`make_inverse_operation` seam that answers the way back, the
built-in cross-domain operations and their `evaluate_operation` methods, the
`splice_*` text-edit helpers, and five open seams higher layers extend:
`child_reference_steps` (per-container-document child traversal),
`with_object_field` (the copy that writes a field of a plain immutable value),
and the per-path-bearing-operation reference seams `reroot_operation`,
`operation_reference`, and `retarget_operation`. The
selection-changing operations drive the selection primitives in the layer below,
which is why the module sits above references and the selection contract.

The module lives in seven fragments that share this namespace:

- [`OperationInterface.jl`](OperationInterface.jl) — the contract: the `Operation`
  supertype, the `WrappingOperation` supertype with its `get_wrapped_operation` /
  `rewrap_operation` pair, the `evaluate_operation` / `invalidate_projection!`
  generics, and the declarations of the seams that the other fragments answer.
- [`OperationDefaults.jl`](OperationDefaults.jl) — the fallbacks: the
  `evaluate_operation` methods for `nothing` and for a value that is not an
  `Operation`, the `invalidate_projection!` that drops nothing, and the default
  `with_object_field`.
- [`Operations.jl`](Operations.jl) — the concrete operations, the `splice_*`
  text-edit helpers, and the `child_reference_steps` traversal seam.
- [`PathChain.jl`](PathChain.jl) — `replace_path_chain!`, which writes a kind of
  path other than the selection into each document on it, `replace_mouse_target!`,
  `get_mouse_target`, and the answers to a move: `add_mouse_target`,
  `has_mouse_target` and `join_move_answers`.
- [`Rerooting.jl`](Rerooting.jl) — the reference-rewrite seams
  (`reroot_operation`, `operation_reference`, `retarget_operation`) and
  `reroot_reference`.
- [`Inversion.jl`](Inversion.jl) — the way back: `make_inverse_operation`,
  `evaluate_invertible_operation!` and the `get_slot_at` seam.
- [`Description.jl`](Description.jl) — `describe_operation`, one line about an
  operation for a human to read, and `describe_reference`, the same for a path.

`evaluate_operation` is duck-typed on `editor`: nothing in the layer names a
concrete editor type, so it works against any object carrying `editor.document`.
"""
module OperationModule

using ..CellModule
using ..DocumentModule
using ..FaultModule
using ..ReferenceModule
using ..SelectionModule
using Base.ScopedValues: ScopedValue, with

export Operation, WrappingOperation, get_wrapped_operation, rewrap_operation,
       is_collecting_operation, join_collected_operations,
       evaluate_operation, invalidate_projection!,
       # from Operations.jl
       ReplacePathOperation, get_operation_path, make_path_operation,
       DoNothingOperation, InvalidateProjectionOperation,
       ReplaceSelectionOperation, ReplaceMouseTargetOperation, StartDragOperation,
       find_drop_zone,
       QuitEditorOperation,
       SetTimerOperation,
       QuitEditorException, ToggleCollapseOperation,
       ReplaceReferencedValueOperation, ReplaceViewStateOperation,
       make_replace_document_operation, make_insert_elements_operation,
       make_delete_elements_operation, SelectNextInsertionOperation, CompoundOperation,
       splice_string, splice_number, splice_value!, with_object_field,
       child_reference_steps,
       # from PathChain.jl
       replace_path_chain!, replace_mouse_target!, get_mouse_target, add_mouse_target,
       has_mouse_target, join_move_answers,
       # from Rerooting.jl
       reroot_reference, reroot_operation, operation_reference, retarget_operation,
       is_self_contained_operation,
       # from Inversion.jl
       make_inverse_operation, evaluate_invertible_operation!, get_slot_at,
       # from Description.jl
       describe_operation, describe_reference

include("OperationInterface.jl")
include("OperationDefaults.jl")
include("Operations.jl")
include("PathChain.jl")
include("Rerooting.jl")
include("Inversion.jl")
include("Description.jl")

end # module
