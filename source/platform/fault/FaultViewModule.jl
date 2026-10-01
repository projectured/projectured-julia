"""
    FaultViewModule

What a fault looks like: the report that stands where a projection failed, the
log that collects them, the barrier that catches, and the projections that draw
both.

The kernel's `FaultModule` holds what a fault **is** — the record, the store,
the barrier helper and the report cascade — and names no document and no
projection. This package holds what a fault **is shown as**. The two are the
same split as `ProjectionModule` in the kernel against
`ProjectionAlgebraModule` here: the kernel declares, the platform shows.

The module is `FaultViewModule` rather than `FaultModule` because both slices
are named `fault` and a module name means one thing.

Start here:

- `FaultCatchingProjection` wraps one step of a pipeline. A fault inside it
  costs one node rather than the editor.
- `FaultReport` is the mark it leaves in the output.
- `FaultLog` is the message log. Attach one to an editor and the frame fills it:
  `attach_fault_target!(editor.faults, log)`.

The module lives in these fragments, which share this namespace:

- [`FaultDocument.jl`](FaultDocument.jl) — `FaultReport`, `FaultLog`,
  `FaultLogEntry` and the `append_fault!` the kernel seam asks for.
- [`Catching.jl`](Catching.jl) — `FaultCatchingProjection` and its IoMap.
- [`FaultToSyntax.jl`](FaultToSyntax.jl), [`FaultToText.jl`](FaultToText.jl),
  [`FaultToWidget.jl`](FaultToWidget.jl) and
  [`FaultToGraphics.jl`](FaultToGraphics.jl) — one renderer per output domain, so
  a barrier can substitute a mark the next step already understands.
- [`FaultLogToSyntax.jl`](FaultLogToSyntax.jl) — the log as a document.
- [`FaultLogOverlay.jl`](FaultLogOverlay.jl) — the log as a panel over a window.
- [`FaultSafeMode.jl`](FaultSafeMode.jl) — the projection the editor falls back
  to when the printer has failed on every frame for long enough.
- [`FaultSettings.jl`](FaultSettings.jl) — `FaultSettings`, what a person
  chooses about a fault, and their apply to the policy of the editor.
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
import ..ProjectionModule: print_document, read_intent,
                           map_reference_forward, map_reference_backward

export FaultReport, FaultLog, FaultLogEntry, get_session_fault_log,
       format_fault_label, format_fault_report_message, clear_fault_log!,
       FaultCatchingProjection, FaultCatchingIoMap,
       FaultToSyntax, FaultToText, FaultToWidget, FaultToGraphics,
       FaultLogToSyntax, FaultLogOverlayProjection, FaultLogOverlayIoMap,
       make_fault_log_content_projection, make_fault_tolerant_projection,
       FAULT_LOG_BACKGROUND,
       FaultSafeModeProjection, FaultSafeModeIoMap,
       FaultSettings

include("FaultDocument.jl")    # the report, the log, and the seam answer
include("Catching.jl")         # the barrier inside the pipeline
include("FaultToSyntax.jl")    # a mark in the syntax domain
include("FaultToText.jl")      # a mark in the text domain
include("FaultToWidget.jl")    # a mark in the widget domain
include("FaultToGraphics.jl")  # a mark in the graphics domain
include("FaultLogToSyntax.jl") # the log as a document
include("FaultLogOverlay.jl")  # the log as a panel
include("FaultSafeMode.jl")    # what the editor shows when nothing else can be
include("FaultSettings.jl")    # what a person chooses about a fault

end # module
