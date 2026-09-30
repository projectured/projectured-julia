"""
    ProjecturedDisplay

A value shown in an editor that runs beside the REPL. It shows any value that a
loaded package gives a document with `make_value_document`, and it depends on
no such package, no backend and no container of documents: a loaded backend
draws the window, and loaded tabs hold the values.

The submodules are aliased so this package's source file keeps its
`using ..XxxModule` form.
"""
module ProjecturedDisplay

using ProjecturedKernel
using ProjecturedNatural
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedWidget

const AgentModule = ProjecturedKernel.AgentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EditorModule = ProjecturedKernel.EditorModule
const OperationModule = ProjecturedKernel.OperationModule
const NaturalModule = ProjecturedNatural.NaturalModule
const ScreenModule = ProjecturedScreen.ScreenModule
const StyleModule = ProjecturedStyle.StyleModule
const WidgetModule = ProjecturedWidget.WidgetModule

include("../../../source/platform/display/DisplayModule.jl")

using .DisplayModule
export EditorDisplay, display_in_editor, close_display_editor!

end # module ProjecturedDisplay
