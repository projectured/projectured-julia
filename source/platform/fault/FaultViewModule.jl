"""
    FaultViewModule

What a fault looks like to a person: the log that collects the faults, the panel
and the tab that show it, the safe mode, and the gestures of a mark.

The kernel's `FaultModule` holds what a fault **is** — the record, the store,
the barrier helper and the report cascade — and names no document and no
projection. The barrier that catches inside a pipeline is a projection of the
algebra, `FaultCatchingProjection`, with the report it leaves, `FaultReport`,
and each domain draws that report with a mark of its own: `FaultToSyntax`,
`FaultToText`, `FaultToWidget`, `FaultToGraphics`. So every slice that builds a
pipeline can name its barriers. This package holds the rest of what a fault **is
shown as**.

The module is `FaultViewModule` rather than `FaultModule` because both slices
are named `fault` and a module name means one thing.

Start here:

- `FaultLog` is the message log. Attach one to an editor and the frame fills it:
  `attach_fault_target!(editor.faults, log)`.
- `make_fault_tolerant_projection` puts one barrier around a whole window and
  the log over it.

The module lives in these fragments, which share this namespace:

- [`FaultDocument.jl`](FaultDocument.jl) — `FaultLog`, `FaultLogEntry`, the
  `append_fault!` the kernel seam asks for, and the gestures of a `FaultReport`:
  the window that says the whole fault, and the menu that tries the part again.
- [`FaultLogToSyntax.jl`](FaultLogToSyntax.jl) — the log as a document.
- [`FaultLogOverlay.jl`](FaultLogOverlay.jl) — the log as a panel over a window.
- [`FaultSafeMode.jl`](FaultSafeMode.jl) — the projection the editor falls back
  to when the printer has failed on every frame for long enough.
- [`FaultSettings.jl`](FaultSettings.jl) — `FaultSettings`, what a person
  chooses about a fault, the `FaultPolicy` that they make, and their apply to
  the policy of the editor.
"""
module FaultViewModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..FaultModule
using ..GestureBindingModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..OperationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..TooltipModule
using ..WidgetModule
using ..FocusModule
using ..EditorModule
using ..SettingsModule

# The names this module EXTENDS are imported, never merely used: a bare
# `using` binds the name for reading and a definition beside it makes a NEW
# function in this module rather than a method on the kernel's. The pipeline
# then never finds it. PAR-QUALIFIED-EXTENSION is the rule, and the layering
# guard is what catches a file that forgets.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..FaultModule: append_fault!
import ..SettingsModule: apply_settings!, read_settings!, is_settings_group_applied
import ..SerializationModule: pred_arguments
import ..EditorModule: wrap_editor!, get_wrapper_layers
import ..StyleModule: get_theme_presets
import ..ProjectionModule: print_document, read_intent,
                           map_reference_forward, map_reference_backward

export FaultLog, FaultLogEntry, get_session_fault_log, clear_fault_log!,
       FaultTheme, ScaledFaultTheme,
       FaultLogToSyntax, make_fault_log_projection, FaultLogOverlayProjection, FaultLogOverlayIoMap,
       make_fault_log_content_projection, make_fault_tolerant_projection,
       make_fault_log_panel_theme,
       FaultSafeModeProjection, FaultSafeModeIoMap,
       FaultSettings, make_fault_policy

include("FaultDocument.jl")    # the log, the seam answer, and the gestures of a mark
include("FaultTheme.jl")       # the theme of the log
include("FaultLogToSyntax.jl") # the log as a document
include("FaultLogOverlay.jl")  # the log as a panel
include("FaultSafeMode.jl")    # what the editor shows when nothing else can be
include("FaultSettings.jl")    # what a person chooses about a fault

end # module
