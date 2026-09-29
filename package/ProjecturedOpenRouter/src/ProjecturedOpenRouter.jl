"""
    ProjecturedOpenRouter

Opt-in package: the Decisions API of OpenRouter as the relevance model of a
`ToolSet`. Depends on `ProjecturedKernel` plus HTTP/JSON3, and answers the
kernel's `RelevanceModel` with `make_openrouter_relevance_model`.

**Every piece of the wire format of the Decisions API lives here and nowhere
else.** The kernel asks a `RelevanceModel` for a probability per text and per
option; this package renders those questions as the `noul` and `choice`
questions of a decision model, such as Jev of TypeSafe, and reads the answers
back. Nothing in the kernel knows that `noul` or `usage.cost` exist.

Nothing binds the model by itself: a window that wants it calls
`set_relevance_model!` with it.
"""
module ProjecturedOpenRouter

using ProjecturedKernel

using HTTP
using JSON3

import ProjecturedKernel.ToolModule: RelevanceModel

include("../../../source/openrouter/OpenRouter.jl")

export make_openrouter_relevance_model

end # module ProjecturedOpenRouter
