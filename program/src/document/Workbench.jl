"""
    WorkbenchModule

The workbench document domain. Models the IDE-level workbench structure:
a top-level workbench split into three pages (navigation, editing,
information) that each host a sequence of panels. Panels are the navigator,
console, descriptor, operator, searcher, and evaluator. WorkbenchEntry
represents a single open document with title, filename, and content.
"""
module WorkbenchModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..TextModule: TextText
import ..ReferenceModule: Reference, ReferencePath
export WorkbenchDocument, WorkbenchInsertion, WorkbenchForeign,
       WorkbenchWorkbench, WorkbenchPage,
       WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
       WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
       WorkbenchAssistant,
       WorkbenchEditor,
       title, setfn!,
       IWorkbenchInsertion, IWorkbenchForeign,
       IWorkbenchWorkbench, IWorkbenchPage,
       IWorkbenchNavigator, IWorkbenchConsole, IWorkbenchDescriptor,
       IWorkbenchOperator, IWorkbenchSearcher, IWorkbenchEvaluator,
       IWorkbenchAssistant,
       IWorkbenchEditor

# ── WorkbenchDocument (abstract base) ────────────────────────────────────────

abstract type WorkbenchDocument <: Document end

# ── WorkbenchInsertion / WorkbenchForeign ───────────────────────────────

@document struct WorkbenchInsertion <: WorkbenchDocument
    value::Any
    selection::Reference
end
WorkbenchInsertion() = WorkbenchInsertion(Cell(nothing), Cell(nothing))

@document struct WorkbenchForeign <: WorkbenchDocument
    value::Any
    selection::Reference
end
WorkbenchForeign(value) = WorkbenchForeign(Cell(value), Cell(nothing))

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
    WorkbenchWorkbench(navigation_page, editing_page, information_page)

The top-level workbench.  Holds three `WorkbenchPage` panels arranged as
navigation, editing, and information columns.
"""
@document struct WorkbenchWorkbench <: WorkbenchDocument
    navigation_page::WorkbenchPage
    editing_page::WorkbenchPage
    information_page::WorkbenchPage
    selection::Reference
end

function WorkbenchWorkbench(navigation_page::WorkbenchDocument,
                             editing_page::WorkbenchDocument,
                             information_page::WorkbenchDocument)
    WorkbenchWorkbench(Cell(navigation_page), Cell(editing_page),
                       Cell(information_page), Cell(nothing))
end

function Base.show(io::IO, w::WorkbenchWorkbench)
    print(io, "WorkbenchWorkbench(navigation_page=", w.navigation_page,
          ", editing_page=", w.editing_page,
          ", information_page=", w.information_page, ")")
end

setfn!(p::WorkbenchPage, f::Function) = (setfn!(getfield(p.elements, :elements), () -> Cell[Cell(x) for x in f()]); p)

function Base.show(io::IO, p::WorkbenchPage)
    print(io, "WorkbenchPage(elements=", length(p.elements), ")")
end

# ── WorkbenchNavigator ────────────────────────────────────────────────────────

const WORKBENCH_NAVIGATOR_TITLE = "Navigator"

"""
    WorkbenchNavigator(folders)

The navigator panel.  `folders` is a sequence of file-system entries or
document nodes.  Its title is the class-level constant `"Navigator"`.
"""
@document struct WorkbenchNavigator <: WorkbenchDocument
    folders::CellVector
    selection::Reference
end

function WorkbenchNavigator(folders::Vector)
    WorkbenchNavigator(CellVector(Cell[Cell(x) for x in folders]), Cell(nothing))
end

WorkbenchNavigator() = WorkbenchNavigator(WorkbenchDocument[])

title(::WorkbenchNavigator) = WORKBENCH_NAVIGATOR_TITLE
setfn!(n::WorkbenchNavigator, f::Function) = (setfn!(getfield(n.folders, :elements), () -> Cell[Cell(x) for x in f()]); n)

function Base.show(io::IO, n::WorkbenchNavigator)
    print(io, "WorkbenchNavigator(folders=", length(n.folders), ")")
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

"""
    WorkbenchAssistant(content)

The assistant panel.  `content` holds the assistant toplevel document
(not yet ported to Julia; typed as `Any`).  Its title is the class-level
constant `"Assistant"`.
"""
@document struct WorkbenchAssistant <: WorkbenchDocument
    content::Any
    selection::Reference
end

function WorkbenchAssistant(content)
    WorkbenchAssistant(Cell(content), Cell(nothing))
end

WorkbenchAssistant() = WorkbenchAssistant(nothing)

title(::WorkbenchAssistant) = WORKBENCH_ASSISTANT_TITLE
setfn!(a::WorkbenchAssistant, f::Function) = (setfn!(getfield(a, :content), f); a)

function Base.show(io::IO, a::WorkbenchAssistant)
    print(io, "WorkbenchAssistant(content=", a.content, ")")
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
