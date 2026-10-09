"""
    ConversationModule

This slice of `ProjecturedPlatform` holds the evaluator documents — a code
form paired with the result of evaluating it. Modeled on the Common Lisp
ProjecturEd `evaluator.lisp`:

- `EvaluatorForm`     — one `form` (the code, e.g. a `JuliaDocument`) and its
                        `result` (a result document; `TextBlock` of the output
                        for now — richer result documents are future work).
- `EvaluatorToplevel` — a sequence of `EvaluatorForm`s (a notebook / REPL
                        toplevel).

`is_error`, `tool_use_id`, `tool_name` and `input` are protocol metadata for
the tool round-trip (an assistant `tool_use` paired with a `tool_result`); the
conceptual core is the two fields `form` + `result`, and each of the two has
a fold of its own.
"""
module ConversationModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..EventModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule
using ..TextModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..DocumentModule: copy_document, get_document_title, has_document_duplicate
import ..DomainModule: accepts_pasted_document, accepts_pasted_text,
                       get_insertion_aliases
import ..FocusModule: is_selection_walk_stop
import ..SelectionModule: has_dormant_selection
import ..OperationModule: evaluate_operation
import ..SerializationModule: pred_arguments, make_pred_document
using ..SerializationModule: print_pred_text, FileCutException
import ..ProjectionModule: get_projection_gesture_bindings
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export EvaluatorDocument, make_evaluator_result_text, get_evaluation_kind_label, find_form_document,
       get_evaluation_title, get_evaluation_section_labels, make_evaluator_arguments_text,
       ToggleEvaluatorSectionOperation, EvaluateSelectedFormOperation,
       ToggleEvaluatorOptionOperation,
       RecallEvaluatorFormOperation
export ConversationDocument, make_conversation_thinking_part
export ConversationPermissionRequest, is_permission_request_open, answer_permission_request!
export ConversationTheme, ScaledConversationTheme
export ConversationConversationToWidgetComposite,
       ConversationTurnToWidgetComposite,
       ConversationPartToWidget,
       ConversationToWidget, compute_transcript_walk
export EvaluatorFormToVerticalLayout, EvaluatorToplevelToWidgetComposite,
       make_evaluator_form_projection, make_evaluator_toplevel_projection
export make_conversation_row, make_conversation_draft_row
export ConversationComposerToWidget, make_conversation_composer_projection,
       read_composer_gesture, resolve_composer_host_operation,
       finalize_draft!, make_conversation_draft, reset_draft!, sync_draft_selection!,
       make_draft_caret_reference,
       make_submit_operation, make_evaluate_operation,
       ComposerInputOperation, ComposerBackspaceOperation, ComposerNewlineOperation,
       ComposerInsertPartOperation, ComposerCommitChooserOperation,
       ComposerCommitSourceOperation, ComposerEvaluateOperation,
       ComposerRevertOperation, ComposerSubmitOperation
export ConversationConversation, EvaluatorForm, EvaluatorToplevel, ConversationTurn,
       ConversationPart, ConversationDraft


include("Evaluator.jl")
include("ConversationDocument.jl")
include("ConversationTheme.jl")
include("ConversationToWidget.jl")
include("EvaluatorToWidget.jl")
include("ConversationEditor.jl")
include("ConversationRows.jl")

end # module
