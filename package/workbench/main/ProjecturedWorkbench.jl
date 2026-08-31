"""
    ProjecturedWorkbench

The workbench application.

The top of the domain stack: a workspace of open documents, its tab and pane
shell, the widget projection that draws it, the assistant panel, and the file
wrapper that saves a whole workbench.

It opens a document of any kind, and it names none of them: a file is read by
`import_document`, which asks the natural-format seam, and the assistant's
fenced blocks go the same way. Which kinds a session can open is therefore the
caller's choice of packages, not this one's dependency list.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedWorkbench

using ProjecturedCollection
using ProjecturedConversation
using ProjecturedFileFormat
using ProjecturedFileSystem
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget
using ProjecturedConversation
using ProjecturedFileSystem

for _src in (ProjecturedCollection, ProjecturedConversation, ProjecturedFileFormat, ProjecturedFileSystem, ProjecturedKernel, ProjecturedLayout, ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedWidget)
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

# What a draft's ENTER and ALT+ENTER mean. Runtime state in the composer's own
# package, so it is registered on load rather than baked into an image — and
# from HERE, because Julia calls `__init__` on a package's top-level module only.
__init__() = WorkbenchAssistantModule.register_draft_handlers!()

end # module ProjecturedWorkbench
