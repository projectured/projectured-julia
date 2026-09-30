# Fragment of `ClipboardModule`.
#
# The internal-clipboard slice projection — Julia port of Lisp's
# `clipboard/slice->t` (`source/projection/primitive/clipboard-to-t.lisp`).
#
# `ClipboardSliceToAnyProjection` sits on a `ClipboardSlice` document and shows
# either the wrapped `content` or the stored `slice`, toggled by `Ctrl+/`. Copy,
# cut, note and paste gestures move the selected sub-document in and out of the
# slice.
#
# It prints the child on display through its recursion, with the context of that
# child, and it reads its own gestures first. It delegates every other gesture to
# the child on display and re-roots the returned operation under that child's
# field. That is the School-A pattern: delegate through the stored child IoMap,
# never re-walk by document type.
#
# ## Display toggling
#
# The display flag is a `Cell`, and the projection's `output` is a derived cell
# over it. To flip the flag is a plain reactive cell write: the output cell
# re-derives, and the stored slice is printed only while it is on display, so
# the view switches with no `editor.iomap` drop.
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
    CLIPBOARD_GESTURES

The seven gestures a clipboard slice can offer, by name: `:toggle` (`Ctrl+/`),
`:copy` (`Ctrl+C`), `:copy_reference` (`Ctrl+Shift+C`), `:cut` (`Ctrl+X`),
`:note` (`Ctrl+N`), `:paste` (`Ctrl+V`) and `:paste_copy` (`Ctrl+Shift+V`).
"""
const CLIPBOARD_GESTURES = (:toggle, :copy, :copy_reference, :cut, :note, :paste, :paste_copy)

"""
    ClipboardSliceToAnyProjection(; display_slice=false, to_text=nothing, from_text=nothing,
                                    text=false, offered_gestures=CLIPBOARD_GESTURES)

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

`offered_gestures` names the gestures the projection answers, out of
[`CLIPBOARD_GESTURES`](@ref); a gesture left out goes on to the content. A host
whose content must not be cut, or whose whole view must not be swapped for the
stored slice, leaves out `:cut` or `:toggle`.

A paste and a cut write only where the paste rules allow: the selection names a
whole document, every document from the content down to it accepts a pasted
document (`accepts_pasted_document`), the slot takes the value, and the document
in the slot accepts it as a replacement (`accepts_pasted_replacement`).
Otherwise the gesture goes on to the content.

A copy and a note take the selected document or, when the selection names a
frame such as a pane tab, the document that [`find_clipboard_document`](@ref)
answers. A copy stores an independent copy made with
[`ClipboardCopyPolicy`](@ref): a document that refuses a paste, such as a tool,
is copied as the duplicate its kind declares, and the copy is refused when the
kind declares none. A note stores the document itself, a tool too.
"""
mutable struct ClipboardSliceToAnyProjection <: Projection
    display_slice::Cell   # reactive: flipping it switches the exposed child (content↔slice)
    to_text::Any          # Document -> String, or nothing  (copy/cut/note mirror → OS)
    from_text::Any        # String -> Document, or nothing   (paste fallback ← OS)
    text::Bool            # text-range copy/cut/paste over a TextBlock content (+ OS)
    offered_gestures::Tuple   # the names, out of CLIPBOARD_GESTURES, this projection answers
end
ClipboardSliceToAnyProjection(; display_slice::Bool=false, to_text=nothing, from_text=nothing, text::Bool=false,
                              offered_gestures::Tuple=CLIPBOARD_GESTURES) =
    ClipboardSliceToAnyProjection(Cell(display_slice), to_text, from_text, text, offered_gestures)

# ── IoMaps ────────────────────────────────────────────────────────────────────

@iomap struct ClipboardSliceToAnyIoMap
    projection::ClipboardSliceToAnyProjection
    input::Any              # ClipboardSlice
    output::Any             # content or slice child output
    content_iomap::Any
    slice_iomap::Any        # iomap of the stored slice while it is on display, or nothing
end

# ── Printers ────────────────────────────────────────────────────────────────

function print_document(p::ClipboardSliceToAnyProjection, recursion, input::ClipboardSlice, ctx)
    content_iomap = print_child(recursion, input.content,
                        make_child_context(ctx, FieldReferenceStep("content")))
    # The stored slice is printed through the whole projection, so it is printed
    # only while it is on display. The cell reads the flag and the slice, so a
    # toggle or a new slice prints it again.
    slice_iomap = reconcile_child_iomap(
        () -> (p.display_slice[] && input.slice isa Document) ? input.slice : nothing,
        slice -> slice === nothing ? nothing :
            print_child(recursion, slice, make_child_context(ctx, FieldReferenceStep("slice"))))
    # Reactive output: a derived cell over the display flag. The projection stays
    # domain-generic — it exposes the output of the child on display directly —
    # so flipping `display_slice` switches that output with no `editor.iomap` drop.
    output = Cell(@computation begin
        slice = slice_iomap[]
        slice === nothing ? content_iomap.output : slice.output
    end)
    ClipboardSliceToAnyIoMap(p, input, output, content_iomap, slice_iomap)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the *active child's* output directly (no clipboard-shaped
# wrapper), so the forward and backward maps are asymmetric: forward peels the
# clipboard field step and returns the child's output reference unwrapped;
# backward delegates to the child and prepends the clipboard field step.

# Active child for a slice projection: ("field-name", child-iomap). The slice
# iomap exists only while the slice is on display.
function _slice_active(iomap::ClipboardSliceToAnyIoMap)
    slice = iomap.slice_iomap
    slice === nothing ? ("content", iomap.content_iomap) : ("slice", slice)
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
        reroot_operation(del, (FieldReferenceStep("content"),)),
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
    reroot_operation(op, (FieldReferenceStep("content"),))
end

# ── Text targets ────────────────────────────────────────────────────────────────
# A selection that ends in a range of a field's text (`_find_text_target`) is
# answered before the rules for a whole document. A paste takes the text of the
# system clipboard, or the text the slice holds when the system clipboard has
# none, and makes the edit that typing it would make. A copy, a note and a cut of
# a range store its characters in the slice and on the system clipboard. A copy
# at a caret has nothing to take, and goes on to the rules below.

"""
    CopyReferenceOperation(clipboard)

`Ctrl+Shift+C`: copy the reference of the selected object, as Julia code that
gives that object when an evaluator runs it:

    evaluate_reference(editor.document, @reference(editor.document, <path>))

The path is the complete selection, read from the root document of the editor
when the operation runs. A selection that ends inside a text names the document
that holds the text, so the code always gives an object. The code goes to the
system clipboard and into the slice as text, so a paste at a caret types it, in
this editor or in another program.

It holds the clipboard and no path, so it travels up the chain unchanged.
"""
struct CopyReferenceOperation <: Operation
    clipboard::ClipboardSlice
end

OperationModule.operation_travels_unchanged(::CopyReferenceOperation) = true

# A copy writes the clipboard and no document, so there is nothing to undo.
make_inverse_operation(document, ::CopyReferenceOperation) = DoNothingOperation()

function evaluate_operation(editor, op::CopyReferenceOperation)
    root = editor.document
    selection = getfield(root, :selection)[]
    selection isa Reference || return nothing
    steps = collect(Any, get_reference_steps(strip_reference_types(selection)))
    while !isempty(steps) &&
          !(try_evaluate_reference(root, _make_steps_path(steps), missing) isa Document)
        pop!(steps)
    end
    isempty(steps) && return nothing
    text = make_reference_code(_make_steps_path(steps))
    op.clipboard.slice = PrimitiveString(text)
    write_os_clipboard!(text)
    nothing
end

"""
    make_reference_code(reference) -> String

Julia code that gives the object `reference` names from the root document of an
editor, in an evaluator where `editor` is bound. `reference` has no type
checkpoints; `@reference` with the document types the path again.
"""
make_reference_code(reference) =
    "evaluate_reference(editor.document, @reference(editor.document, " *
    lstrip(sprint(show, reference), '.') * "))"

function _text_target_paste(p, input)
    target = _find_text_target(input; writes = true)
    target === nothing && return nothing
    text = read_os_clipboard()
    (text === nothing || isempty(text)) && (text = _slice_text(input.slice))
    text === nothing && return nothing
    pasted = _make_pasted_text(target, text)
    pasted === nothing && return nothing
    _make_text_target_edit(target, pasted)
end

function _text_target_copy(p, input; cut::Bool = false)
    target = _find_text_target(input; writes = cut)
    (target === nothing || target.start == target.stop) && return nothing
    text = _get_text_target_text(target)
    ops = Any[replace_document(_field_path("slice"), PrimitiveString(text)),
              cut ? _make_text_target_edit(target, "") : ReplaceSelectionOperation(target.path),
              WriteOsClipboardOperation(text)]
    CompoundOperation(ops)
end

# Copy: store an independent copy of the selected object in the slice, made with
# `ClipboardCopyPolicy`, so a tool is stored as its duplicate. The
# write retargets the selection to `.slice` (ReplaceDocumentOperation moves the
# selection to where it writes), so a trailing ReplaceSelectionOperation restores
# the user's original selection on the copied source. When the projection has a
# `to_text` converter, the copy is also mirrored to the OS clipboard.
function _clipboard_copy(p, input)
    # Text mode is exclusive over a TextBlock content: never fall through to the node
    # path (which would `evaluate_reference` a character selection).
    (p.text && input.content isa TextBlock) && return _text_clipboard_copy(p, input)
    text = _text_target_copy(p, input)
    text === nothing || return text
    sel, selected = _selected(input)
    obj = find_clipboard_document(selected)
    obj === nothing && return nothing
    payload = _make_clipboard_copy(obj)
    payload === nothing && return nothing
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
    text = _text_target_copy(p, input; cut = true)
    text === nothing || return text
    sel, obj = _selected(input)
    obj isa Document || return nothing
    _find_paste_target(input, DocumentNothing()) === nothing && return nothing
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
    text = _text_target_copy(p, input)
    text === nothing || return text
    sel, selected = _selected(input)
    obj = find_clipboard_document(selected)
    obj === nothing && return nothing
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
    text = _text_target_paste(p, input)
    text === nothing || return text
    slice = input.slice
    if !(slice isa Document)
        doc = _os_paste_document(p)
        doc === nothing && return nothing
        sel = _find_paste_target(input, doc)
        sel === nothing && return nothing
        return CompoundOperation(Any[
            replace_document(sel, doc),
            ReplaceSelectionOperation(sel),
        ])
    end
    sel = _find_paste_target(input, slice)
    sel === nothing && return nothing
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
    text = _text_target_paste(p, input)
    text === nothing || return text
    slice = input.slice
    if !(slice isa Document)
        doc = _os_paste_document(p)
        doc === nothing && return nothing
        sel = _find_paste_target(input, doc)
        sel === nothing && return nothing
        return CompoundOperation(Any[
            replace_document(sel, doc),
            ReplaceSelectionOperation(sel),
        ])
    end
    sel = _find_paste_target(input, slice)
    sel === nothing && return nothing
    fresh = _make_clipboard_copy(slice)
    fresh === nothing && return nothing
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
    named = (:toggle, :copy, :copy_reference, :cut, :note, :paste_copy, :paste)
    GestureBinding[binding for (name, binding) in zip(named, _make_clipboard_bindings(p))
                   if name in p.offered_gestures]
end

function _make_clipboard_bindings(p::ClipboardSliceToAnyProjection)
    GestureBinding[
        GestureBinding(KeyDownPattern(:slash; modifiers = [:ctrl]),
                       (doc, event) -> ToggleClipboardSliceOperation(p);
                       description = "Toggle stored slice", domain = "clipboard",
                       name = "Toggle stored slice"),
        GestureBinding(KeyDownPattern(:c; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_copy(p, doc); description = "Copy",
                       domain = "clipboard", name = "Copy"),
        GestureBinding(KeyDownPattern(:c; modifiers = [:ctrl, :shift]),
                       (doc, event) -> CopyReferenceOperation(doc);
                       description = "Copy the reference of the selected object",
                       domain = "clipboard", name = "Copy reference"),
        GestureBinding(KeyDownPattern(:x; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_cut(p, doc); description = "Cut",
                       domain = "clipboard", name = "Cut"),
        GestureBinding(KeyDownPattern(:n; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_note(p, doc); description = "Note",
                       domain = "clipboard", name = "Note"),
        GestureBinding(KeyDownPattern(:v; modifiers = [:ctrl, :shift]),
                       (doc, event) -> _clipboard_paste_copy(p, doc);
                       description = "Paste copy", domain = "clipboard",
                       name = "Paste copy"),
        GestureBinding(KeyDownPattern(:v; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_paste(p, doc); description = "Paste",
                       domain = "clipboard", name = "Paste"),
    ]
end

function read_intent(p::ClipboardSliceToAnyProjection, recursion, change::Intent,
                         iomap::ClipboardSliceToAnyIoMap)
    name, child = _slice_active(iomap)
    steps = (FieldReferenceStep(name),)
    # An operation with a route goes to the child on display, when the route
    # leads there.
    if change.route !== nothing
        routed = follow_intent_route(change, steps...)
        routed === nothing && return Intent(change.gesture, nothing)
        answer = read_routed_intent(child.projection, recursion, routed, child)
        return Intent(change.gesture, reroot_operation(answer.operation, steps))
    end
    own = read_projection_gesture(p, iomap, change.gesture)
    # Routing one gesture stops at the first answer; a collection takes both. The
    # child's is prefixed with the child's field, exactly as its operations are.
    if change.gesture isa CollectIntents
        inner = read_intent(child.projection, recursion, change, child).operation
        return Intent(change.gesture,
                      merge_collected_intents(_collected_intents(own),
                                              _collected_intents(reroot_operation(inner, steps))))
    end
    own !== nothing && return Intent(change.gesture, own)
    inner = read_intent(child.projection, recursion, change, child)
    Intent(change.gesture, reroot_operation(inner.operation, steps))
end

# 3-arg payload form (used by tests and any parent that hands a bare payload).
read_intent(p::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
