"""
    AssistantModule

The assistant: a chat with a model that can act on the editor.

The document alone lives here — the conversation it holds, the prompt a person
types, the draft the composer edits, the model and the key it talks to, and the
`Llm` that services a turn. What a turn DOES is `AssistantModule`'s, and what
it looks like is `AssistantModule`'s.

It is a `Document` of its own, so a program that wants an assistant beside its
own panes does not carry an IDE to get one.
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
import ..DomainModule: accepts_pasted_document, accepts_opened_file
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments

export Assistant, ASSISTANT_TITLE, DEFAULT_ASSISTANT_SYSTEM
export AssistantToWidgetSplitPane, AssistantToWidgetCard
export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       EvaluateDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, format_conversation, write_conversation,
       parse_markdown_blocks


include("AssistantDocument.jl")
include("AssistantToWidget.jl")
include("AssistantTurn.jl")

end # module
