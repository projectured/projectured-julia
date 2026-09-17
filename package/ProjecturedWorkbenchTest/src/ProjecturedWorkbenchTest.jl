"""
    ProjecturedWorkbenchTest

The Workbench tier of the test-package DAG: the suites whose fixtures are workbench
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_workbench()`.
"""
module ProjecturedWorkbenchTest

using Test
import ProjecturedConversation
import ProjecturedFileSystem
import ProjecturedJson
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNatural
import ProjecturedFileFormat
import ProjecturedGestureLog
import ProjecturedGestureHelp
import ProjecturedInspector
import ProjecturedTooltip
import ProjecturedClipboard
import ProjecturedPane
import ProjecturedSyntax
import ProjecturedWidget
import ProjecturedText
import ProjecturedLayout
import ProjecturedScreen
import ProjecturedGraphics
import ProjecturedPlot
import ProjecturedVersioning
import ProjecturedFocus
import ProjecturedDragging
import ProjecturedReflection
import ProjecturedProjection
import ProjecturedComponent
import ProjecturedStyle
import ProjecturedSerialization
import ProjecturedDomain
import ProjecturedPrimitive
import ProjecturedCollection
import ProjecturedMarkdown
import ProjecturedWorkbench
import ProjecturedXml
import ProjecturedYaml
using ProjecturedConversationExample
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedWorkbenchExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedConversation, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFileSystem, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedMarkdown, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget, ProjecturedWorkbench, ProjecturedXml, ProjecturedYaml)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/workbench/editor/AssistantMvpTest.jl")
include("../../../test/workbench/editor/AssistantDuplicateTest.jl")
include("../../../test/workbench/projection/WorkbenchContentPaneTest.jl")
include("../../../test/workbench/projection/WorkbenchTabClickTest.jl")

include("../../../test/workbench/WorkbenchSuite.jl")

end # module ProjecturedWorkbenchTest
