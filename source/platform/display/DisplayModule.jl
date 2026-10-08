"""
    DisplayModule

A value shown in an editor that runs beside the REPL.

[`display_in_editor`](@ref) shows a value in the editor of this process. The
document of the value is what `make_value_document` makes for it, so the
package that owns the value's type decides how it is shown, and this module
names no such package. A value that no loaded package gives a document is an
error. The editor draws with `NaturalToGraphics`, which asks the owner of each
document type for its projection.

The editor runs on a task of its own, which `run_editor!(...; wait = false)`
pins to a thread that is not the thread of the REPL. So the REPL keeps its
speed, and the window stays live while an input runs.

The module lives in two fragments:

- [`EditorDisplay.jl`](EditorDisplay.jl) — `EditorDisplay`,
  `display_in_editor`, `close_display_editor!` and the session of the editor.
- [`DisplayWorkload.jl`](DisplayWorkload.jl) — `run_display_workload`,
  `WorkloadBackend`, `make_workload_events` and `make_workload_table`: the first
  window and a first look at it, run by the `@compile_workload` of a package.
"""
module DisplayModule

using Base.ScopedValues: with
using ..AgentModule
using ..BackendModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..FaultModule
using ..GraphicsModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PerformanceModule
using ..ScreenModule
using ..StyleModule
using ..WidgetModule

import ..BackendModule: initialize_backend!, quit_backend!, take_from_devices!, write_to_devices!

export EditorDisplay, display_in_editor, close_display_editor!, refresh_display_editor!,
       WorkloadBackend, make_workload_events, make_workload_table, run_display_workload

include("EditorDisplay.jl")
include("DisplayWorkload.jl")

end # module DisplayModule
