"""
    ProjecturedConversation

The conversation domain.

A chat with an assistant: the turn and part documents, the expression
evaluator, the syntax and widget projections, and the editor that drives the
loop.

A turn may carry a payload of any source domain — a JSON object, a Julia
expression — and this package names none of them. What a person may type into the
composer is whatever domain the session loaded and the natural-format seam can
read; `ProjecturedFileFormat` is that seam.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedConversation

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedFocus
using ProjecturedNatural
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedText
using ProjecturedWidget

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedFocus, ProjecturedNatural, ProjecturedKernel, ProjecturedLayout, ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle, ProjecturedText, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/conversation/ConversationModule.jl")

end # module ProjecturedConversation
