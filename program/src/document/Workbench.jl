"""
    WorkbenchModule

The workbench document domain. Models the IDE-level workbench structure:
a top-level workbench split into four pages (navigation, editing,
information, control) that each host a sequence of panels. Panels are
the navigator, console, descriptor, operator, searcher, evaluator, and
assistant. WorkbenchEntry represents a single open document with title,
filename, and content.
"""
module WorkbenchModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..TextModule: TextText
import ..PrimitiveModule: PrimitiveString
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart, ConversationDraft
import ..LlmModule: LlmBackend, FakeLlm, AnthropicLlm
import ..ReferenceModule: Reference, ReferencePath
import ..WorkspaceModule: Workspace, WorkspaceFolder
export WorkbenchDocument, WorkbenchInsertion,
       WorkbenchWorkbench, WorkbenchPage,
       WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
       WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
       WorkbenchAssistant,
       WorkbenchEditor,
       title, setfn!,
       IWorkbenchInsertion,
       IWorkbenchWorkbench, IWorkbenchPage,
       IWorkbenchNavigator, IWorkbenchConsole, IWorkbenchDescriptor,
       IWorkbenchOperator, IWorkbenchSearcher, IWorkbenchEvaluator,
       IWorkbenchAssistant,
       IWorkbenchEditor,
       DEFAULT_ASSISTANT_SYSTEM

# ── WorkbenchDocument (abstract base) ────────────────────────────────────────

abstract type WorkbenchDocument <: Document end

# ── WorkbenchInsertion ───────────────────────────────────────────────────

@document struct WorkbenchInsertion <: WorkbenchDocument
    value::Any
    selection::Reference
end
WorkbenchInsertion() = WorkbenchInsertion(Cell(nothing), Cell(nothing))

# ── WorkbenchPage ─────────────────────────────────────────────────────────────

"""
    WorkbenchPage(elements)

A page within the workbench that holds a sequence of panel documents.
"""
@document struct WorkbenchPage <: WorkbenchDocument
    elements::CellVector
    selection::Reference
end

function WorkbenchPage(elements::Vector)
    WorkbenchPage(CellVector(Cell[Cell(x) for x in elements]), Cell(nothing))
end

WorkbenchPage() = WorkbenchPage(WorkbenchDocument[])

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
    selection::Reference
end

function WorkbenchWorkbench(navigation_page::WorkbenchDocument,
                             editing_page::WorkbenchDocument,
                             information_page::WorkbenchDocument,
                             control_page::WorkbenchDocument = WorkbenchPage([]))
    WorkbenchWorkbench(Cell(navigation_page), Cell(editing_page),
                       Cell(information_page), Cell(control_page),
                       Cell(nothing))
end

function Base.show(io::IO, w::WorkbenchWorkbench)
    print(io, "WorkbenchWorkbench(navigation_page=", w.navigation_page,
          ", editing_page=", w.editing_page,
          ", information_page=", w.information_page,
          ", control_page=", w.control_page, ")")
end

setfn!(p::WorkbenchPage, f::Function) = (setfn!(getfield(p.elements, :elements), () -> Cell[Cell(x) for x in f()]); p)

function Base.show(io::IO, p::WorkbenchPage)
    print(io, "WorkbenchPage(elements=", length(p.elements), ")")
end

# ── WorkbenchNavigator ────────────────────────────────────────────────────────

const WORKBENCH_NAVIGATOR_TITLE = "Navigator"

"""
    WorkbenchNavigator(workspace)

The navigator panel.  `workspace` is a `Workspace` document containing
`WorkspaceFolder` entries.  Its title is the class-level constant `"Navigator"`.
"""
@document struct WorkbenchNavigator <: WorkbenchDocument
    workspace::Workspace
    selection::Reference
end

WorkbenchNavigator(workspace::Workspace) =
    WorkbenchNavigator(Cell(workspace), Cell(nothing))

WorkbenchNavigator() = WorkbenchNavigator(Workspace())

title(::WorkbenchNavigator) = WORKBENCH_NAVIGATOR_TITLE

function Base.show(io::IO, n::WorkbenchNavigator)
    print(io, "WorkbenchNavigator(workspace=", n.workspace, ")")
end

# ── WorkbenchConsole ──────────────────────────────────────────────────────────

const WORKBENCH_CONSOLE_TITLE = "Console"

"""
    WorkbenchConsole(content)

The console panel.  `content` is a `TextText` value.  Its title is the
class-level constant `"Console"`.
"""
@document struct WorkbenchConsole <: WorkbenchDocument
    content::TextText
    selection::Reference
end

function WorkbenchConsole(content::TextText)
    WorkbenchConsole(Cell(content), Cell(nothing))
end

WorkbenchConsole() = WorkbenchConsole(TextText())

title(::WorkbenchConsole) = WORKBENCH_CONSOLE_TITLE
setfn!(c::WorkbenchConsole, f::Function) = (setfn!(getfield(c, :content), f); c)

function Base.show(io::IO, c::WorkbenchConsole)
    print(io, "WorkbenchConsole(content=", c.content, ")")
end

# ── WorkbenchDescriptor ───────────────────────────────────────────────────────

const WORKBENCH_DESCRIPTOR_TITLE = "Descriptor"

"""
    WorkbenchDescriptor(content)

The descriptor panel.  `content` is a `ReferencePath` pointing to the
document node currently being described.  Its title is the class-level
constant `"Descriptor"`.
"""
@document struct WorkbenchDescriptor <: WorkbenchDocument
    content::ReferencePath
    selection::Reference
end

function WorkbenchDescriptor(content::ReferencePath)
    WorkbenchDescriptor(Cell(content), Cell(nothing))
end

title(::WorkbenchDescriptor) = WORKBENCH_DESCRIPTOR_TITLE

function Base.show(io::IO, d::WorkbenchDescriptor)
    print(io, "WorkbenchDescriptor(content=", d.content, ")")
end

# ── WorkbenchOperator ─────────────────────────────────────────────────────────

const WORKBENCH_OPERATOR_TITLE = "Operator"

"""
    WorkbenchOperator()

The operator panel.  Its title is the class-level constant `"Operator"`.
"""
@document struct WorkbenchOperator <: WorkbenchDocument
    selection::Reference
end

WorkbenchOperator() = WorkbenchOperator(Cell(nothing))

title(::WorkbenchOperator) = WORKBENCH_OPERATOR_TITLE

function Base.show(io::IO, ::WorkbenchOperator)
    print(io, "WorkbenchOperator()")
end

# ── WorkbenchSearcher ─────────────────────────────────────────────────────────

const WORKBENCH_SEARCHER_TITLE = "Searcher"

"""
    WorkbenchSearcher()

The searcher panel.  Its title is the class-level constant `"Searcher"`.
"""
@document struct WorkbenchSearcher <: WorkbenchDocument
    selection::Reference
end

WorkbenchSearcher() = WorkbenchSearcher(Cell(nothing))

title(::WorkbenchSearcher) = WORKBENCH_SEARCHER_TITLE

function Base.show(io::IO, ::WorkbenchSearcher)
    print(io, "WorkbenchSearcher()")
end

# ── WorkbenchEvaluator ────────────────────────────────────────────────────────

const WORKBENCH_EVALUATOR_TITLE = "Evaluator"

"""
    WorkbenchEvaluator(content)

The evaluator panel.  `content` holds the evaluator toplevel document
(not yet ported to Julia; typed as `Any`).  Its title is the class-level
constant `"Evaluator"`.
"""
@document struct WorkbenchEvaluator <: WorkbenchDocument
    content::Any
    selection::Reference
end

function WorkbenchEvaluator(content)
    WorkbenchEvaluator(Cell(content), Cell(nothing))
end

WorkbenchEvaluator() = WorkbenchEvaluator(nothing)

title(::WorkbenchEvaluator) = WORKBENCH_EVALUATOR_TITLE
setfn!(e::WorkbenchEvaluator, f::Function) = (setfn!(getfield(e, :content), f); e)

function Base.show(io::IO, e::WorkbenchEvaluator)
    print(io, "WorkbenchEvaluator(content=", e.content, ")")
end

# ── WorkbenchAssistant ────────────────────────────────────────────────────────

const WORKBENCH_ASSISTANT_TITLE = "Assistant"
const DEFAULT_ASSISTANT_MODEL  = "claude-opus-4-7"
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
                                  "MANDATORY — read these resources BEFORE writing any code:\n" *
                                  "1. resource://guides\n" *
                                  "2. resource://modules\n" *
                                  "3. resource://guide/getting-started\n" *
                                  "4. resource://guide/editor/reference\n" *
                                  "5. resource://guide/editor/selection\n\n" *
                                  "TO FIND A SPECIFIC API OR GUIDE — do this BEFORE writing code:\n" *
                                  "- Call the `search_api` tool to find the right module, struct, or function.\n" *
                                  "- Call the `search_documentation` tool to find the relevant guide section.\n" *
                                  "- Read full text with `read_resource(uri)`; read a function's full docs with " *
                                  "`read_function_documentation(\"Module\", \"name\")`.\n" *
                                  "- `list_resources` enumerates guide/module/class resources if you need to browse.\n\n" *
                                  "Prefer the high-level workbench/document manipulation helpers (find them via " *
                                  "`search_api(\"workbench\")`) over hand-writing reactive-cell mutations.\n\n" *
                                  "NEVER guess names or signatures — search for them.\n" *
                                  "NEVER search in files, read files, or run shell commands — use the editor's search tools and resources."

"""
    WorkbenchAssistant(; conversation, input, model, system, api_key, status, llm)

The assistant panel. Holds the full chat history (`conversation`), the
editable prompt (`input`, a `PrimitiveString` so the existing text-edit
projections route `KeyPress`/backspace/delete to it directly), the
Anthropic model id (`model`), the system prompt (`system`), the Anthropic
API key (`api_key`), a `status` symbol (`:idle`, `:streaming`, `:error`,
...), and a pluggable `llm::LlmBackend` that decides how submit turns are
serviced (real Claude vs. a canned-reply fake).

The default `llm` is `AnthropicLlm()` when `ANTHROPIC_API_KEY` is set,
`FakeLlm()` otherwise — so `run_example(assistant_example)` works offline.
"""
@document struct WorkbenchAssistant <: WorkbenchDocument
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    model::String
    system::String
    api_key::String
    status::Symbol
    llm::LlmBackend
    selection::Reference
end

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function WorkbenchAssistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              model::AbstractString = DEFAULT_ASSISTANT_MODEL,
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = get(ENV, "ANTHROPIC_API_KEY", ""),
                              status::Symbol = :idle,
                              llm::LlmBackend = isempty(api_key) ? FakeLlm() : AnthropicLlm())
    a = WorkbenchAssistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(status),
                           Cell(llm),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

title(::WorkbenchAssistant) = WORKBENCH_ASSISTANT_TITLE
setfn!(a::WorkbenchAssistant, f::Function) = (setfn!(getfield(a, :conversation), f); a)

function Base.show(io::IO, a::WorkbenchAssistant)
    print(io, "WorkbenchAssistant(model=", repr(a.model),
          ", status=:", a.status, ", conversation=", a.conversation, ")")
end

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
    selection::Reference
end

function WorkbenchEditor(content;
                        title::AbstractString="",
                        filename::AbstractString="")
    WorkbenchEditor(Cell(String(title)), Cell(String(filename)),
                   Cell(content), Cell(nothing))
end

title(e::WorkbenchEditor) = e.title
setfn!(e::WorkbenchEditor, f::Function) = (setfn!(getfield(e, :content), f); e)

function Base.show(io::IO, e::WorkbenchEditor)
    print(io, "WorkbenchEditor(title=", repr(e.title),
          ", filename=", repr(e.filename), ")")
end

end # module
