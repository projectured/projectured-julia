"""
    ProjecturedWorkbench

The workbench application.

The top of the domain stack: a workspace of open documents, its tab and pane
shell, the widget projection that draws it, and the file wrapper that saves a
whole workbench.

The assistant is `ProjecturedAssistant`'s. It is a panel here like any other, and
a program that wants one beside its own panes takes that package alone.

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

using ProjecturedAssistant
using ProjecturedCollection
using ProjecturedConversation
using ProjecturedFileFormat
using ProjecturedFileSystem
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPane
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget
using ProjecturedConversation
using ProjecturedFileSystem

for _src in (ProjecturedAssistant, ProjecturedCollection, ProjecturedConversation, ProjecturedFileFormat, ProjecturedFileSystem, ProjecturedKernel, ProjecturedLayout, ProjecturedPane, ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/workbench/WorkbenchModule.jl")

# The draft's key handlers are registered by `ProjecturedAssistant`, which owns
# them now.

end # module ProjecturedWorkbench
