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

The module lives in one fragment:

- [`EditorDisplay.jl`](EditorDisplay.jl) — `EditorDisplay`,
  `display_in_editor`, `close_display_editor!` and the session of the editor.
"""
module DisplayModule

using ..AgentModule
using ..DocumentModule
using ..EditorModule
using ..NaturalModule
using ..OperationModule
using ..ScreenModule
using ..StyleModule
using ..WidgetModule

export EditorDisplay, display_in_editor, close_display_editor!

include("EditorDisplay.jl")

end # module DisplayModule
