"""
    OperationModule

Default evaluate_operation methods for built-in operations. Loaded after
EditorModule so the Editor type is available.
"""
module OperationModule

import ..OperationApiModule: Operation, evaluate_operation
import ..DocumentApiModule: Document, clear_selection!, set_selection!
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference, is_element_reference, evaluate_reference
import ..ReactiveModule: Cell
export ReplaceSelectionOperation, QuitEditorOperation, QuitEditorException, replace_selection!,
       OpenWindowOperation, CloseWindowOperation, ToggleCollapseOperation,
       ReplaceDocumentOperation, CollectionInsertOperation, CollectionDeleteOperation

function evaluate_operation(editor, op::Nothing) end

# Fallback for any other input (e.g., raw events returned by reader)
function evaluate_operation(editor, op) end

struct QuitEditorException <: Exception end

"""
    QuitEditorOperation()

Operation that signals the editor loop to stop.
Produced when the user closes the window or presses Escape.
"""
struct QuitEditorOperation <: Operation end

function evaluate_operation(editor, op::QuitEditorOperation)
    throw(QuitEditorException())
end

"""
    ReplaceSelectionOperation(path)

Operation that replaces the current selection with `path`.
Produced by the reader side of the projection pipeline and applied to the
document by `evaluate_operation` in the editor loop.

Click-versus-keyboard disambiguation no longer rides on this operation: a
projection that gives a projection-introduced glyph a second, click-only meaning
— e.g. the inline expand/collapse marker in `SyntaxNodeToText`, which toggles on
click but must stay a plain cursor stop under `Ctrl+Home` / arrow keys — keys
that behaviour off the originating gesture (`change.gesture isa MousePress`),
which now rides through the reader chain in the `Change`.
"""
struct ReplaceSelectionOperation <: Operation
    path::ReferencePath
end

function evaluate_operation(editor, op::ReplaceSelectionOperation)
    document = editor.document
    clear_selection!(document)
    set_selection!(document, op.path)
end

"""
    ReplaceDocumentOperation(path, document)

Replace the document currently selected at `path` (a `ReferencePath` rooted at
`editor.document`) with `document`. This is the structural analogue of the
primitive replace-range operations: instead of editing the text inside a value,
it swaps the value itself — the move every JSON `json/read-command`
type-to-replace gesture makes (`[` → array, `{` → object, digit → number, …).

`document` carries its own initial selection (in its `selection` field, relative
to itself); after the swap the editor selection becomes `path ⧺ document.selection`
so the cursor lands inside the freshly-created value.

An empty `path` replaces the whole root: `editor.document` is rebound and the
cached iomap is dropped so the next `print!` rebuilds the projection on the new
root (a wholesale root swap is not reactive — every nested swap writes into a
`Cell` and stays incremental).
"""
struct ReplaceDocumentOperation <: Operation
    path::ReferencePath
    document::Document
end

function evaluate_operation(editor, op::ReplaceDocumentOperation)
    new_doc = op.document
    inner_sel = getfield(new_doc, :selection)[]
    inner_sel === nothing && (inner_sel = EmptyReferencePath())
    if op.path isa EmptyReferencePath
        editor.document = new_doc
        editor.iomap = nothing
        replace_selection!(new_doc, inner_sel)
        return
    end
    parent_path, terminal = _split_terminal_step(op.path)
    parent = evaluate_reference(editor.document, parent_path)
    _write_document_slot!(parent, terminal, new_doc)
    replace_selection!(editor.document, _concat_paths(op.path, inner_sel))
end

# Concatenate two reference *paths* (vs. `append_reference`, which appends raw
# *steps* — splicing a whole path there would wrongly lodge a ReferencePath where
# a ReferenceStep belongs).
_concat_paths(::EmptyReferencePath, b::ReferencePath) = b
_concat_paths(a::ConcreteReferencePath, b::ReferencePath) =
    ConcreteReferencePath(a.head, _concat_paths(a.tail, b))

# Split a non-empty path into (everything-but-last-step, last-step).
function _split_terminal_step(path::ConcreteReferencePath)
    steps = []
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    terminal = steps[end]
    prefix = EmptyReferencePath()
    for i in (length(steps) - 1):-1:1
        prefix = ConcreteReferencePath(steps[i], prefix)
    end
    (prefix, terminal)
end

# Write `new_doc` into the slot `step` selects on `parent`. A FieldReference
# names a `Cell`-backed document field (e.g. `JsonObjectEntry.value`); a
# RangeReference selects an element of a sequence container (`CellVector`).
function _write_document_slot!(parent, step::FieldReference, new_doc)
    f = getfield(parent, Symbol(step.name))
    f isa Cell || error("ReplaceDocumentOperation: field $(step.name) of $(typeof(parent)) is not a Cell")
    f[] = new_doc
end

function _write_document_slot!(parent, step::RangeReference, new_doc)
    parent[step.start + 1] = new_doc
end

"""
    CollectionInsertOperation(path, index, items[, selection])

Insert each of `items` into the sequence container at `path` (a `CellVector`
such as a JSON array's `.elements` or object's `.entries`), starting at the
0-based `index`. When `selection` is non-`nothing` the editor selection is moved
there afterwards (the reader uses this to drop the cursor into the new element —
matching the Lisp `make-operation/compound` of a sequence insert plus a
replace-selection).
"""
struct CollectionInsertOperation <: Operation
    path::ReferencePath
    index::Int
    items::Vector{Any}
    selection::Union{ReferencePath, Nothing}
end

CollectionInsertOperation(path, index, items) =
    CollectionInsertOperation(path, index, Vector{Any}(items), nothing)

function evaluate_operation(editor, op::CollectionInsertOperation)
    container = evaluate_reference(editor.document, op.path)
    for (k, item) in enumerate(op.items)
        insert!(container, op.index + k, Cell(item))
    end
    op.selection === nothing && return
    replace_selection!(editor.document, op.selection)
end

"""
    CollectionDeleteOperation(path, index, count)

Remove `count` elements from the sequence container at `path`, starting at the
0-based `index`. The defined inverse of `CollectionInsertOperation`, so undo can
build on the pair.
"""
struct CollectionDeleteOperation <: Operation
    path::ReferencePath
    index::Int
    count::Int
end

CollectionDeleteOperation(path, index) = CollectionDeleteOperation(path, index, 1)

function evaluate_operation(editor, op::CollectionDeleteOperation)
    container = evaluate_reference(editor.document, op.path)
    for _ in 1:op.count
        deleteat!(container, op.index + 1)
    end
end

"""
    ToggleCollapseOperation([target])

Operation that flips the `collapsed` field of a single collapsible node.

`target` is the node whose `collapsed` cell should be toggled, or `nothing`.
A `nothing` target reaches the projection layer that owns the collapse state
(`SyntaxNodeToText`), which resolves it to the **innermost** collapsible node
containing the current selection before the operation propagates back up — so
the editor only ever evaluates an operation with a concrete `target`.

Two entry points produce it (see `SyntaxToText` / `TextToGraphics`):
- a keyboard chord (`Ctrl+.`), which carries no target and is resolved from
  the selection, and
- a click on the inline expand/collapse marker (or the collapsed ellipsis),
  which already carries the clicked node as its target.

The operation only affects *rendering*: the source document is untouched, so a
selection that pointed inside the just-collapsed subtree simply stops drawing a
cursor until the node is expanded again.
"""
struct ToggleCollapseOperation <: Operation
    target::Any
end

ToggleCollapseOperation() = ToggleCollapseOperation(nothing)

function evaluate_operation(editor, op::ToggleCollapseOperation)
    target = op.target
    target === nothing && return
    target.collapsed = !target.collapsed
end

"""
    OpenWindowOperation(; id, title, x, y, width, height, bg, style, content)

Operation that requests a new `WindowDocument` (with the given fields) be
added to the screen. Produced by `TooltipDecoratorProjection` when a
tooltip should become visible; intercepted by `WindowManagerProjection`,
which appends (or updates) the matching `WindowDocument` on its input
`ScreenDocument.windows`.

The fields mirror `WindowDocument`'s schema 1:1 — the manager hands them
straight through.
"""
struct OpenWindowOperation <: Operation
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
    bg::NTuple{4,UInt8}
    style::Symbol
    content::Document
end

OpenWindowOperation(; id::Symbol,
                      title::AbstractString = "",
                      x::Integer = -1,
                      y::Integer = -1,
                      width::Integer = 0,
                      height::Integer = 0,
                      bg::NTuple{4,Integer} = (UInt8(253), UInt8(246), UInt8(227), UInt8(255)),
                      style::Symbol = :tooltip,
                      content::Document) =
    OpenWindowOperation(id, String(title), Int(x), Int(y), Int(width), Int(height),
                        (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
                        style, content)

"""
    CloseWindowOperation(id)

Operation that requests the `WindowDocument` with the matching `id` be
removed from the screen. Produced by `TooltipDecoratorProjection` when a
tooltip should disappear; intercepted by `WindowManagerProjection`.
A close for an unknown id is silently ignored.
"""
struct CloseWindowOperation <: Operation
    id::Symbol
end

"""
    clear_selection!(document)

Recursively clears the selection from `document` and all its children.
Sets the document's `selection` field to `nothing` and traverses the reference
path to clear selections from nested structures.
"""
function clear_selection!(document)
    hasproperty(document, :selection) || return
    sel = getfield(document, :selection)
    path = sel[]
    sel[] = nothing
    path isa ConcreteReferencePath || return
    h = path.head
    rest = path.tail
    child = if h isa FieldReference
        sym = Symbol(h.name)
        f = getfield(document, sym)
        f isa Cell ? f[] : f
    elseif h isa RangeReference
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return
        document[idx]
    else
        return
    end
    clear_selection!(child)
end

"""
    set_selection!(document, path)

Recursively sets the selection on `document` and its children to `path`.
Sets the document's `selection` field to the given reference path and traverses
the path to set selections on nested structures.
"""
function set_selection!(document, path)
    if hasproperty(document, :selection)
        getfield(document, :selection)[] = path
    end
    path isa ConcreteReferencePath || return
    h = path.head
    rest = path.tail
    child = if h isa FieldReference
        sym = Symbol(h.name)
        f = getfield(document, sym)
        f isa Cell ? f[] : f
    elseif h isa RangeReference
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return
        document[idx]
    else
        return
    end
    set_selection!(child, rest)
end

"""
    replace_selection!(document, path)

Replaces the current selection on `document` with `path`.
This is equivalent to calling `clear_selection!(document)` followed by
`set_selection!(document, path)`, ensuring the old selection is fully cleared
before setting the new one.
"""
function replace_selection!(document, path)
    clear_selection!(document)
    set_selection!(document, path)
end

end # module
