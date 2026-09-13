# ──────────────────────────────────────────────────────────────────────────
# Folded in from ClipboardSliceToAny.jl.
#
# The internal-clipboard slice projection — Julia port of Lisp's
# `clipboard/slice->t` (`source/projection/primitive/clipboard-to-t.lisp`).
#
# `ClipboardSliceToAnyProjection` sits on a `ClipboardSlice` document and shows
# either the wrapped `content` or the stored `slice`, toggled by `Ctrl+/`. Copy,
# cut, note and paste gestures move the selected sub-document in and out of the
# slice.
#
# It delegates every non-clipboard gesture into its `content` child reader and
# re-roots the returned operation under the `content` field. That is the School-A
# pattern: delegate through the stored child IoMap, never re-walk by document
# type.
#
# ## Display toggling
#
# The display flag is a `Cell`, and the projection's `output` is a derived cell
# over it. To flip the flag is a plain reactive cell write: the reactive
# `ChainingProjection` re-pulls the changed output and re-prints only the
# downstream stages, so the view switches with no `editor.iomap` drop.
#
# ## OS-clipboard bridge
#
# The projection takes optional `to_text` and `from_text` converters. When they
# are set, copy, cut and note mirror the copied sub-document out to the OS
# clipboard through a `WriteOsClipboardOperation`, and `Ctrl+V` falls back to the
# OS clipboard when the internal slice is empty. The OS read and write go through
# `Clipboard.jl`, which is stubbable and degrades to a no-op when the host has no
# clipboard tool. With both converters `nothing`, the default, there is no OS
# interaction at all.
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

When `text` is `true`, the wrapped `content` is treated as a `TextBlock` and
copy/cut/paste operate on **character ranges** instead of document nodes: copy/cut
store the selected substring (as a `TextString`) in the slice and mirror it to the
OS clipboard; paste splices the slice's text (or, if the slice is empty, the OS
clipboard's text) in at the caret. `text` defaults to `false`.
"""
mutable struct ClipboardSliceToAnyProjection <: Projection
    display_slice::Cell   # reactive: flipping it switches the exposed child (content↔slice)
    to_text::Any          # Document -> String, or nothing  (copy/cut/note mirror → OS)
    from_text::Any        # String -> Document, or nothing   (paste fallback ← OS)
    text::Bool            # text-range copy/cut/paste over a TextBlock content (+ OS)
end
ClipboardSliceToAnyProjection(; display_slice::Bool=false, to_text=nothing, from_text=nothing, text::Bool=false) =
    ClipboardSliceToAnyProjection(Cell(display_slice), to_text, from_text, text)

# ── IoMaps ────────────────────────────────────────────────────────────────────

@iomap struct ClipboardSliceToAnyIoMap
    projection::ClipboardSliceToAnyProjection
    input::Any              # ClipboardSlice
    output::Any             # content or slice child output
    content_iomap::Any
    slice_iomap::Any        # iomap of the stored slice, or nothing
end

# ── Printers ────────────────────────────────────────────────────────────────

function print_document(p::ClipboardSliceToAnyProjection, recursion, input::ClipboardSlice, ctx)
    content_iomap = print_child(recursion, input.content,
                        make_child_context(ctx, FieldReferenceStep("content")))
    slice_val = input.slice
    slice_iomap = slice_val isa Document ?
        print_child(recursion, slice_val,
            make_child_context(ctx, FieldReferenceStep("slice"))) : nothing
    # Reactive output: a derived cell over the display flag (the projection stays
    # domain-generic — it still exposes the active child directly). The reactive
    # ChainingProjection re-pulls this through its own per-stage cells, so
    # flipping `display_slice` switches the exposed child with no `editor.iomap`
    # drop — only the downstream stages re-print.
    output = ComputedCell(() -> (p.display_slice[] && slice_iomap !== nothing) ?
                            slice_iomap.output : content_iomap.output)
    ClipboardSliceToAnyIoMap(p, input, output, content_iomap, slice_iomap)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the *active child's* output directly (no clipboard-shaped
# wrapper), so the forward and backward maps are asymmetric: forward peels the
# clipboard field step and returns the child's output reference unwrapped;
# backward delegates to the child and prepends the clipboard field step.

# Active child for a slice projection: ("field-name", child-iomap).
function _slice_active(iomap::ClipboardSliceToAnyIoMap)
    (iomap.projection.display_slice[] && iomap.slice_iomap !== nothing) ?
        ("slice", iomap.slice_iomap) : ("content", iomap.content_iomap)
end

function map_reference_forward(::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    name, child = _slice_active(iomap)
    h = get_reference_head(reference)
    (h isa FieldReferenceStep && h.name == name) || return nothing
    map_reference_forward(child.projection, child, get_reference_tail(reference))
end

function map_reference_backward(::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyIoMap, reference)
    name, child = _slice_active(iomap)
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep(name), mapped)
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
    ToggleClipboardSliceOperation(projection)

Flip the `display_slice` `Cell` of a `ClipboardSliceToAnyProjection`, swapping the
output between the wrapped content and the stored slice. This is a plain reactive
cell write: the projection's derived `output` cell re-derives and the reactive
`ChainingProjection` re-pulls it downstream — no `editor.iomap` drop.
"""
struct ToggleClipboardSliceOperation <: Operation
    projection::ClipboardSliceToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardSliceOperation)
    # Reactive cell write only — NO editor.iomap drop. The derived output cell
    # re-derives and the change propagates downstream through reactive Sequential.
    op.projection.display_slice[] = !op.projection.display_slice[]
end

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
    text = read_os_clipboard()
    text === nothing && return nothing
    doc = try p.from_text(text) catch; nothing end
    doc isa Document ? doc : nothing
end

# ── Text mode (TextBlock content) ───────────────────────────────────────────────
# In text mode copy/cut/paste move *character ranges*, not document nodes. The
# slice stores the copied text as a TextString (the ProjecturEd clipboard); the OS
# clipboard is always mirrored on copy/cut and used as the paste fallback. Edits are
# `ReplaceStringRangeOperation`s built by `make_text_insert_operation`, re-rooted under
# `content`; the caret advances automatically on evaluation.

# The plain string held by a stored slice, or `nothing` when it carries no text.
_slice_text(d::TextString)     = (c = d.content; c isa AbstractString ? String(c) : nothing)
_slice_text(d::PrimitiveString) = (v = d.value;  v isa AbstractString ? String(v) : nothing)
_slice_text(d)                 = nothing

# Copy/cut/paste over a TextBlock content. Each returns `nothing` to decline (no
# TextBlock content, or no usable character selection), so the caller falls through.
function _text_clipboard_copy(p, input)
    content = input.content
    content isa TextBlock || return nothing
    sub = get_selection_substring(content)
    sub === nothing && return nothing
    CompoundOperation(Any[
        replace_document(_field_path("slice"), TextString(sub)),
        ReplaceSelectionOperation(input.selection),
        WriteOsClipboardOperation(sub),
    ])
end

function _text_clipboard_cut(p, input)
    content = input.content
    content isa TextBlock || return nothing
    sub = get_selection_substring(content)
    sub === nothing && return nothing
    del = make_text_insert_operation(content, "")              # replace the selected range with "" = delete
    del === nothing && return nothing
    CompoundOperation(Any[
        replace_document(_field_path("slice"), TextString(sub)),
        _prefix_op(del, (FieldReferenceStep("content"),)),
        WriteOsClipboardOperation(sub),
    ])
end

function _text_clipboard_paste(p, input)
    content = input.content
    content isa TextBlock || return nothing
    str = _slice_text(input.slice)                 # primary: the ProjecturEd clipboard
    str === nothing && (str = read_os_clipboard())  # fallback: the OS clipboard
    str === nothing && return nothing
    op = make_text_insert_operation(content, str)
    op === nothing && return nothing
    _prefix_op(op, (FieldReferenceStep("content"),))
end

# Copy: store an independent deep copy of the selected object in the slice. The
# write retargets the selection to `.slice` (ReplaceDocumentOperation moves the
# selection to where it writes), so a trailing ReplaceSelectionOperation restores
# the user's original selection on the copied source. When the projection has a
# `to_text` converter, the copy is also mirrored to the OS clipboard.
function _clipboard_copy(p, input)
    # Text mode is exclusive over a TextBlock content: never fall through to the node
    # path (which would `evaluate_reference` a character selection).
    (p.text && input.content isa TextBlock) && return _text_clipboard_copy(p, input)
    sel, obj = _selected(input)
    obj isa Document || return nothing
    payload = copy_document(obj)
    clear_selection!(payload)                  # clipboard payload carries no cursor
    ops = Any[
        replace_document(_field_path("slice"), payload),
        ReplaceSelectionOperation(sel),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Cut: store the live object in the slice and blank out its source position.
function _clipboard_cut(p, input)
    (p.text && input.content isa TextBlock) && return _text_clipboard_cut(p, input)
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
    (p.text && input.content isa TextBlock) && return _text_clipboard_copy(p, input)
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
    (p.text && input.content isa TextBlock) && return _text_clipboard_paste(p, input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReference) && return nothing
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
    (p.text && input.content isa TextBlock) && return _text_clipboard_paste(p, input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReference) && return nothing
    slice = input.slice
    if !(slice isa Document)
        doc = _os_paste_document(p)
        doc === nothing && return nothing
        return CompoundOperation(Any[
            replace_document(sel, doc),
            ReplaceSelectionOperation(sel),
        ])
    end
    fresh = copy_document(slice)
    clear_selection!(fresh)                    # pasted content starts with no cursor
    CompoundOperation(Any[
        replace_document(sel, fresh),
        ReplaceSelectionOperation(sel),
    ])
end

# ── Readers ─────────────────────────────────────────────────────────────────

# Own gestures, reified as a `get_projection_gesture_bindings` table so the same set that
# fires (via `read_projection_gesture`) is the one a listing shows. The
# operations capture the projection `p` (for the display toggle) and take the
# clipboard document as their `doc` argument; they return `nothing` to decline
# (e.g. no usable selection), falling through to the content-child delegation.
# ModifierKeys are matched exactly, so `Ctrl+Shift+V` (paste-copy) and `Ctrl+V`
# (paste) are distinct — order between them is therefore immaterial.
function get_projection_gesture_bindings(p::ClipboardSliceToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:slash, [:ctrl], nothing),
            (doc, event) -> ToggleClipboardSliceOperation(p),
            (doc, sel) -> true, "Toggle stored slice", "clipboard", false, "Toggle stored slice"),
        GestureBinding(KeyDownPattern(:c, [:ctrl], nothing),
            (doc, event) -> _clipboard_copy(p, doc),
            (doc, sel) -> true, "Copy", "clipboard", false, "Copy"),
        GestureBinding(KeyDownPattern(:x, [:ctrl], nothing),
            (doc, event) -> _clipboard_cut(p, doc),
            (doc, sel) -> true, "Cut", "clipboard", false, "Cut"),
        GestureBinding(KeyDownPattern(:n, [:ctrl], nothing),
            (doc, event) -> _clipboard_note(p, doc),
            (doc, sel) -> true, "Note", "clipboard", false, "Note"),
        GestureBinding(KeyDownPattern(:v, [:ctrl, :shift], nothing),
            (doc, event) -> _clipboard_paste_copy(p, doc),
            (doc, sel) -> true, "Paste copy", "clipboard", false, "Paste copy"),
        GestureBinding(KeyDownPattern(:v, [:ctrl], nothing),
            (doc, event) -> _clipboard_paste(p, doc),
            (doc, sel) -> true, "Paste", "clipboard", false, "Paste"),
    ]
end

function read_intent(p::ClipboardSliceToAnyProjection, recursion, change::Intent,
                         iomap::ClipboardSliceToAnyIoMap)
    own = read_projection_gesture(p, iomap, change.gesture)
    # Routing one gesture stops at the first answer; a collection takes both. The
    # child's is prefixed with `content`, exactly as its operations are.
    if change.gesture isa CollectIntents
        cim = iomap.content_iomap
        child = cim === nothing ? nothing :
                read_intent(cim.projection, recursion, change, cim).operation
        return Intent(change.gesture,
                      merge_collected_intents(_collected_intents(own),
                                              _collected_intents(_prefix_op(child, (FieldReferenceStep("content"),)))))
    end
    own !== nothing && return Intent(change.gesture, own)
    cim = iomap.content_iomap
    inner = read_intent(cim.projection, recursion, change, cim)
    Intent(change.gesture, _prefix_op(inner.operation, (FieldReferenceStep("content"),)))
end

# 3-arg payload form (used by tests and any parent that hands a bare payload).
read_intent(p::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
