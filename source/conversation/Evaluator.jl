"""
    ConversationModule

The evaluator document domain — a code form paired with the result of
evaluating it. Modeled on the Common Lisp ProjecturEd `evaluator.lisp`:

- `EvaluatorForm`     — one `form` (the code, e.g. a `JuliaDocument`) and its
                        `result` (a result document; `TextBlock` of the output
                        for now — richer result documents are future work).
- `EvaluatorToplevel` — a sequence of `EvaluatorForm`s (a notebook / REPL
                        toplevel).

`is_error` and `tool_use_id` are protocol metadata for the Anthropic tool
round-trip (an assistant `tool_use` paired with a `tool_result`); the
conceptual core is the two fields `form` + `result`.
"""
module ConversationModule

using ..CellModule
import ..CellModule: set_cell_function!
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..TextModule
export EvaluatorDocument, make_evaluator_result_text, get_evaluation_kind_label
export ConversationDocument, make_conversation_thinking_part
using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..NaturalModule
using ..WidgetModule
using ..LayoutModule
using ..StyleModule
using ..IoMapModule
using ..OperationModule
import ..OperationModule: evaluate_operation
using ..PrimitiveModule
using ..EventModule
using ..ProjectionAlgebraModule
using ..PrinterContextModule
export ConversationConversationToWidgetComposite,
       ConversationTurnToWidgetComposite,
       ConversationPartToWidget,
       ConversationToWidget
using ..DomainModule
using ..ToolModule
using ..GestureBindingModule
using ..EventPatternModule
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings
export ConversationComposerToWidget, read_composer_gesture, resolve_composer_host_operation,
       finalize_draft!, make_conversation_draft, reset_draft!,
       make_submit_operation, make_evaluate_operation,
       ComposerInputOperation, ComposerBackspaceOperation, ComposerNewlineOperation,
       ComposerInsertPartOperation, ComposerCommitChooserOperation,
       ComposerCommitSourceOperation, ComposerEvaluateOperation,
       ComposerRevertOperation, ComposerSubmitOperation
export ConversationConversation, EvaluatorForm, ConversationTurn, ConversationPart, ConversationDraft




# ── Abstract base ────────────────────────────────────────────────────────────

abstract type EvaluatorDocument <: Document end

# ── EvaluatorForm ────────────────────────────────────────────────────────────

"""
    EvaluatorForm(form; source, result, is_error, tool_use_id, tool_name)

A code form paired with its evaluation result. `form` is the code document
(a `JuliaDocument`); `result` is the result document (`TextBlock` for now).

`source` is the text the call was made with, **kept as it arrived**. The form is
the *projection* of that text, and a projection is not reversible in general: a
snippet that does not parse is held as a `PrimitiveString`, whose stringification
is its constructor repr, and a snippet that does parse becomes an AST whose
printing is the printer's idea of the code rather than the caller's. Either way a
caller that needs the original — a conversation replayed into a model's history —
must not re-derive it from the document. It reads `source`.

Empty `source` means the caller kept none, and a reader falls back to the form.
"""
@document struct EvaluatorForm <: EvaluatorDocument
    form::Document
    result::Document
    is_error::Bool
    tool_use_id::String
    tool_name::String
    source::String
end

EvaluatorForm(form::Document;
              result::Document = TextBlock(),
              is_error::Bool = false,
              tool_use_id::AbstractString = "",
              tool_name::AbstractString = "execute_julia_code",
              source::AbstractString = "") =
    EvaluatorForm(Cell(form), Cell(result), Cell(is_error),
                  Cell(String(tool_use_id)), Cell(String(tool_name)),
                  Cell(String(source)), Cell(nothing))

"""
    get_evaluation_kind_label(name::AbstractString) -> "eval" | "resource" | "tool"

Classify a tool-call form's header label by the tool that produced it:
`execute_julia_code` is an evaluation, `list_resources` / `read_resource`
are resource reads, everything else is a generic tool call.
"""
function get_evaluation_kind_label(name::AbstractString)
    name == "execute_julia_code" && return "eval"
    (name == "list_resources" || name == "read_resource") && return "resource"
    return "tool"
end
get_evaluation_kind_label(f::EvaluatorForm) = get_evaluation_kind_label(f.tool_name)

# Convenience: build a result document from a plain output string.
make_evaluator_result_text(s::AbstractString) = TextBlock(TextString(String(s)))

# ── EvaluatorToplevel ────────────────────────────────────────────────────────

"""
    EvaluatorToplevel(elements = [])

An ordered sequence of `EvaluatorForm`s.
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector = CellVector()
end
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(nothing))

set_cell_function!(t::EvaluatorToplevel, f::Function) =
    (set_cell_function!(getfield(t.elements, :elements), () -> Cell[Cell(x) for x in f()]); t)


include("ConversationDocument.jl")
include("ConversationToWidget.jl")
include("ConversationEditor.jl")

end # module
