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

import ..CellModule: Cell, set_cell_function!
import ..DocumentModule: Document, @document
import ..PrimitiveModule: PrimitiveString
import ..LlmModule: Llm
import ..ReferenceModule: Reference
import ..ConversationModule: ConversationConversation, ConversationDraft, ConversationPart
export Assistant, ASSISTANT_TITLE, DEFAULT_ASSISTANT_SYSTEM
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetSplitPane,
                       WidgetScrollPane, WidgetComposite, WidgetCard, Point2D, Inset,
                       inset_default
import ..LayoutModule: VerticalLayout, LayoutConstraint
import ..TextModule: TextBlock, TextString
import ..StyleModule: font_ubuntu_monospace_regular_20
import ..StyleModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap, IoMap,
                      reconcile_child_iomap, reconcile_child_iomaps, var"@iomap"
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..CollectionModule: CellVector, ComputedCellVector
import ..OperationModule: Operation, ReplaceSelectionOperation,
                          ReplaceReferencedValueOperation, CompoundOperation,
                          reroot_operation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..EventModule: KeyDown, KeyPress
import ..GestureBindingModule: read_gesture
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference, FieldReferenceStep,
                          RangeReferenceStep, ElementReferenceStep, PositionReferenceStep,
                          get_reference_steps, extend_reference, try_evaluate_reference,
                          annotate_reference_types, var"@reference", var"@reference_step",
                          var"@reference_case"
import ..PrinterContextModule: make_child_context
import ..ProjectionAlgebraModule: TypeDispatchingProjection
import ..ConversationModule: ConversationConversation, ConversationDraft
export AssistantToWidgetSplitPane, AssistantToWidgetCard
import ..OperationModule: Operation, evaluate_operation
import ..OperationModule
import ..ProjectionApiModule: read_intent
import ..CellModule: Cell, ComputedCell
import ..NaturalModule: parse_natural_text, has_natural_parser,
                                make_natural_projection, get_natural_extension,
                                print_natural_text
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep, EmptyReference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart,
                              ConversationThinking, make_conversation_thinking_part
import ..ConversationModule: EvaluatorForm, make_evaluator_result_text, get_evaluation_kind_label
import ..EventModule: KeyDown
import ..ToolModule: Tool, ToolSet, list_tools, call_tool,
                      register_default_tools!, execute_julia_code, get_last_evaluated_value
import ..EventModule: KeyPress
import ..EventPatternModule: var"@event_case"
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..AgentModule: Agent, run_turn!, AgentToolResult
import ..LlmModule: Llm, stream_turn, make_llm, get_llm_backend_names,
                     LlmRequest, LlmMessage, LlmContent,
                     LlmText, LlmThinking, LlmRedactedThinking, LlmToolUse, LlmToolResult,
                     LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
                     LlmThinkingStart, LlmThinkingDelta, LlmThinkingSignature, LlmThinkingStop,
                     LlmRedactedThinkingBlock,
                     LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
                     LlmTurnEnd, LlmFailure
import ..DocumentModule: Document
import ..ConversationModule: ConversationDraft
import ..ConversationModule: read_composer_gesture, resolve_composer_host_operation,
                                    ComposerSubmitOperation, ComposerEvaluateOperation,
                                    finalize_draft!, reset_draft!
export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       EvaluateDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, format_conversation, write_conversation,
       parse_markdown_blocks


# `@document` gives every document a `selection::Reference` slot.


const ASSISTANT_TITLE = "Assistant"
"""
    DEFAULT_ASSISTANT_SYSTEM

Shared system / instruction prompt for any AI assistant working against the
editor: the `system` field of an in-editor `Assistant`, and the
`instructions` field of the MCP server's `initialize` response. Keep the
two sites in sync by sourcing both from this constant.
"""
const DEFAULT_ASSISTANT_SYSTEM = "You are Claude working inside the ProjecturEd editor — a projectional editor built in Julia.\n\n" *
                                  "Use `execute_julia_code` to inspect and modify the editor's document and projection; " *
                                  "the variable `editor` is bound to the running editor.\n\n" *
                                  "MANDATORY — read this BEFORE writing any code:\n" *
                                  "- resource://guide/orientation  (the concept index — your starting point)\n" *
                                  "Everything else is on demand: the orientation lists the catalogues " *
                                  "(resource://guides, resource://modules) and the search tools, and points to the " *
                                  "specific guides (reference, selection, finding-and-selecting, operations, …). " *
                                  "Read whatever your task touches.\n\n" *
                                  "TO INSPECT OR CHANGE THE DOCUMENT — never hand-walk the document tree or write\n" *
                                  "bespoke helpers; use the general primitives (they work through any Screen/Window\n" *
                                  "wrapping and across every domain):\n" *
                                  "- `search_references(editor.document, query)` returns paths to matching document nodes.\n" *
                                  "- `search_documents(editor.document, query)` returns the matching document nodes themselves (each once).\n" *
                                  "  `query` is a predicate `node -> Bool`, or a `String`/`Regex` matching leaf text (which folds to its enclosing document; pass `raw=true` for the exact matched value).\n" *
                                  "- `evaluate_reference(editor.document, path)` resolves a path back to its node.\n" *
                                  "- Build an `Operation` and apply it with `evaluate_operation(editor, op)` — e.g. " *
                                  "`ReplaceSelectionOperation(path)` to select. This is the one way to change the document.\n" *
                                  "  See resource://guide/editor/finding-and-selecting and resource://guide/operations.\n\n" *
                                  "SCOPING A SEARCH TO A DOMAIN — the workbench renders the SAME document through\n" *
                                  "several projections (a JSON value also appears in syntax and text editors), so a\n" *
                                  "bare value match (e.g. \"Alice\" or `n isa AbstractString`) returns one hit per\n" *
                                  "projection and cannot tell them apart. Match the DOMAIN NODE TYPE instead, e.g.\n" *
                                  "`v -> v isa JsonString && v.value == \"Alice\"`, and/or first locate the document\n" *
                                  "with `search_documents(editor.document, x -> x isa JsonDocument)`.\n\n" *
                                  "STATE PERSISTS between `execute_julia_code` calls: a variable you assign at top\n" *
                                  "level in one call (e.g. `paths = search_references(...)`) is still bound in the\n" *
                                  "next call, so you can build up state incrementally instead of one giant block.\n\n" *
                                  "TO FIND A SPECIFIC API OR GUIDE — do this BEFORE writing code:\n" *
                                  "- Call the `search_api` tool to find the right module, struct, or function.\n" *
                                  "- Call the `search_documentation` tool to find the relevant guide section.\n" *
                                  "- Read full text with `read_resource(uri)`; read a function's full docs with " *
                                  "`read_function_documentation(\"Module\", \"name\")`.\n" *
                                  "- `list_resources` enumerates documentation/module/class resources if you need to browse.\n\n" *
                                  "NEVER guess names or signatures — search for them.\n" *
                                  "NEVER search in files, read files, or run shell commands — use the editor's search tools and resources."

"""
    Assistant(; conversation, input, backend, model, system, api_key, context, status, llm)

The assistant panel. Holds the full chat history (`conversation`), the
editable prompt (`input`, a `PrimitiveString` so the existing text-edit
projections route `KeyPress`/backspace/delete to it directly), the
`backend` that services a turn (`:anthropic`, `:ollama`), the model id
(`model`), the system prompt (`system`), the API key (`api_key`), a `status`
symbol (`:idle`, `:streaming`, `:error`, ...), and a pluggable `llm::Llm` that
overrides the backend entirely (a canned-reply fake, in a test).

**A person says which backend they want.** `backend` defaults to `:none`, and an
assistant that names none errors on submit with the list of backends whose
packages are loaded. Nothing is guessed: a guess was only ever right while one
backend existed.

`model` defaults to empty, which means "the backend's own default" — a model name
belongs to a provider, and a Claude id means nothing to a local server.

`context` is how many tokens of this conversation the model may see, and `0` leaves
the size to the backend. It is one of the three keywords every backend accepts, and
a backend it does not apply to ignores it: a hosted provider's window comes with the
model and cannot be set per request.

`llm` defaults to `nothing` and `api_key` to empty: the backend and key are
resolved **at submit time**, not here. This keeps the choice out of the
precompiled image — documents are built eagerly into `const`s during
precompilation (no key then), so resolving at construction would freeze the wrong
choice. Resolving lazily means a key exported before launch is honoured.
Production `main` never fabricates a fake — tests/examples that want offline
behaviour pass an explicit `llm` (a `FakeLlm`/`ScriptedLlm` from
`ProjecturedKernelExample`, e.g. `FakeLlm("ok")`).
"""
@document struct Assistant <: Document
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    backend::Symbol
    model::String
    system::String
    api_key::String
    context::Int
    status::Symbol
    collapse_thinking::Bool
    llm::Union{Nothing,Llm}
end

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function Assistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              backend::Symbol = :none,
                              model::AbstractString = "",
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = "",
                              context::Integer = 0,
                              status::Symbol = :idle,
                              collapse_thinking::Bool = true,
                              llm::Union{Nothing,Llm} = nothing)
    a = Assistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(backend), Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(Int(context)), Cell(status),
                           Cell(collapse_thinking),
                           Cell(llm),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

set_cell_function!(a::Assistant, f::Function) = (set_cell_function!(getfield(a, :conversation), f); a)


include("AssistantToWidget.jl")
include("AssistantTurn.jl")

end # module AssistantModule
