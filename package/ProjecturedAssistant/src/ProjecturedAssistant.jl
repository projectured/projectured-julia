"""
    ProjecturedAssistant

The assistant: a chat with a model that can act on the editor.

Three files. `Assistant.jl` is the document — the conversation, the prompt, the
draft, the model and the key, and the `Llm` that services a turn. `AssistantTurn.jl`
is what a turn does — the operations, the streaming, the tools it may call, and
the blocks an answer is split into. `AssistantToWidget.jl` is what it looks like.

It was part of `ProjecturedWorkbench`, whose other half is an IDE: a workspace, a
navigator, a console, a searcher, tabs and a file tree. A program that wants an
assistant beside its own panes had to carry all of it, and the six source domains
the IDE names with it.

**This package names no source domain.** What a person may type into the composer
and what a fenced block in an answer becomes are asked of the natural-format
seam, so they are the caller's choice of packages rather than this one's.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names itself.
"""
module ProjecturedAssistant

using ProjecturedCollection
using ProjecturedConversation
using ProjecturedDomain
using ProjecturedNatural
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedText
using ProjecturedWidget

for _src in (ProjecturedCollection, ProjecturedConversation, ProjecturedDomain,
             ProjecturedNatural, ProjecturedKernel, ProjecturedLayout,
             ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle,
             ProjecturedText, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/assistant/AssistantModule.jl")

using .AssistantModule

end # module ProjecturedAssistant
