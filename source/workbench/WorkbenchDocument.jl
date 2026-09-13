# ──────────────────────────────────────────────────────────────────────────
# Folded in from WorkbenchDocument.jl.
#
# The workbench document domain — the IDE shell. A `WorkbenchWorkbench` holds
# four `WorkbenchPage`s (navigation/editing/information/control), each hosting
# panels (navigator, console, descriptor, operator, searcher, evaluator,
# assistant).
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


get_workbench_title(::WorkbenchNavigator) = WORKBENCH_NAVIGATOR_TITLE

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

get_workbench_title(::WorkbenchConsole) = WORKBENCH_CONSOLE_TITLE
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

get_workbench_title(::WorkbenchDescriptor) = WORKBENCH_DESCRIPTOR_TITLE

# ── WorkbenchOperator ─────────────────────────────────────────────────────────

const WORKBENCH_OPERATOR_TITLE = "Operator"

"""
    WorkbenchOperator()

The operator panel.  Its title is the class-level constant `"Operator"`.
"""
@document struct WorkbenchOperator <: WorkbenchDocument
end

get_workbench_title(::WorkbenchOperator) = WORKBENCH_OPERATOR_TITLE

# ── WorkbenchSearcher ─────────────────────────────────────────────────────────

const WORKBENCH_SEARCHER_TITLE = "Searcher"

"""
    WorkbenchSearcher()

The searcher panel.  Its title is the class-level constant `"Searcher"`.
"""
@document struct WorkbenchSearcher <: WorkbenchDocument
end

get_workbench_title(::WorkbenchSearcher) = WORKBENCH_SEARCHER_TITLE

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

get_workbench_title(::WorkbenchEvaluator) = WORKBENCH_EVALUATOR_TITLE
set_cell_function!(e::WorkbenchEvaluator, f::Function) = (set_cell_function!(getfield(e, :content), f); e)

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

get_workbench_title(e::WorkbenchEditor) = e.title
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
