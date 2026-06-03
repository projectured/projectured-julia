"""
    OperationModule

Default evaluate_operation methods for built-in operations. Loaded after
EditorModule so the Editor type is available.
"""
module OperationModule

import ..OperationApiModule: Operation, evaluate_operation
import ..DocumentApiModule: Document, clear_selection!, set_selection!
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, FieldReference, RangeReference, is_element_reference
import ..ReactiveModule: Cell
export ReplaceSelectionOperation, QuitEditorOperation, QuitEditorException, replace_selection!,
       OpenWindowOperation, CloseWindowOperation

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
