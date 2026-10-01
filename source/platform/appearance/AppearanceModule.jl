"""
    AppearanceModule

The appearance of an editor in its view: a document that holds the `Appearance`
of the editor around the document that the editor shows, a projection that
makes the view print again after a change of the appearance, the operations
that step the zoom and the scales, their keys, and the `appearance` wrapper of
`build_editor`.

The editor knows nothing about themes. A projection reads its scaled theme
through untracked style fields, which record no edge, so a change of a scale
reaches no cell of the view. `AppearanceManagingProjection` is the one place
that sees such a change: it adds `InvalidateProjectionOperation` to the answer,
and the editor prints the whole view again.

- [`AppearanceDocument.jl`](AppearanceDocument.jl) — `AppearanceDocument`, and
  the keys of the zoom and the scales.
- [`AppearanceOperations.jl`](AppearanceOperations.jl) — `AdjustZoomOperation`
  and `AdjustScaleOperation`.
- [`AppearanceManagingProjection.jl`](AppearanceManagingProjection.jl) — the
  printer, the reader and the mappings of the wrapper.
- [`AppearanceWrapper.jl`](AppearanceWrapper.jl) — the `appearance` wrapper of
  `build_editor`.
"""
module AppearanceModule

using ..CellModule
using ..DeviceModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule

import ..DocumentModule: get_wrapped_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default, make_wrapper_setting
import ..OperationModule: evaluate_operation, describe_operation, make_inverse_operation,
                          operation_travels_unchanged
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

export AppearanceDocument, make_appearance_document
export AdjustZoomOperation, AdjustScaleOperation, APPEARANCE_SCALES, copy_zoom_to_display!
export AppearanceManagingProjection, AppearanceManagingIoMap, is_appearance_change

include("AppearanceDocument.jl")
include("AppearanceOperations.jl")
include("AppearanceManagingProjection.jl")
include("AppearanceWrapper.jl")

end # module AppearanceModule
