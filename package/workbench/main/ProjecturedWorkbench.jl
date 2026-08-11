"""
    ProjecturedWorkbench

The workbench application.

The top of the domain stack: a workspace of open documents, its tab and pane
shell, the widget projection that draws it, the assistant panel, and the file
wrapper that saves a whole workbench.

It opens documents of every kind, so it depends on the domains it can open.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedWorkbench

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual
using ProjecturedConversation
using ProjecturedFileSystem
using ProjecturedJson
using ProjecturedJulia
using ProjecturedMarkdown
using ProjecturedXml
using ProjecturedYaml

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual, ProjecturedConversation, ProjecturedFileSystem, ProjecturedJson, ProjecturedJulia, ProjecturedMarkdown, ProjecturedXml, ProjecturedYaml)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Workspace.jl")
include("Workbench.jl")
include("WorkspaceToFileSystem.jl")
include("WorkbenchToWidget.jl")
include("WorkbenchAssistant.jl")
include("WorkbenchFile.jl")

end # module ProjecturedWorkbench
