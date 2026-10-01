"""
    ApplicationModule

The ProjecturEd application: a window that shows files, with a file navigator
and the assistant beside them, and the command line of the `projectured`
binary.

It names no domain, no backend and no adapter. A document of a domain draws
through the natural renderer, which each loaded domain registers itself with;
the model of the assistant is asked for by the name of its backend, through
`make_llm`; the window backend is the one a caller passes, or the loaded one
that [`default_backend`](@ref) finds. So the application shows every domain
that a session loads, and a session decides what it holds by what it loads:

    using Projectured, ProjecturedSdl, ProjecturedOllama
    run_application("data.json")
"""
module ApplicationModule

import InteractiveUtils: subtypes

using ..KernelModule
using ..AssistantModule
using ..CollectionModule
using ..ConversationModule
using ..DomainModule
using ..FileFormatModule
using ..FileSystemModule
using ..NaturalModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ScreenModule
using ..SerializationModule
using ..ShellModule
using ..StyleModule
using ..TextModule
using ..TooltipModule
using ..UndoModule
using ..WidgetModule

export default_backend
export run_application, start_application!, make_application_document,
       make_application_projection, make_application_window, make_application_api,
       APPLICATION_SYSTEM, make_application_assistant,
       make_application_content_projections, get_application_greeting_text,
       APPLICATION_ASSISTANTS, parse_application_arguments, run_application_command,
       warm_application, evaluate_reachable_cells!

include("DefaultBackend.jl")
include("Application.jl")

end # module ApplicationModule
