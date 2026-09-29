"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.

The module lives in eight fragments that share this namespace:

- [`Editor.jl`](Editor.jl) — `Editor`, its constructor, the invalidation of its
  projection, the editor as the start of a reference, and its fault store.
- [`Inbox.jl`](Inbox.jl) — `post_operation!`, `wake_editor!`,
  `drain_operations!`, and the calls that another task runs on the editor task.
- [`Feeds.jl`](Feeds.jl) — `InboxFeed`, the timeout of the wait, the frame
  measurements, and `drain_feeds!`.
- [`ReadEvaluatePrint.jl`](ReadEvaluatePrint.jl) — the three stages of a frame,
  `read!`, `evaluate!` and `print!`, and `read_rooted_operation`.
- [`DocumentEdits.jl`](DocumentEdits.jl) — `find_rooted_operation`,
  `insert_elements!` and `delete_elements!`.
- [`SafeMode.jl`](SafeMode.jl) — the safe mode, which shows the fault list in
  place of a projection that fails.
- [`FaultBarriers.jl`](FaultBarriers.jl) — the barrier of each stage, the report
  of the faults of a frame, the limits of the fault counts, and the repairs after
  an operation that failed.
- [`EditorLoop.jl`](EditorLoop.jl) — the counter log, `run_frame!`,
  `get_frame_clock_time`, `run_editor!` and `make_editor`.
"""
module EditorModule

using ..AgentModule
using ..BackendModule
using ..CellModule
using ..ClockModule
using ..DeviceModule
using ..DocumentModule
using ..EventModule
using ..FaultModule
using ..FeedModule
using ..GestureRecognizerModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..PerformanceModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..ToolModule

# Imported to extend: `InboxFeed` answers `drain_changes!` with the drain of the inbox.
import ..FeedModule: drain_changes!

export Editor, make_editor, run_editor!, read!, read_rooted_operation, evaluate!, print!, run_frame!,
       find_rooted_operation, insert_elements!, delete_elements!,
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
include("DocumentEdits.jl")
include("SafeMode.jl")
include("FaultBarriers.jl")
include("EditorLoop.jl")

end # module
