"""
    ProjecturedConsole

The console backend. It renders the text domain to an ANSI terminal and needs
no third-party package, so the umbrella still aggregates it. It is a peer of
`ProjecturedSdl`, `ProjecturedWeb` and `ProjecturedPdf`, which is what a
concrete backend is.

The submodules below are aliased so this package's source file keeps its
relative `..XxxModule` references.
"""
module ProjecturedConsole

using ProjecturedKernel
using ProjecturedStyle
using ProjecturedText

const BackendModule = ProjecturedKernel.BackendModule
const EditorModule = ProjecturedKernel.EditorModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const TextModule = ProjecturedText.TextModule

include("../../../source/backend/console/ConsoleBackendModule.jl")

end # module ProjecturedConsole
