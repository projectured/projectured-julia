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
- [`AppearanceOperations.jl`](AppearanceOperations.jl) — `AdjustZoomOperation`,
  `AdjustScaleOperation`, `ReplaceThemeValueOperation`, and the save and the load.
- [`AppearanceManagingProjection.jl`](AppearanceManagingProjection.jl) — the
  printer, the reader and the mappings of the wrapper.
- [`AppearanceWrapper.jl`](AppearanceWrapper.jl) — the `appearance` wrapper of
  `build_editor`.
- [`AppearanceToWidget.jl`](AppearanceToWidget.jl) — the appearance tab.
"""
module AppearanceModule

using ..BackendModule
using ..CellModule
using ..DeviceModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..SelectionModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..ToolModule
using ..TooltipModule
using ..WidgetModule

import ..DocumentModule: get_wrapped_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default, make_wrapper_argument
import ..OperationModule: evaluate_operation, describe_operation, make_inverse_operation,
                          is_self_contained_operation, get_wrapped_operation,
                          rewrap_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

export AppearanceDocument, make_appearance_document, find_editor_appearance
export APPEARANCE_SCALES, AdjustZoomOperation, AdjustScaleOperation, copy_zoom_to_display!,
       ReplaceThemeValueOperation, SaveAppearanceOperation, LoadAppearanceOperation
export AppearanceManagingProjection, AppearanceManagingIoMap, is_appearance_change
export copy_system_colors!, follow_window_backgrounds!
export AppearanceToWidget, AppearanceToWidgetIoMap

include("AppearanceDocument.jl")
include("AppearanceOperations.jl")
include("AppearanceManagingProjection.jl")
include("AppearanceWrapper.jl")
include("AppearanceToWidget.jl")

# The natural renderer draws an `Appearance` as the appearance tab, with the
# widgets of the editor.
function __init__()
    register_natural_graphics!(:appearance, (; measure, appearance) -> begin
        widgets = WidgetToGraphics(; measure, theme = get_scaled_theme!(appearance, WidgetTheme),
                                   graphics_theme = get_scaled_theme!(appearance, GraphicsTheme))
        pane = last(only(row for row in widgets.dispatch if first(row) === WidgetScrollPane))
        Pair{Type,Any}[Appearance => AppearanceToWidget(; scroll_pane = pane)]
    end)
end

end # module AppearanceModule
