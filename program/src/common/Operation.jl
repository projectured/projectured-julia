"""
    OperationModule

Default evaluate_operation methods for built-in operations. Loaded after
EditorModule so the Editor type is available.
"""
module OperationModule

import ..OperationApiModule: Operation, evaluate_operation
import ..DocumentApiModule: clear_selection!, set_selection!
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, FieldReference, RangeReference, is_element_reference
import ..ReactiveModule: Cell
export ReplaceSelectionOperation, QuitEditorOperation, QuitEditorException, replace_selection!

function evaluate_operation(op::Nothing, document) end

# Fallback for any other input (e.g., raw events returned by reader)
function evaluate_operation(op, document) end

struct QuitEditorException <: Exception end

"""
    QuitEditorOperation()

Operation that signals the editor loop to stop.
Produced when the user closes the window or presses Escape.
"""
struct QuitEditorOperation <: Operation end

function evaluate_operation(op::QuitEditorOperation, document)
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

function evaluate_operation(op::ReplaceSelectionOperation, document)
    clear_selection!(document)
    set_selection!(document, op.path)
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
