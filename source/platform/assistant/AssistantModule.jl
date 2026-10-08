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
"""
module AssistantModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..ConversationModule
using ..DocumentModule
using ..EventModule
using ..EventModule
using ..FaultModule
using ..GestureBindingModule
using ..IoMapModule
using ..LayoutModule
using ..LlmModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..TextModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..DocumentModule: copy_document, get_document_title, has_document_duplicate
import ..DomainModule: accepts_pasted_document, accepts_opened_file, release_document!
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments

export Assistant, ASSISTANT_TITLE, DEFAULT_ASSISTANT_SYSTEM, DEFAULT_AGENT_COMMAND,
       DEFAULT_AGENT_SESSION_META
export AssistantToWidgetSplitPane, AssistantToWidgetCard
export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       EvaluateDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, format_conversation, write_conversation,
       parse_markdown_blocks
export register_assistant_api!, get_registered_assistant_api
export ExternalAgentSession, is_external_agent_turn_running, CancelAssistantTurnOperation,
       stop_external_agent!, StartExternalAgentOperation, SetAgentOptionOperation,
       make_agent_option_bar, format_agent_usage


include("AssistantDocument.jl")
include("AssistantToWidget.jl")
include("AssistantTurn.jl")
include("ExternalAgentTurn.jl")
include("AssistantApi.jl")

end # module
