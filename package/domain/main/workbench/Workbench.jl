"""
    WorkbenchModule

The workbench document domain — the IDE shell. A `WorkbenchWorkbench` holds
four `WorkbenchPage`s (navigation/editing/information/control), each hosting
panels (navigator, console, descriptor, operator, searcher, evaluator,
assistant).
"""
module WorkbenchModule

import ..CellModule: Cell, set_cell_function!, set_cell_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..TextModule: TextBlock
import ..PrimitiveModule: PrimitiveString
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart, ConversationDraft
import ..LlmModule: Llm
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep, RangeReferenceStep, EmptyReference, FieldReferenceStep, is_element_reference_step
import ..WorkspaceModule: Workspace, WorkspaceFolder
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: insert_elements, delete_elements
import ..JsonParserModule: jsonparse_file
import ..XmlParserModule: xmlparse_file
import ..JuliaParserModule: juliaparse_file
export WorkbenchDocument, title, set_cell_function!, DEFAULT_ASSISTANT_SYSTEM,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation

# ── WorkbenchDocument (abstract base) ────────────────────────────────────────

abstract type WorkbenchDocument <: Document end

# ── WorkbenchInsertion ───────────────────────────────────────────────────

@document struct WorkbenchInsertion <: WorkbenchDocument
    value::Any = nothing
end

# ── WorkbenchPage ─────────────────────────────────────────────────────────────

"""
    WorkbenchPage(elements)

A page within the workbench that holds a sequence of panel documents.
"""
@document struct WorkbenchPage <: WorkbenchDocument
    elements::CellVector = CellVector()
end

function WorkbenchPage(elements::Vector)
    WorkbenchPage(CellVector(Cell[Cell(x) for x in elements]), Cell(nothing))
end

# ── WorkbenchWorkbench ────────────────────────────────────────────────────────

"""
    WorkbenchWorkbench(navigation_page, editing_page, information_page, control_page)

The top-level workbench. Holds four `WorkbenchPage` panels: navigation on the
left, editing in the center, information across the bottom, and control on
the right.
"""
@document struct WorkbenchWorkbench <: WorkbenchDocument
    navigation_page::WorkbenchPage
    editing_page::WorkbenchPage
    information_page::WorkbenchPage
    control_page::WorkbenchPage
end

function WorkbenchWorkbench(navigation_page::WorkbenchDocument,
                             editing_page::WorkbenchDocument,
                             information_page::WorkbenchDocument,
                             control_page::WorkbenchDocument = WorkbenchPage([]))
    WorkbenchWorkbench(Cell(navigation_page), Cell(editing_page),
                       Cell(information_page), Cell(control_page),
                       Cell(nothing))
end

set_cell_function!(p::WorkbenchPage, f::Function) = (set_cell_function!(getfield(p.elements, :elements), () -> Cell[Cell(x) for x in f()]); p)

# ── WorkbenchNavigator ────────────────────────────────────────────────────────

const WORKBENCH_NAVIGATOR_TITLE = "Navigator"

"""
    WorkbenchNavigator(workspace)

The navigator panel.  `workspace` is a `Workspace` document containing
`WorkspaceFolder` entries.  Its title is the class-level constant `"Navigator"`.
"""
@document struct WorkbenchNavigator <: WorkbenchDocument
    workspace::Workspace  # required: keeps the 1-arg `WorkbenchNavigator(workspace)`
                          # ctor (macro Rule Y needs req≥1)
end


title(::WorkbenchNavigator) = WORKBENCH_NAVIGATOR_TITLE

# ── WorkbenchConsole ──────────────────────────────────────────────────────────

const WORKBENCH_CONSOLE_TITLE = "Console"

"""
    WorkbenchConsole(content)

The console panel.  `content` is a `TextBlock` value.  Its title is the
class-level constant `"Console"`.
"""
@document struct WorkbenchConsole <: WorkbenchDocument
    content::TextBlock = TextBlock()
end

function WorkbenchConsole(content::TextBlock)
    WorkbenchConsole(Cell(content), Cell(nothing))
end

title(::WorkbenchConsole) = WORKBENCH_CONSOLE_TITLE
set_cell_function!(c::WorkbenchConsole, f::Function) = (set_cell_function!(getfield(c, :content), f); c)

# ── WorkbenchDescriptor ───────────────────────────────────────────────────────

const WORKBENCH_DESCRIPTOR_TITLE = "Descriptor"

"""
    WorkbenchDescriptor(content)

The descriptor panel.  `content` is a `Reference` pointing to the
document node currently being described.  Its title is the class-level
constant `"Descriptor"`.
"""
@document struct WorkbenchDescriptor <: WorkbenchDocument
    content::Reference
end

function WorkbenchDescriptor(content::Reference)
    WorkbenchDescriptor(Cell(content), Cell(nothing))
end

title(::WorkbenchDescriptor) = WORKBENCH_DESCRIPTOR_TITLE

# ── WorkbenchOperator ─────────────────────────────────────────────────────────

const WORKBENCH_OPERATOR_TITLE = "Operator"

"""
    WorkbenchOperator()

The operator panel.  Its title is the class-level constant `"Operator"`.
"""
@document struct WorkbenchOperator <: WorkbenchDocument
end

title(::WorkbenchOperator) = WORKBENCH_OPERATOR_TITLE

# ── WorkbenchSearcher ─────────────────────────────────────────────────────────

const WORKBENCH_SEARCHER_TITLE = "Searcher"

"""
    WorkbenchSearcher()

The searcher panel.  Its title is the class-level constant `"Searcher"`.
"""
@document struct WorkbenchSearcher <: WorkbenchDocument
end

title(::WorkbenchSearcher) = WORKBENCH_SEARCHER_TITLE

# ── WorkbenchEvaluator ────────────────────────────────────────────────────────

const WORKBENCH_EVALUATOR_TITLE = "Evaluator"

"""
    WorkbenchEvaluator(content)

The evaluator panel.  `content` holds the evaluator toplevel document
(not yet ported to Julia; typed as `Any`).  Its title is the class-level
constant `"Evaluator"`.
"""
@document struct WorkbenchEvaluator <: WorkbenchDocument
    content::Any = nothing
end

function WorkbenchEvaluator(content)
    WorkbenchEvaluator(Cell(content), Cell(nothing))
end

title(::WorkbenchEvaluator) = WORKBENCH_EVALUATOR_TITLE
set_cell_function!(e::WorkbenchEvaluator, f::Function) = (set_cell_function!(getfield(e, :content), f); e)

# ── WorkbenchAssistant ────────────────────────────────────────────────────────

const WORKBENCH_ASSISTANT_TITLE = "Assistant"
const DEFAULT_ASSISTANT_MODEL  = "claude-opus-4-8"
"""
    DEFAULT_ASSISTANT_SYSTEM

Shared system / instruction prompt for any AI assistant working against the
editor: the `system` field of an in-editor `WorkbenchAssistant`, and the
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
    WorkbenchAssistant(; conversation, input, model, system, api_key, status, llm)

The assistant panel. Holds the full chat history (`conversation`), the
editable prompt (`input`, a `PrimitiveString` so the existing text-edit
projections route `KeyPress`/backspace/delete to it directly), the
Anthropic model id (`model`), the system prompt (`system`), the Anthropic
API key (`api_key`), a `status` symbol (`:idle`, `:streaming`, `:error`,
...), and a pluggable `llm::Llm` that decides how submit turns are
serviced (real Claude vs. a canned-reply fake).

`llm` defaults to `nothing` and `api_key` to empty: the backend and key are
resolved from `ENV["ANTHROPIC_API_KEY"]` **at submit time**, not here. This keeps
the choice out of the precompiled image — documents are built eagerly into
`const`s during precompilation (no key then), so resolving at construction would
freeze the wrong choice. Resolving lazily means a key exported before launch is
honoured. When a key is set *and* the opt-in `ProjecturedLlm` package is loaded,
the real Claude backend is discovered by reflection; otherwise submitting errors
with a clear message. Production `main` never fabricates a fake — tests/examples
that want offline behaviour pass an explicit `llm` (a `FakeLlm`/`ScriptedLlm`
from `ProjecturedKernelExample`, e.g. `FakeLlm("ok")`).
"""
@document struct WorkbenchAssistant <: WorkbenchDocument
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    model::String
    system::String
    api_key::String
    status::Symbol
    collapse_thinking::Bool
    llm::Union{Nothing,Llm}
end

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function WorkbenchAssistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              model::AbstractString = DEFAULT_ASSISTANT_MODEL,
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = "",
                              status::Symbol = :idle,
                              collapse_thinking::Bool = true,
                              llm::Union{Nothing,Llm} = nothing)
    a = WorkbenchAssistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(status),
                           Cell(collapse_thinking),
                           Cell(llm),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

title(::WorkbenchAssistant) = WORKBENCH_ASSISTANT_TITLE
set_cell_function!(a::WorkbenchAssistant, f::Function) = (set_cell_function!(getfield(a, :conversation), f); a)

# ── WorkbenchEditor ──────────────────────────────────────────────────────────

"""
    WorkbenchEditor(content; title, filename)

An open document entry within the workbench.  `content` is the document
tree (any type), `title` is a display string, and `filename` is the
path on disk.
"""
@document struct WorkbenchEditor <: WorkbenchDocument
    title::String
    filename::String
    content::Any
    follow_end::Bool
end

function WorkbenchEditor(content;
                        title::AbstractString="",
                        filename::AbstractString="",
                        follow_end::Bool=false)
    WorkbenchEditor(Cell(String(title)), Cell(String(filename)),
                   Cell(content), Cell(follow_end), Cell(nothing))
end

title(e::WorkbenchEditor) = e.title
set_cell_function!(e::WorkbenchEditor, f::Function) = (set_cell_function!(getfield(e, :content), f); e)

# ── Workbench manipulation (B1) ───────────────────────────────────────────────
#
# Workbench tab edits are expressed as operations: build the operation carrying
# its target `WorkbenchPage` and apply it with `evaluate_operation(editor, op)` —
# the same path the editor loop runs for a gesture. Find the page (and any tab)
# generically with `search_documents` / `search_references` (which walk through the
# ScreenDocument → WindowDocument → … wrapping); there is deliberately no bespoke
# imperative helper layer that re-navigates `editor.document`. See
# package/kernel/doc/finding-and-selecting.md and package/kernel/doc/operation.md.

# The `.elements` field path, shared by the open/close builders below.
const _WORKBENCH_ELEMENTS = ConcreteReference(FieldReferenceStep("elements"), EmptyReference())

"""
    WorkbenchOpenDocumentOperation(page, entry) -> operation

Open a workbench tab: append `entry` (a `WorkbenchEditor`) to `page`
(a `WorkbenchPage`). An **identity-rooted** sequence splice — `insert_elements`
with `root=page` appending at the end. Locate `page` with e.g.
`search_documents(editor.document, x -> x isa WorkbenchPage)` and apply with
`evaluate_operation(editor, WorkbenchOpenDocumentOperation(page, entry))`.
"""
WorkbenchOpenDocumentOperation(page::WorkbenchPage, entry::WorkbenchDocument) =
    insert_elements(_WORKBENCH_ELEMENTS, length(page.elements), Any[entry]; root=page)

"""
    WorkbenchCloseDocumentOperation(page, index) -> operation

Close the workbench tab at **1-based** `index` on `page` (a `WorkbenchPage`). An
identity-rooted splice — `delete_elements` with `root=page` at the 0-based
`index-1`. Locate `page` with `search_documents` / `search_references`.
"""
WorkbenchCloseDocumentOperation(page::WorkbenchPage, index::Integer) =
    delete_elements(_WORKBENCH_ELEMENTS, index - 1, 1; root=page)

end # module
