"""
    ProjecturedWorkbenchTest

The Workbench tier of the test-package DAG: the suites whose fixtures are workbench
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_workbench()`.
"""
module ProjecturedWorkbenchTest

using Test
import ProjecturedBase
import ProjecturedConversation
import ProjecturedFileSystem
import ProjecturedJson
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedMarkdown
import ProjecturedVisual
import ProjecturedWorkbench
import ProjecturedXml
import ProjecturedYaml
using ProjecturedConversationExample
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedWorkbenchExample

const _SOURCES = (ProjecturedBase, ProjecturedConversation, ProjecturedFileSystem, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedMarkdown, ProjecturedVisual, ProjecturedWorkbench, ProjecturedXml, ProjecturedYaml)

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

include("editor/AssistantMvpTest.jl")
include("projection/WorkbenchContentPaneTest.jl")
include("projection/WorkbenchTabClickTest.jl")

"""
    test_workbench_layering()

Static layered-architecture guard for `ProjecturedWorkbench`.
"""
function test_workbench_layering()
    main = normpath(dirname(pathof(ProjecturedWorkbench)))
    check_layering(main, joinpath(main, "ProjecturedWorkbench.jl");
                   name = "workbench",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedWorkbench; all = true)
                         if isdefined(ProjecturedWorkbench, n) &&
                            getfield(ProjecturedWorkbench, n) isa Module &&
                            getfield(ProjecturedWorkbench, n) !== ProjecturedWorkbench &&
                            parentmodule(getfield(ProjecturedWorkbench, n)) !== ProjecturedWorkbench))
end

"""
    test_workbench()

Run this package's whole suite: the layering guard and every workbench test.
"""
function test_workbench()
    @testset "ProjecturedWorkbench" begin
        test_workbench_layering()
        test_assistant_mvp()
        test_workbench_content_pane()
        test_workbench_tab_click()
    end
end

export test_workbench, test_workbench_layering, test_assistant_mvp
export test_workbench_content_pane, test_workbench_tab_click

end # module ProjecturedWorkbenchTest
