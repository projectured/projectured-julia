"""
    ClipboardToAnyProjectionModule

The internal-clipboard projection — Julia port of Lisp's `clipboard/slice->t`
and `clipboard/collection->t` (`source/projection/primitive/clipboard-to-t.lisp`).

Two projections sit on top of the `ClipboardSlice` / `ClipboardCollection`
documents:

- `ClipboardSliceToAnyProjection` shows either the wrapped `content` or the stored
  `slice`, toggled by `Ctrl+/`. Copy / cut / note / paste gestures move the
  selected sub-document in and out of the slice.
- `ClipboardCollectionToAnyProjection` shows either the wrapped `content` or the
  `elements` collection, toggled by `Ctrl+*`. `Ctrl+=` adds the selected object
  to the collection; `Ctrl+-` removes the selected element.

Both delegate non-clipboard gestures into their `content` child reader and
re-root the returned operation under the `content` field (the School-A pattern —
delegate through the stored child IoMap, never re-walk by document type).

## Display toggling

The display flag swaps which child document becomes the output, so a toggle
cannot update reactively in place. The toggle operations therefore drop
`editor.iomap`, forcing the next `print!` to rebuild the projection on the new
flag (mirroring `ReplaceDocumentOperation`'s root-swap handling).

## Deferred (matches the Lisp `#+nil` branch)

Pasting from / copying to the **system** clipboard (Lisp shells out to `xclip`)
is not ported; only the internal clipboard is implemented.
"""
module ClipboardToAnyProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceDocumentOperation,
                          CollectionInsertOperation, CollectionDeleteOperation, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..ReactiveModule: Cell
import ..DocumentModule: Document
import ..DocumentCoreModule: DocumentNothing
import ..DocumentCopyModule: copy_document
import ..ClipboardModule: ClipboardSlice, ClipboardCollection
import ..CollectionModule: CellVector
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference, ElementReference,
                          evaluate_reference, head, tail
import ..PrinterContextModule: PrinterContext, child_context
import ..IoMapApiModule: IoMap
import ..KeyboardModule: KeyDown
import ..EventCaseModule: var"@event_case"

export ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
       ClipboardSliceToAnyProjectionIoMap, ClipboardCollectionToAnyProjectionIoMap,
       ToggleClipboardSliceDisplayOperation, ToggleClipboardCollectionDisplayOperation

# ── Projections ─────────────────────────────────────────────────────────────

"""
    ClipboardSliceToAnyProjection(; display_slice=false)

Projects a `ClipboardSlice`. When `display_slice` is `false` the output is the
projection of `content`; when `true` it is the projection of the stored `slice`
(falling back to `content` when no slice is stored).
"""
mutable struct ClipboardSliceToAnyProjection <: Projection
    display_slice::Bool
end
ClipboardSliceToAnyProjection(; display_slice::Bool=false) =
    ClipboardSliceToAnyProjection(display_slice)

"""
    ClipboardCollectionToAnyProjection(; display_collection=false)

Projects a `ClipboardCollection`. When `display_collection` is `false` the output
is the projection of `content`; when `true` it is a `CellVector` of the projected
`elements`.
"""
mutable struct ClipboardCollectionToAnyProjection <: Projection
    display_collection::Bool
end
ClipboardCollectionToAnyProjection(; display_collection::Bool=false) =
    ClipboardCollectionToAnyProjection(display_collection)

# ── IoMaps ────────────────────────────────────────────────────────────────────

struct ClipboardSliceToAnyProjectionIoMap <: IoMap
    projection::ClipboardSliceToAnyProjection
    input::Any              # ClipboardSlice
    output::Any             # content or slice child output
    content_iomap::Any
    slice_iomap::Any        # iomap of the stored slice, or nothing
end

struct ClipboardCollectionToAnyProjectionIoMap <: IoMap
    projection::ClipboardCollectionToAnyProjection
    input::Any              # ClipboardCollection
    output::Any             # content child output, or CellVector of element outputs
    content_iomap::Any
    element_iomaps::Any     # Vector of per-element child iomaps
end

# ── Printers ────────────────────────────────────────────────────────────────

function projection_print(p::ClipboardSliceToAnyProjection, recursion, input::ClipboardSlice, ctx)
    content_iomap = projection_printer_recurse(recursion, input.content,
                        child_context(ctx, FieldReference("content")))
    slice_val = input.slice
    slice_iomap = slice_val isa Document ?
        projection_printer_recurse(recursion, slice_val,
            child_context(ctx, FieldReference("slice"))) : nothing
    output = (p.display_slice && slice_iomap !== nothing) ? slice_iomap.output :
                                                            content_iomap.output
    ClipboardSliceToAnyProjectionIoMap(p, input, output, content_iomap, slice_iomap)
end

function projection_print(p::ClipboardCollectionToAnyProjection, recursion, input::ClipboardCollection, ctx)
    content_iomap = projection_printer_recurse(recursion, input.content,
                        child_context(ctx, FieldReference("content")))
    elements = input.elements
    element_iomaps = [projection_printer_recurse(recursion, elements[i],
                          child_context(ctx, FieldReference("elements"), ElementReference(i)))
                      for i in 1:length(elements)]
    output = p.display_collection ?
        CellVector(Cell[Cell(im.output) for im in element_iomaps]) :
        content_iomap.output
    ClipboardCollectionToAnyProjectionIoMap(p, input, output, content_iomap, element_iomaps)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the *active child's* output directly (no clipboard-shaped
# wrapper), so the forward and backward maps are asymmetric: forward peels the
# clipboard field step and returns the child's output reference unwrapped;
# backward delegates to the child and prepends the clipboard field step.

# Active child for a slice projection: ("field-name", child-iomap).
function _slice_active(iomap::ClipboardSliceToAnyProjectionIoMap)
    (iomap.projection.display_slice && iomap.slice_iomap !== nothing) ?
        ("slice", iomap.slice_iomap) : ("content", iomap.content_iomap)
end

function map_reference_forward(::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyProjectionIoMap, reference)
    reference isa ConcreteReferencePath || return reference
    name, child = _slice_active(iomap)
    h = head(reference)
    (h isa FieldReference && h.name == name) || return nothing
    map_reference_forward(child.projection, child, tail(reference))
end

function map_reference_backward(::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyProjectionIoMap, reference)
    name, child = _slice_active(iomap)
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReferencePath(FieldReference(name), mapped)
end

function map_reference_forward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyProjectionIoMap, reference)
    reference isa ConcreteReferencePath || return reference
    if iomap.projection.display_collection
        h = head(reference)
        (h isa FieldReference && h.name == "elements") || return nothing
        rest = tail(reference)
        rest isa ConcreteReferencePath || return nothing
        e = head(rest)
        e isa RangeReference || return nothing
        i = e.stop
        ims = iomap.element_iomaps
        (i < 1 || i > length(ims)) && return nothing
        child = ims[i]
        mapped = map_reference_forward(child.projection, child, tail(rest))
        mapped === nothing && return nothing
        ConcreteReferencePath(e, mapped)
    else
        h = head(reference)
        (h isa FieldReference && h.name == "content") || return nothing
        child = iomap.content_iomap
        map_reference_forward(child.projection, child, tail(reference))
    end
end

function map_reference_backward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyProjectionIoMap, reference)
    if iomap.projection.display_collection
        reference isa ConcreteReferencePath || return reference
        e = head(reference)
        e isa RangeReference || return nothing
        i = e.stop
        ims = iomap.element_iomaps
        (i < 1 || i > length(ims)) && return nothing
        child = ims[i]
        mapped = map_reference_backward(child.projection, child, tail(reference))
        mapped === nothing && return nothing
        ConcreteReferencePath(FieldReference("elements"), ConcreteReferencePath(e, mapped))
    else
        child = iomap.content_iomap
        mapped = map_reference_backward(child.projection, child, reference)
        mapped === nothing && return nothing
        ConcreteReferencePath(FieldReference("content"), mapped)
    end
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
    ToggleClipboardSliceDisplayOperation(projection)

Flip the `display_slice` flag of a `ClipboardSliceToAnyProjection`, swapping the
output between the wrapped content and the stored slice. Dropping `editor.iomap`
forces the next print to rebuild on the new flag.
"""
struct ToggleClipboardSliceDisplayOperation <: Operation
    projection::ClipboardSliceToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardSliceDisplayOperation)
    op.projection.display_slice = !op.projection.display_slice
    editor.iomap = nothing
end

"""
    ToggleClipboardCollectionDisplayOperation(projection)

Flip the `display_collection` flag of a `ClipboardCollectionToAnyProjection`.
"""
struct ToggleClipboardCollectionDisplayOperation <: Operation
    projection::ClipboardCollectionToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardCollectionDisplayOperation)
    op.projection.display_collection = !op.projection.display_collection
    editor.iomap = nothing
end

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReferencePath(FieldReference(name), EmptyReferencePath())

# The selected sub-document and its path, or (nothing, nothing) when there is no
# usable (non-empty) selection.
function _selected(input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing, nothing
    obj = try evaluate_reference(input, sel) catch; return nothing, nothing end
    sel, obj
end

# Copy: store an independent deep copy of the selected object in the slice. The
# write retargets the selection to `.slice` (ReplaceDocumentOperation moves the
# selection to where it writes), so a trailing ReplaceSelectionOperation restores
# the user's original selection on the copied source.
function _clipboard_copy(input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    CompoundOperation(Any[
        ReplaceDocumentOperation(_field_path("slice"), copy_document(obj)),
        ReplaceSelectionOperation(sel),
    ])
end

# Cut: store the live object in the slice and blank out its source position.
function _clipboard_cut(input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    CompoundOperation(Any[
        ReplaceDocumentOperation(_field_path("slice"), obj),
        ReplaceDocumentOperation(sel, DocumentNothing()),
    ])
end

# Note: like copy, but stores the live object (no deep copy). Restores the
# original selection after the slice write (see `_clipboard_copy`).
function _clipboard_note(input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    CompoundOperation(Any[
        ReplaceDocumentOperation(_field_path("slice"), obj),
        ReplaceSelectionOperation(sel),
    ])
end

# Paste: replace the selection target with the stored slice. The trailing
# ReplaceSelectionOperation pins the selection to the pasted target (rather than
# letting it follow the slice's stale inner selection).
function _clipboard_paste(input)
    slice = input.slice
    slice isa Document || return nothing
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing
    CompoundOperation(Any[
        ReplaceDocumentOperation(sel, slice),
        ReplaceSelectionOperation(sel),
    ])
end

# Paste-copy: like paste, but a fresh deep copy each time.
function _clipboard_paste_copy(input)
    slice = input.slice
    slice isa Document || return nothing
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing
    CompoundOperation(Any[
        ReplaceDocumentOperation(sel, copy_document(slice)),
        ReplaceSelectionOperation(sel),
    ])
end

# Add the selected object to the front of the collection (matches Lisp `push`).
function _clipboard_collection_add(input)
    _, obj = _selected(input)
    obj isa Document || return nothing
    CollectionInsertOperation(_field_path("elements"), 0, Any[obj])
end

# Remove the selected element from the collection.
function _clipboard_collection_remove(input)
    idx = _elements_index(input.selection)
    idx === nothing && return nothing
    CollectionDeleteOperation(_field_path("elements"), idx)
end

# 0-based index of the element a selection path addresses, or nothing when the
# path does not descend through `elements[i]`.
function _elements_index(path)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    (h isa FieldReference && h.name == "elements") || return nothing
    rest = path.tail
    rest isa ConcreteReferencePath || return nothing
    e = rest.head
    e isa RangeReference || return nothing
    e.start
end

# ── Readers ─────────────────────────────────────────────────────────────────

function projection_read(p::ClipboardSliceToAnyProjection, recursion, change::Change,
                         iomap::ClipboardSliceToAnyProjectionIoMap)
    input = iomap.input
    own = @event_case change.gesture begin
        KeyDown(:slash; ctrl)    => ToggleClipboardSliceDisplayOperation(p)
        KeyDown(:c; ctrl)        => _clipboard_copy(input)
        KeyDown(:x; ctrl)        => _clipboard_cut(input)
        KeyDown(:n; ctrl)        => _clipboard_note(input)
        KeyDown(:v; ctrl, shift) => _clipboard_paste_copy(input)
        KeyDown(:v; ctrl)        => _clipboard_paste(input)
    end
    own !== nothing && return Change(change.gesture, own)
    cim = iomap.content_iomap
    inner = projection_read(cim.projection, recursion, change, cim)
    Change(change.gesture, _prefix_op(inner.operation, (FieldReference("content"),)))
end

function projection_read(p::ClipboardCollectionToAnyProjection, recursion, change::Change,
                         iomap::ClipboardCollectionToAnyProjectionIoMap)
    input = iomap.input
    own = @event_case change.gesture begin
        KeyDown(:asterisk; ctrl) => ToggleClipboardCollectionDisplayOperation(p)
        KeyDown(:equals; ctrl)   => _clipboard_collection_add(input)
        KeyDown(:minus; ctrl)    => _clipboard_collection_remove(input)
    end
    own !== nothing && return Change(change.gesture, own)
    cim = iomap.content_iomap
    inner = projection_read(cim.projection, recursion, change, cim)
    Change(change.gesture, _prefix_op(inner.operation, (FieldReference("content"),)))
end

# 3-arg legacy shims (used by tests and any parent that hands a bare payload).
projection_read(p::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation
projection_read(p::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# ── Operation re-rooting ───────────────────────────────────────────────────────
# Prepend `steps` to the reference path carried by a delegated content operation,
# so it is rooted at the clipboard document rather than at `content`.

function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        ReplaceSelectionOperation(_prepend(steps, op.path))
    elseif op isa StringReplaceRangeOperation
        StringReplaceRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa NumberReplaceRangeOperation
        NumberReplaceRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceDocumentOperation
        ReplaceDocumentOperation(_prepend(steps, op.path), op.document)
    elseif op isa CollectionInsertOperation
        CollectionInsertOperation(_prepend(steps, op.path), op.index, op.items,
            op.selection === nothing ? nothing : _prepend(steps, op.selection))
    elseif op isa CollectionDeleteOperation
        CollectionDeleteOperation(_prepend(steps, op.path), op.index, op.count)
    else
        op
    end
end

function _prepend(steps::Tuple, path::ReferencePath)
    result = path
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

end # module
