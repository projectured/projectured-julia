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
       OpenWindowOperation, CloseWindowOperation, ToggleCollapseOperation, TreeNavigateOperation

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
    ReplaceSelectionOperation(path; from_click=false)

Operation that replaces the current selection with `path`.
Produced by the reader side of the projection pipeline and applied to the
document by `evaluate_operation` in the editor loop.

`from_click` records that the selection originated from a pointer gesture
(a mouse click) rather than keyboard navigation. A projection that gives a
projection-introduced glyph a second, click-only meaning — e.g. the inline
expand/collapse marker in `SyntaxNodeToText`, which toggles on click but must
stay a plain cursor stop under `Ctrl+Home` / arrow keys — keys that behaviour
off this flag. It is set by the click readers in `TextToGraphics` and defaults
to `false` everywhere else, so keyboard-derived selections never trip it.
"""
struct ReplaceSelectionOperation <: Operation
    path::ReferencePath
    from_click::Bool
end

ReplaceSelectionOperation(path) = ReplaceSelectionOperation(path, false)

function evaluate_operation(editor, op::ReplaceSelectionOperation)
    document = editor.document
    clear_selection!(document)
    set_selection!(document, op.path)
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
    TreeNavigateOperation(direction)

Operation that navigates the tree selection. `direction` is one of:
- `:root`  — select the root node (Ctrl+Alt+Home)
- `:up`    — select the parent node
- `:down`  — select the first child
- `:left`  — select the previous sibling
- `:right` — select the next sibling

Produced by the text-to-graphics layer when Alt+arrow/Home is pressed.
Resolved at the syntax layer where the tree structure is available.
"""
struct TreeNavigateOperation <: Operation
    direction::Symbol
end

function evaluate_operation(editor, op::TreeNavigateOperation)
    # Resolved upstream at the syntax layer; if it reaches the editor
    # unresolved, it becomes a ReplaceSelectionOperation which is evaluated
    # normally. This fallback is a no-op.
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
