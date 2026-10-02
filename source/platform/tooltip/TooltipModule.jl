"""
    TooltipModule

Two ways to show a tooltip window.

- **What a part says about itself.** A part answers a dwell of the pointer from
  its own gesture table ([`make_tooltip_binding`](@ref)) with an
  [`OpenTooltipOperation`](@ref), and each part around it adds its own layer.
  [`TooltipWindowProjection`](@ref) keeps the window: it opens it, shows more and
  fewer layers with F2 and Shift+F2, and closes it. The window holds a
  [`TooltipContent`](@ref), which the natural projection draws.
- **A source.** `TooltipSource` marks a sub-tree as a tooltip anchor, and the
  `TooltipDecoratorProjection` reader opens and closes the window of its
  `content`.
"""
module TooltipModule

using ..CellModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..SelectionModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_wrapped_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..GraphicsModule: map_operation_position
import ..OperationModule: is_collecting_operation, join_collected_operations, reroot_operation,
                          operation_reference, retarget_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_child_iomaps

export TooltipSource
export TooltipDecoratorProjection, TooltipDecoratorIoMap
export OpenTooltipOperation, make_tooltip_operation, make_tooltip_binding
export TooltipContent
export TooltipWindowState, TooltipWindowProjection, TooltipWindowIoMap
export make_tooltip_window_document, make_tooltip_window_projection, wrap_tooltip_window


include("TooltipDocument.jl")
include("TooltipDecorator.jl")
include("TooltipOperation.jl")
include("TooltipContent.jl")
include("TooltipWindow.jl")

end # module
