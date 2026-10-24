"""
    AssistantModule

The assistant: a chat with a model that can act on the editor.

The document alone lives here — the conversation it holds, the prompt a person
types, the draft the composer edits, the model and the key it talks to, and the
`Llm` that services a turn. What a turn DOES is `AssistantModule`'s, and what
it looks like is `AssistantModule`'s.

It is a `Document` of its own, so a program that wants an assistant beside its
own panes does not carry an IDE to get one.

A turn has two kinds. With a model, the kernel's `run_turn!` drives the model
and runs its tools (`AssistantTurn.jl`). With an external agent, the agent runs
its own loop and its own tools, and the turn draws what it reports
(`ExternalAgentTurn.jl`).

The events of an external agent also fill the work of its session, an
`AgentWork`: its subagents with their transcripts, its plans, its background
tasks as tasks of the task slice, its notices and its processes
(`AgentWorkDocument.jl`). Each event of a session goes into the queue of the
session, in a prompt and between two prompts, and the feed of the window applies
the events in the order in which they came (`AgentEventFeed.jl`). The work page
of an assistant shows that work in a navigator, and a subagent has a page of its
own (`AssistantWorkDocument.jl`, `AssistantWorkToWidget.jl`,
`AgentWorkToWidget.jl`).
"""
module AssistantModule

using ..AgentModule
using ..BackendModule
using ..CellModule
using ..ClockModule
using ..CollectionModule
using ..ConversationModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..EventModule
using ..FaultModule
using ..FeedModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IoMapModule
using ..LayoutModule
using ..LlmModule
using ..NaturalModule
using ..NavigatorModule
using ..OperationModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..ScreenModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..SystemProcessModule
using ..TaskModule
using ..TerminalModule
using ..TextModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule
using ..WidgetModule
using ..WorkPlanModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..DocumentModule: copy_document, get_document_title, has_document_duplicate, is_walk_opaque
import ..DomainModule: accepts_pasted_document, accepts_opened_file, release_document!,
                       get_insertion_aliases, make_insertion_document, get_document_decoration
import ..EditorModule: wrap_editor!, get_wrapper_layers
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..OperationModule: evaluate_operation
import ..RosterModule: get_item_facets, compute_item_facet
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments, make_pred_document
import ..TaskModule: get_result_codes, format_task_parameters, get_task_columns,
                     format_task_column, format_task_details, get_task_actions
import ..TreeModule: get_tree_children_steps, format_tree_node_label, is_explorer_entry_type

export AgentBackgroundTask, AgentBackgroundTaskResult
export Assistant, ASSISTANT_TITLE, DEFAULT_ASSISTANT_SYSTEM, DEFAULT_AGENT_INSTRUCTIONS, DEFAULT_AGENT_COMMAND,
       DEFAULT_AGENT_SESSION_META, ASSISTANT_WORK_STATES, DEFAULT_ASSISTANT_ROUNDS
export AssistantToWidgetSplitPane, AssistantToWidgetCard
export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       EvaluateDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, format_conversation, write_conversation,
       parse_markdown_blocks
export register_assistant_api!, get_registered_assistant_api, describe_registered_assistant_api
export ExternalAgentSession, is_external_agent_turn_running, CancelAssistantTurnOperation,
       stop_external_agent!, StartExternalAgentOperation, SetAgentOptionOperation, SignOutAgentOperation,
       make_agent_option_bar, format_agent_usage, describe_agent_usage
export is_assistant_turn_running, make_assistant_stop_button, make_assistant_picture_button
export send_go_on!, GO_ON_PROMPT, wake_assistant!, ASSISTANT_WAKE_LIMIT
export AddDraftPictureOperation, register_picture_tools!
export compute_assistant_overview_title, find_first_prompt, find_last_prompt, compute_prompt_count,
       compute_assistant_turn_side, describe_assistant_activity, collect_open_assistant_requests,
       find_assistant_start_time,
       find_assistant_last_activity_time, compute_assistant_elapsed_time, compute_assistant_busy_time
export AssistantList, get_session_assistant_list, set_assistant_list_source!,
       set_assistant_list_opener!, select_assistant!, link_assistant_list!, unlink_assistant_list!
export AssistantListToWidgetPane
export apply_agent_event!, AgentEventFeed
export show_assistant_work!
export AssistantWorkToWidget
export AgentWorkToWidget


include("AgentWorkDocument.jl")
include("AssistantDocument.jl")
include("AssistantToWidget.jl")
include("AssistantTurn.jl")
include("ExternalAgentTurn.jl")
include("AssistantWake.jl")
include("AssistantPicture.jl")
include("AssistantOverview.jl")
include("AssistantList.jl")
include("AssistantListToWidget.jl")
include("AssistantApi.jl")
include("AgentEventFeed.jl")
include("AssistantWorkDocument.jl")
include("AssistantWorkToWidget.jl")
include("AgentWorkToWidget.jl")

end # module
