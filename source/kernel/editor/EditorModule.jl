"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

using ..ProjectionModule
using ..IntentModule
using ..IoMapModule
using ..DeviceModule
using ..BackendModule
using ..EventModule
using ..PerformanceModule
using ..ClockModule
using ..DocumentModule
using ..OperationModule
using ..GestureRecognizerModule
using ..ToolModule
using ..AgentModule
using ..FaultModule
using ..SelectionModule
using ..ReferenceModule
using ..CellModule
using ..FeedModule
import ..FeedModule: drain_changes!

export Editor, make_editor, run_editor!, read!, read_rooted_operation, evaluate!, print!, run_frame!,
       get_frame_clock_time,
       post_operation!, drain_operations!, is_editor_degraded,
       get_consecutive_fault_limit,
       is_editor_in_safe_mode, enter_safe_mode!, leave_safe_mode!,
       report_frame_faults!,
       InboxFeed, wake_editor!, drain_feeds!

include("Editor.jl")
include("Inbox.jl")
include("Feeds.jl")
include("ReadEvaluatePrint.jl")
include("SafeMode.jl")
include("FaultBarriers.jl")
include("EditorLoop.jl")

end # module
