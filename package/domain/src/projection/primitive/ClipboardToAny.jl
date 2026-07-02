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

The display flag is a `Cell`, and each projection's `output` is a derived cell over
it. Flipping the flag is a plain reactive cell write: the reactive
`SequentialProjection` re-pulls the changed output and re-prints only the downstream
stages, so the view switches with **no `editor.iomap` drop**. (Earlier this swap
required nulling `editor.iomap`; reactive composition makes that unnecessary.)

## OS-clipboard bridge (the Lisp `#+nil` `xclip` branch, now ported)

`ClipboardSliceToAnyProjection` takes optional `to_text` / `from_text` converters.
When set, copy/cut/note mirror the copied sub-document out to the OS clipboard (via a
`WriteOsClipboardOperation`), and `Ctrl+V` falls back to the OS clipboard when the
internal slice is empty. The actual OS read/write goes through
[`OsClipboardModule`](@ref) (shell-out to `xclip`/`xsel`/`wl-*`/`pb*`), which is
stubbable and degrades gracefully when no clipboard tool is present. With both
converters `nothing` (the default) there is no OS interaction — only the internal
clipboard, exactly as before.
"""
module ClipboardToAnyProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change, as_change
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValue, replace_document,
                          insert_elements, delete_elements, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation, PrimitiveString
import ..ReactiveModule: Cell
import ..DocumentModule: Document
import ..DocumentCoreModule: DocumentNothing
import ..DocumentModule: copy_document
import ..ClipboardModule: ClipboardSlice, ClipboardCollection
import ..TextModule: TextText, TextString, text_selection_substring, text_insert_op
import ..CollectionModule: CellVector
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference, ElementReference,
                          evaluate_reference, head, tail, strip_reference_types
import ..PrinterContextModule: PrinterContext, child_context
import ..IoMapApiModule: IoMap
import ..GestureBindingModule: GestureBinding, KeyDownPattern,
                              projection_gestures, read_projection_gesture, collect_gestures
import ..OsClipboardModule: os_clipboard_read, os_clipboard_write

export ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
       ClipboardSliceToAnyProjectionIoMap, ClipboardCollectionToAnyProjectionIoMap,
       ToggleClipboardSliceDisplayOperation, ToggleClipboardCollectionDisplayOperation,
       WriteOsClipboardOperation

# ── Projections ─────────────────────────────────────────────────────────────

"""
    ClipboardSliceToAnyProjection(; display_slice=false, to_text=nothing, from_text=nothing)

Projects a `ClipboardSlice`. When `display_slice` is `false` the output is the
projection of `content`; when `true` it is the projection of the stored `slice`
(falling back to `content` when no slice is stored).

`to_text` / `from_text` are the optional OS-clipboard converters. When `to_text`
(a `Document -> String`) is set, copy/cut/note also mirror the copied sub-document
out to the OS clipboard. When `from_text` (a `String -> Document`) is set, `Ctrl+V`
falls back to the OS clipboard if the internal slice is empty. Both default to
`nothing`, in which case there is no OS-clipboard interaction at all.

When `text` is `true`, the wrapped `content` is treated as a `TextText` and
copy/cut/paste operate on **character ranges** instead of document nodes: copy/cut
store the selected substring (as a `TextString`) in the slice and mirror it to the
OS clipboard; paste splices the slice's text (or, if the slice is empty, the OS
clipboard's text) in at the caret. `text` defaults to `false`.
"""
mutable struct ClipboardSliceToAnyProjection <: Projection
    display_slice::Cell   # reactive: flipping it switches the exposed child (content↔slice)
    to_text::Any          # Document -> String, or nothing  (copy/cut/note mirror → OS)
    from_text::Any        # String -> Document, or nothing   (paste fallback ← OS)
    text::Bool            # text-range copy/cut/paste over a TextText content (+ OS)
end
ClipboardSliceToAnyProjection(; display_slice::Bool=false, to_text=nothing, from_text=nothing, text::Bool=false) =
    ClipboardSliceToAnyProjection(Cell(display_slice), to_text, from_text, text)

"""
    ClipboardCollectionToAnyProjection(; display_collection=false)

Projects a `ClipboardCollection`. When `display_collection` is `false` the output
is the projection of `content`; when `true` it is a `CellVector` of the projected
`elements`.
"""
mutable struct ClipboardCollectionToAnyProjection <: Projection
    display_collection::Cell   # reactive: flipping it switches content ↔ elements view
end
ClipboardCollectionToAnyProjection(; display_collection::Bool=false) =
    ClipboardCollectionToAnyProjection(Cell(display_collection))

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
    # Reactive output: a derived cell over the display flag (the projection stays
    # domain-generic — it still exposes the active child directly). The reactive
    # SequentialProjection re-pulls this through its own per-stage cells, so
    # flipping `display_slice` switches the exposed child with no `editor.iomap`
    # drop — only the downstream stages re-print.
    output = Cell(() -> (p.display_slice[] && slice_iomap !== nothing) ?
                            slice_iomap.output : content_iomap.output)
    ClipboardSliceToAnyProjectionIoMap(p, input, output, content_iomap, slice_iomap)
end

function projection_print(p::ClipboardCollectionToAnyProjection, recursion, input::ClipboardCollection, ctx)
    content_iomap = projection_printer_recurse(recursion, input.content,
                        child_context(ctx, FieldReference("content")))
    elements = input.elements
    element_iomaps = [projection_printer_recurse(recursion, elements[i],
                          child_context(ctx, FieldReference("elements"), ElementReference(i)))
                      for i in 1:length(elements)]
    # Reactive output (see the slice printer): a derived cell over the display flag,
    # re-pulled by the reactive SequentialProjection — no `editor.iomap` drop.
    output = Cell(() -> p.display_collection[] ?
        CellVector(Cell[Cell(im.output) for im in element_iomaps]) :
        content_iomap.output)
    ClipboardCollectionToAnyProjectionIoMap(p, input, output, content_iomap, element_iomaps)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the *active child's* output directly (no clipboard-shaped
# wrapper), so the forward and backward maps are asymmetric: forward peels the
# clipboard field step and returns the child's output reference unwrapped;
# backward delegates to the child and prepends the clipboard field step.

# Active child for a slice projection: ("field-name", child-iomap).
function _slice_active(iomap::ClipboardSliceToAnyProjectionIoMap)
    (iomap.projection.display_slice[] && iomap.slice_iomap !== nothing) ?
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
    if iomap.projection.display_collection[]
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
    if iomap.projection.display_collection[]
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

Flip the `display_slice` `Cell` of a `ClipboardSliceToAnyProjection`, swapping the
output between the wrapped content and the stored slice. This is a plain reactive
cell write: the projection's derived `output` cell re-derives and the reactive
`SequentialProjection` re-pulls it downstream — no `editor.iomap` drop.
"""
struct ToggleClipboardSliceDisplayOperation <: Operation
    projection::ClipboardSliceToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardSliceDisplayOperation)
    # Reactive cell write only — NO editor.iomap drop. The derived output cell
    # re-derives and the change propagates downstream through reactive Sequential.
    op.projection.display_slice[] = !op.projection.display_slice[]
end

"""
    ToggleClipboardCollectionDisplayOperation(projection)

Flip the `display_collection` `Cell` of a `ClipboardCollectionToAnyProjection`.
A plain reactive cell write (see `ToggleClipboardSliceDisplayOperation`).
"""
struct ToggleClipboardCollectionDisplayOperation <: Operation
    projection::ClipboardCollectionToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardCollectionDisplayOperation)
    # Reactive cell write only — NO editor.iomap drop.
    op.projection.display_collection[] = !op.projection.display_collection[]
end

"""
    WriteOsClipboardOperation(text)

Side-effecting operation that writes `text` to the OS clipboard at evaluate time.
It is appended to the copy/cut/note compound when the clipboard projection has a
`to_text` converter, so a ProjecturEd copy is mirrored to the system clipboard.
Best-effort: `os_clipboard_write` degrades to a no-op (returns `false`) when no
clipboard tool is available, so this never fails an edit.
"""
struct WriteOsClipboardOperation <: Operation
    text::String
end

evaluate_operation(editor, op::WriteOsClipboardOperation) = (os_clipboard_write(op.text); nothing)

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReferencePath(FieldReference(name), EmptyReferencePath())

# Append an OS-clipboard mirror write to `ops` when the projection can serialize
# `obj` to text (a `to_text` converter is set and yields a String). No-op otherwise.
function _maybe_os_mirror!(ops, p, obj)
    p.to_text === nothing && return ops
    txt = try p.to_text(obj) catch; nothing end
    txt isa AbstractString && push!(ops, WriteOsClipboardOperation(String(txt)))
    ops
end

# Build a Document from the OS clipboard text via the projection's `from_text`
# converter, or `nothing` when there is no converter, no readable OS text, or the
# converter declines / errors. Used as the empty-slice paste fallback.
function _os_paste_document(p)
    p.from_text === nothing && return nothing
    text = os_clipboard_read()
    text === nothing && return nothing
    doc = try p.from_text(text) catch; nothing end
    doc isa Document ? doc : nothing
end

# ── Text mode (TextText content) ───────────────────────────────────────────────
# In text mode copy/cut/paste move *character ranges*, not document nodes. The
# slice stores the copied text as a TextString (the ProjecturEd clipboard); the OS
# clipboard is always mirrored on copy/cut and used as the paste fallback. Edits are
# `StringReplaceRangeOperation`s built by `text_insert_op`, re-rooted under
# `content`; the caret advances automatically on evaluation.

# The plain string held by a stored slice, or `nothing` when it carries no text.
_slice_text(d::TextString)     = (c = d.content; c isa AbstractString ? String(c) : nothing)
_slice_text(d::PrimitiveString) = (v = d.value;  v isa AbstractString ? String(v) : nothing)
_slice_text(d)                 = nothing

# Copy/cut/paste over a TextText content. Each returns `nothing` to decline (no
# TextText content, or no usable character selection), so the caller falls through.
function _text_clipboard_copy(p, input)
    content = input.content
    content isa TextText || return nothing
    sub = text_selection_substring(content)
    sub === nothing && return nothing
    CompoundOperation(Any[
        replace_document(_field_path("slice"), TextString(sub)),
        ReplaceSelectionOperation(input.selection),
        WriteOsClipboardOperation(sub),
    ])
end

function _text_clipboard_cut(p, input)
    content = input.content
    content isa TextText || return nothing
    sub = text_selection_substring(content)
    sub === nothing && return nothing
    del = text_insert_op(content, "")              # replace the selected range with "" = delete
    del === nothing && return nothing
    CompoundOperation(Any[
        replace_document(_field_path("slice"), TextString(sub)),
        _prefix_op(del, (FieldReference("content"),)),
        WriteOsClipboardOperation(sub),
    ])
end

function _text_clipboard_paste(p, input)
    content = input.content
    content isa TextText || return nothing
    str = _slice_text(input.slice)                 # primary: the ProjecturEd clipboard
    str === nothing && (str = os_clipboard_read())  # fallback: the OS clipboard
    str === nothing && return nothing
    op = text_insert_op(content, str)
    op === nothing && return nothing
    _prefix_op(op, (FieldReference("content"),))
end

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
# the user's original selection on the copied source. When the projection has a
# `to_text` converter, the copy is also mirrored to the OS clipboard.
function _clipboard_copy(p, input)
    # Text mode is exclusive over a TextText content: never fall through to the node
    # path (which would `evaluate_reference` a character selection).
    (p.text && input.content isa TextText) && return _text_clipboard_copy(p, input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    ops = Any[
        replace_document(_field_path("slice"), copy_document(obj)),
        ReplaceSelectionOperation(sel),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Cut: store the live object in the slice and blank out its source position.
function _clipboard_cut(p, input)
    (p.text && input.content isa TextText) && return _text_clipboard_cut(p, input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    ops = Any[
        replace_document(_field_path("slice"), obj),
        replace_document(sel, DocumentNothing()),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Note: like copy, but stores the live object (no deep copy). Restores the
# original selection after the slice write (see `_clipboard_copy`).
function _clipboard_note(p, input)
    # for text, "note" == copy the substring (text mode is exclusive)
    (p.text && input.content isa TextText) && return _text_clipboard_copy(p, input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    ops = Any[
        replace_document(_field_path("slice"), obj),
        ReplaceSelectionOperation(sel),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Paste: replace the selection target with the stored slice. The trailing
# ReplaceSelectionOperation pins the selection to the pasted target (rather than
# letting it follow the slice's stale inner selection). When the internal slice is
# empty, fall back to the OS clipboard via the projection's `from_text` converter.
function _clipboard_paste(p, input)
    (p.text && input.content isa TextText) && return _text_clipboard_paste(p, input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing
    slice = input.slice
    if !(slice isa Document)
        doc = _os_paste_document(p)
        doc === nothing && return nothing
        return CompoundOperation(Any[
            replace_document(sel, doc),
            ReplaceSelectionOperation(sel),
        ])
    end
    CompoundOperation(Any[
        replace_document(sel, slice),
        ReplaceSelectionOperation(sel),
    ])
end

# Paste-copy: like paste, but a fresh deep copy each time. The OS fallback already
# produces a fresh document per read, so it needs no extra copy. In text mode it is
# identical to paste (splicing a string needs no copy).
function _clipboard_paste_copy(p, input)
    (p.text && input.content isa TextText) && return _text_clipboard_paste(p, input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing
    slice = input.slice
    if !(slice isa Document)
        doc = _os_paste_document(p)
        doc === nothing && return nothing
        return CompoundOperation(Any[
            replace_document(sel, doc),
            ReplaceSelectionOperation(sel),
        ])
    end
    CompoundOperation(Any[
        replace_document(sel, copy_document(slice)),
        ReplaceSelectionOperation(sel),
    ])
end

# Add the selected object to the front of the collection (matches Lisp `push`).
function _clipboard_collection_add(input)
    _, obj = _selected(input)
    obj isa Document || return nothing
    insert_elements(_field_path("elements"), 0, Any[obj])
end

# Remove the selected element from the collection.
function _clipboard_collection_remove(input)
    idx = _elements_index(input.selection)
    idx === nothing && return nothing
    delete_elements(_field_path("elements"), idx)
end

# 0-based index of the element a selection path addresses, or nothing when the
# path does not descend through `elements[i]`.
function _elements_index(path)
    path = strip_reference_types(path)
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

# Own gestures, reified as a `projection_gestures` table so the same set that
# fires (via `read_projection_gesture`) is the one `collect_gestures` shows. The
# operations capture the projection `p` (for the display toggle) and take the
# clipboard document as their `doc` argument; they return `nothing` to decline
# (e.g. no usable selection), falling through to the content-child delegation.
# Modifiers are matched exactly, so `Ctrl+Shift+V` (paste-copy) and `Ctrl+V`
# (paste) are distinct — order between them is therefore immaterial.
function projection_gestures(p::ClipboardSliceToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:slash, [:ctrl], nothing),
            (doc, event) -> ToggleClipboardSliceDisplayOperation(p),
            (doc, sel) -> true, "Toggle stored slice", "clipboard"),
        GestureBinding(KeyDownPattern(:c, [:ctrl], nothing),
            (doc, event) -> _clipboard_copy(p, doc),
            (doc, sel) -> true, "Copy", "clipboard"),
        GestureBinding(KeyDownPattern(:x, [:ctrl], nothing),
            (doc, event) -> _clipboard_cut(p, doc),
            (doc, sel) -> true, "Cut", "clipboard"),
        GestureBinding(KeyDownPattern(:n, [:ctrl], nothing),
            (doc, event) -> _clipboard_note(p, doc),
            (doc, sel) -> true, "Note", "clipboard"),
        GestureBinding(KeyDownPattern(:v, [:ctrl, :shift], nothing),
            (doc, event) -> _clipboard_paste_copy(p, doc),
            (doc, sel) -> true, "Paste copy", "clipboard"),
        GestureBinding(KeyDownPattern(:v, [:ctrl], nothing),
            (doc, event) -> _clipboard_paste(p, doc),
            (doc, sel) -> true, "Paste", "clipboard"),
    ]
end

function projection_read(p::ClipboardSliceToAnyProjection, recursion, change::Change,
                         iomap::ClipboardSliceToAnyProjectionIoMap)
    own = read_projection_gesture(p, iomap, change.gesture)
    own !== nothing && return Change(change.gesture, own)
    cim = iomap.content_iomap
    inner = projection_read(cim.projection, recursion, change, cim)
    Change(change.gesture, _prefix_op(inner.operation, (FieldReference("content"),)))
end

# Gather this projection's own gestures plus the content child's, mirroring the
# reader's own-then-delegate structure, so `collect_gestures` (the help window)
# shows both the clipboard commands and whatever the wrapped content offers.
function collect_gestures(p::ClipboardSliceToAnyProjection, recursion, iomap::ClipboardSliceToAnyProjectionIoMap)
    result = GestureBinding[]
    append!(result, projection_gestures(p, iomap))
    cim = iomap.content_iomap
    cim === nothing || append!(result, collect_gestures(cim.projection, recursion, cim))
    result
end

function projection_gestures(p::ClipboardCollectionToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:asterisk, [:ctrl], nothing),
            (doc, event) -> ToggleClipboardCollectionDisplayOperation(p),
            (doc, sel) -> true, "Toggle collection", "clipboard"),
        GestureBinding(KeyDownPattern(:equals, [:ctrl], nothing),
            (doc, event) -> _clipboard_collection_add(doc),
            (doc, sel) -> true, "Add to collection", "clipboard"),
        GestureBinding(KeyDownPattern(:minus, [:ctrl], nothing),
            (doc, event) -> _clipboard_collection_remove(doc),
            (doc, sel) -> true, "Remove from collection", "clipboard"),
    ]
end

function projection_read(p::ClipboardCollectionToAnyProjection, recursion, change::Change,
                         iomap::ClipboardCollectionToAnyProjectionIoMap)
    own = read_projection_gesture(p, iomap, change.gesture)
    own !== nothing && return Change(change.gesture, own)
    cim = iomap.content_iomap
    inner = projection_read(cim.projection, recursion, change, cim)
    Change(change.gesture, _prefix_op(inner.operation, (FieldReference("content"),)))
end

function collect_gestures(p::ClipboardCollectionToAnyProjection, recursion, iomap::ClipboardCollectionToAnyProjectionIoMap)
    result = GestureBinding[]
    append!(result, projection_gestures(p, iomap))
    cim = iomap.content_iomap
    cim === nothing || append!(result, collect_gestures(cim.projection, recursion, cim))
    result
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
    elseif op isa ReplaceReferencedValue
        op.document === nothing ?
            ReplaceReferencedValue(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
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
