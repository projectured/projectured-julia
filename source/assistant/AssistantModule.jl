"""
    AssistantModule

The assistant: a chat with a model that can act on the editor.

The document alone lives here — the conversation it holds, the prompt a person
types, the draft the composer edits, the model and the key it talks to, and the
`Llm` that services a turn. What a turn DOES is `AssistantModule`'s, and what
it looks like is `AssistantModule`'s.

It was `ProjecturedWorkbench`'s, as a `WorkbenchDocument` beside the navigator and
the console. It is a `Document` of its own now, because a program that wants an
assistant beside its own panes should not carry an IDE to get one.
"""
module AssistantModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..ConversationModule
using ..DocumentModule
using ..EventModule
using ..EventPatternModule
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
using ..StyleModule
using ..TextModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_function!
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

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
