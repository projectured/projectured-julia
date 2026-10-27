"""
    ApplicationModule

The ProjecturEd application: a window that shows files, with a Files pane
and the assistant beside them, and the command line of the `projectured`
binary.

It names no domain, no backend and no adapter. A document of a domain draws
through the natural renderer, which each loaded domain registers itself with;
the model of the assistant is asked for by the name of its backend, through
`make_llm`; the window backend is the one a caller passes, or the loaded one
that [`default_backend`](@ref) finds. So the application shows every domain
that a session loads, and a session decides what it holds by what it loads:

    using Projectured, ProjecturedPlatform, ProjecturedSDL, ProjecturedOllama
    run_application("data.json")

[`run_application_workload`](@ref) runs the same window on a backend with no
device and gives it a list of clicks, keys and typed texts, so that the
`@compile_workload` of a package compiles the code that a person runs first.
"""
module ApplicationModule

using ..GraphicsModule
using ..KernelModule
using ..AppearanceModule
using ..ArrangementModule
using ..AssistantModule
using ..ClipboardModule
using ..CollectionModule
using ..ConversationModule
using ..DisplayModule
using ..DomainModule
using ..ExplorerModule
using ..FileFormatModule
using ..FaultViewModule
using ..FileSystemModule
using ..FocusModule
using ..FrameStatisticsModule
using ..BackgroundWorkModule
using ..GestureHelpModule
using ..GestureLogModule
using ..HelpModule
using ..InspectorModule
using ..McpLogModule
using ..MessageLogModule
using ..NaturalModule
using ..NavigatorModule
using ..PaneModule
using ..RosterModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ScreenModule
using ..SerializationModule
using ..SettingsManagingModule
using ..SettingsModule
using ..ShellModule
using ..StyleModule
using ..SystemProcessModule
using ..TaskModule
using ..TextModule
using ..TooltipModule
using ..TreeModule
using ..UndoModule
using ..WidgetModule

import ..LlmModule: stream_turn
import ..SettingsModule: is_settings_group_read_at_start
import ..TaskModule: make_task_api

export default_backend
export APPLICATION_ASSISTANTS, get_application_greeting_text, make_application_assistant,
       make_application_document, make_application_content_projections,
       make_application_projection, make_application_wrappers, make_application_window,
       make_editor_api, EDITOR_SYSTEM, APPLICATION_SYSTEM, make_domain_system,
       make_application_settings,
       run_application, parse_application_arguments, restart_with_window_threads!,
       run_application_command,
       evaluate_reachable_cells!, warm_application, register_editor_tools!, start_application!
export DrawnText, DrawnPart, WorkloadStep, WorkloadClick, WorkloadKey, WorkloadTyping, WorkloadWait,
       run_application_workload, run_window_workload, make_workload_llm
export StartSettings
export make_editor_explorer_content

include("DefaultBackend.jl")
include("Application.jl")
include("StartSettings.jl")
include("ApplicationExplorer.jl")
include("ApplicationWorkload.jl")

end # module ApplicationModule
