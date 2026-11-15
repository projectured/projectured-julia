"""
    SettingsManagingModule

The settings of an editor as a view that a person edits, with the commands of the
settings. The module holds a document that holds the `Settings` of the editor around
the document that the editor shows, a projection that turns each normal edit of a
setting into an `ApplySettingOperation`, the commands of the settings, and the
`settings` wrapper of `build_editor`.

The editor holds no setting and reads none. A view of a settings group makes the
normal edit of a field, and `SettingsManagingProjection` is the one place that
turns it into a write and an apply.

- [`SettingsDocument.jl`](SettingsDocument.jl) — `SettingsDocument`, and the
  commands of the settings.
- [`SettingsManagingProjection.jl`](SettingsManagingProjection.jl) — the printer,
  the reader and the mappings of the wrapper.
- [`SettingsWrapper.jl`](SettingsWrapper.jl) — the `settings` wrapper of
  `build_editor`, and its start step.
- [`SettingsGroupToWidget.jl`](SettingsGroupToWidget.jl) — the view of one group: the
  page of a group, and the body of its card in the settings tab.
- [`SettingsToWidget.jl`](SettingsToWidget.jl) — the view of the settings tab, and
  its row in the natural renderer.
"""
module SettingsManagingModule

using ..AgentModule
using ..CellModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
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
using ..SettingsModule
using ..StyleModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule
using ..WidgetModule

import ..DocumentModule: get_wrapped_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default,
                       make_wrapper_argument
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

import ..DomainModule: get_document_decoration, accepts_pasted_document
import ..SerializationModule: pred_arguments, make_pred_document
import ..TreeModule: get_tree_children_steps
export SettingsDocument, make_settings_document, find_editor_settings, describe_settings,
       change_setting!,
       make_toggle_setting_operation
export SettingsManagingProjection, SettingsManagingIoMap, wrap_setting_writes
export start_settings!
export SettingsToWidget, SettingsToWidgetIoMap, SettingsGroupToWidget, SettingsGroupToWidgetIoMap

include("SettingsDocument.jl")
include("SettingsManagingProjection.jl")
include("SettingsWrapper.jl")
include("SettingsGroupToWidget.jl")
include("SettingsToWidget.jl")

# The rows that let a tab draw the settings of an editor, and a page or a card draw
# one group. The factory form, so every renderer builds its own projection
# instances.
function __init__()
    register_natural_graphics!(:settings, (; measure, appearance) -> begin
        theme = get_scaled_theme!(appearance, WidgetTheme)
        widgets = WidgetToGraphics(; measure, theme,
                                   graphics_theme = get_scaled_theme!(appearance, GraphicsTheme))
        pane = last(only(row for row in widgets.dispatch if first(row) === WidgetScrollPane))
        Pair{Type,Any}[Settings => ChainingProjection(SettingsToWidget(; theme), pane),
                       SettingsGroup => ChainingProjection(SettingsGroupToWidget(; theme),
                                                           VerticalLayoutToGraphicsCanvas())]
    end)
end

end # module SettingsManagingModule
