"""
    ProjecturedConversation

The conversation domain.

A chat with an assistant: the turn and part documents, the expression
evaluator, the syntax and widget projections, and the editor that drives the
loop.

A turn may carry a JSON, Julia or XML payload, so this depends on those three
domains.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedConversation

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedJson
using ProjecturedJulia
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget
using ProjecturedXml
using ProjecturedJson
using ProjecturedJulia
using ProjecturedXml

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedWidget, ProjecturedXml)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Evaluator.jl")
include("Conversation.jl")
include("ConversationToSyntax.jl")
include("ConversationToWidget.jl")
include("ConversationEditor.jl")

end # module ProjecturedConversation
