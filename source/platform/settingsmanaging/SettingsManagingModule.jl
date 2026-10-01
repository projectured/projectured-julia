"""
    SettingsManagingModule

The settings of an editor in its view: a document that holds the `Settings` of
the editor around the document that the editor shows, a projection that turns
each normal edit of a setting into an `ApplySettingOperation`, the commands of
the settings, and the `settings` wrapper of `build_editor`.

The editor holds no setting and reads none. A view of a settings group makes the
normal edit of a field, and `SettingsManagingProjection` is the one place that
turns it into a write and an apply.

- [`SettingsDocument.jl`](SettingsDocument.jl) — `SettingsDocument`, and the
  commands of the settings.
- [`SettingsManagingProjection.jl`](SettingsManagingProjection.jl) — the printer,
  the reader and the mappings of the wrapper.
- [`SettingsWrapper.jl`](SettingsWrapper.jl) — the `settings` wrapper of
  `build_editor`, and its start step.
"""
module SettingsManagingModule

using ..CellModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..SelectionModule
using ..SettingsModule

import ..DocumentModule: get_wrapped_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default,
                       make_wrapper_argument
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

export SettingsDocument, make_settings_document, make_toggle_setting_operation
export SettingsManagingProjection, SettingsManagingIoMap, wrap_setting_writes
export start_settings!

include("SettingsDocument.jl")
include("SettingsManagingProjection.jl")
include("SettingsWrapper.jl")

end # module SettingsManagingModule
