# Fragment of `ClipboardModule`.
#
# The internal-clipboard slice projection.
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

A paste writes only where the paste rules allow: the selection names a whole
document, every document from the content down to it accepts a pasted document
(`accepts_pasted_document`), the slot takes the value, and the document in the
slot accepts it as a replacement (`accepts_pasted_replacement`). Otherwise the
gesture goes on to the content. Before a paste replaces a whole document, that
document can take a stored document that is no plain text in its own way
(`make_pasted_document_operation`), as a dashboard takes it as a card.

A cut is what a copy stores and the content's answer to Delete at the same
selection, in one operation; a cut that can not delete stores nothing. Delete and
Backspace that nothing inside answers take a whole selected document out of its
slot by the same rules: an element leaves its list, and a field gets the empty
document of its domain. That edit goes down to the document that holds the slot,
so each reader and each history on the way reads it.

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
    recursion::Any          # the projection the children were printed with, which reads them
end

# ── Printers ────────────────────────────────────────────────────────────────

function print_document(p::ClipboardSliceToAnyProjection, recursion, input::ClipboardSlice, ctx)
    content_iomap = print_child(recursion, input.content,
                        make_child_context(ctx, FieldReferenceStep("content")))
    # The stored slice is printed through the whole projection, so it is printed
    # only while it is on display. The cell reads the flag and the slice, so a
    # toggle or a new slice prints it again.
    slice_iomap = make_reconciled_child_iomap_cell(
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
    ClipboardSliceToAnyIoMap(p, input, output, content_iomap, slice_iomap, recursion)
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

# ── The text of the system clipboard ──────────────────────────────────────────
# A reader reads nothing outside the document, so a paste that needs the text of
# the system clipboard answers `PasteOsClipboardOperation`, and its evaluation
# reads the text off the task of the editor. The paste functions below take that
# text as `os`: `UNREAD_OS_TEXT` in a reader, and the text read, or `nothing`
# when the clipboard has none, in the evaluation.

struct UnreadOsText end
const UNREAD_OS_TEXT = UnreadOsText()

"""
    PasteOsClipboardOperation(place, projection, copy)

A paste that takes the text of the system clipboard. Its evaluation reads the
clipboard on a task of its own, after the writes started before it, and pastes
at `place`, the clipboard document that the gesture landed in: at once when the
read ends inside a short wait, which is the usual case, else when the text comes,
if the place still exists. `copy` is the paste of a fresh copy.

The start of the paste writes no document, so undo steps over it.
"""
struct PasteOsClipboardOperation <: Operation
    place::Reference        # the clipboard document, from where the operation stands
    projection::Any         # ::ClipboardSliceToAnyProjection
    copy::Bool
end

OperationModule.operation_reference(op::PasteOsClipboardOperation) = op.place
OperationModule.retarget_operation(op::PasteOsClipboardOperation, place::Reference) =
    PasteOsClipboardOperation(place, op.projection, op.copy)
make_inverse_operation(document, ::PasteOsClipboardOperation) = DoNothingOperation()

# What a reader answers for a paste that needs the text of the system clipboard.
_paste_os_text(p; copy::Bool = false) =
    ReplaceViewStateOperation(PasteOsClipboardOperation(EmptyReference(), p, copy))

function evaluate_operation(editor, op::PasteOsClipboardOperation)
    start_document_read!(editor, read_os_clipboard,
                         text -> ApplyOsClipboardPasteOperation(op.place, op.projection,
                                                                op.copy, text))
    nothing
end

"""
    ApplyOsClipboardPasteOperation(place, projection, copy, text)

The paste of `PasteOsClipboardOperation`, once the text of the system clipboard
is read. It makes the edit of the paste at `place` and evaluates it as an
operation from the root: each reader between the place and the root lifts it, as
it lifts the answer to a gesture. A place that holds no clipboard document pastes
nothing.
"""
struct ApplyOsClipboardPasteOperation <: Operation
    place::Reference
    projection::Any
    copy::Bool
    text::Any               # ::String, nothing, or the exception of the read
end

OperationModule.is_self_contained_operation(::ApplyOsClipboardPasteOperation) = true
make_inverse_operation(document, ::ApplyOsClipboardPasteOperation) = DoNothingOperation()

function evaluate_operation(editor, op::ApplyOsClipboardPasteOperation)
    text = op.text isa AbstractString ? String(op.text) : nothing
    input = try_evaluate_reference(editor.document, op.place, nothing)
    if !(input isa ClipboardSlice)
        @warn("The paste came after its place was gone, so it pastes nothing.", place = op.place)
        return nothing
    end
    edit = op.copy ? _clipboard_paste_copy(op.projection, input; os = text) :
                     _clipboard_paste(op.projection, input; os = text)
    edit === nothing && return nothing
    # A placed edit goes down to its place from the root, so each reader and each
    # history on the way reads it.
    rooted = edit isa NamedTuple ?
        _read_down_to_place(edit.place, edit.operation) do at, operation
            read_rooted_operation(editor, concat_references(op.place, at), operation;
                                  description = "Paste")
        end :
        read_rooted_operation(editor, op.place, edit; description = "Paste")
    rooted === nothing || evaluate_operation(editor, rooted)
    nothing
end

# Build a Document from the OS clipboard text via the projection's `from_text`
# converter, or `nothing` when there is no converter, no OS text, or the converter
# declines / errors. Used as the empty-slice paste fallback.
function _os_paste_document(p, text)
    p.from_text === nothing && return nothing
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
        make_replace_document_operation(_field_path("slice"), TextString(sub)),
        ReplaceSelectionOperation(input.selection),
        WriteOsClipboardOperation(sub),
    ])
end

function _text_clipboard_paste(p, input; os = UNREAD_OS_TEXT)
    content = input.content
    content isa TextBlock || return nothing
    str = _slice_text(input.slice)                 # primary: the ProjecturEd clipboard
    if str === nothing                             # fallback: the OS clipboard
        os === UNREAD_OS_TEXT && return _paste_os_text(p)
        str = os
    end
    str === nothing && return nothing
    op = make_text_insert_operation(content, str)
    op === nothing && return nothing
    (; place = _field_path("content"), operation = op)
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

OperationModule.is_self_contained_operation(::CopyReferenceOperation) = true

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
    start_os_clipboard_write!(text)
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

function _text_target_paste(p, input; os = UNREAD_OS_TEXT, copy::Bool = false, whole::Bool = false)
    target = whole ? _find_whole_value_target(input) : _find_text_target(input; writes = true)
    target === nothing && return nothing
    os === UNREAD_OS_TEXT && return _paste_os_text(p; copy)
    text = os
    (text === nothing || isempty(text)) && (text = _slice_text(input.slice))
    text === nothing && return nothing
    pasted = _make_pasted_text(target, text)
    pasted === nothing && return nothing
    (place, rest) = _split_at_place(input, target.path)
    (; place, operation = _make_text_target_edit(target, pasted; path = rest))
end

# The edit of a paste that puts `value` at `path`, a whole document, and selects
# it, as a placed edit.
function _make_replace_edit(input, path::Reference, value)
    (place, rest) = _split_at_place(input, path)
    (; place, operation = CompoundOperation(Any[make_replace_document_operation(rest, value),
                                                ReplaceSelectionOperation(rest)]))
end

# Whether a paste on the whole selected document is a text typed over its value:
# the stored copy is a text of another kind than that document, or there is no
# stored copy and no converter of the text of the system clipboard. An empty
# place, such as the hole that a cut leaves, takes the stored document instead.
function _is_whole_value_paste(p, input)
    selected = try_evaluate_reference(input, input.selection, missing)
    selected isa Document || return false
    # The general type of the document, which the domain names as its placeholder.
    is_domain_placeholder(Base.typename(typeof(selected)).wrapper) && return false
    slice = input.slice
    slice === nothing && return p.from_text === nothing
    _slice_text(slice) !== nothing && typeof(slice) !== typeof(selected)
end

# The document that a paste puts on the whole selected document: the stored
# document, except a stored text in a hole of a domain, which becomes the
# insertion of that domain with the text in it, so the hole holds a document of
# its own domain.
function _make_pasted_value(input, slice)
    text = _slice_text(slice)
    text === nothing && return slice
    selected = try_evaluate_reference(input, input.selection, missing)
    selected isa Document || return slice
    insertion = get_domain_insertion(typeof(selected))
    insertion === nothing ? slice : insertion(text)
end

# What a reader answers for the result of a paste. A placed edit, an `operation`
# relative to the document that `place` names from the clipboard document, goes
# down to its place, so each reader and each history on the way reads it. An
# operation, such as the start of a read of the system clipboard, is the answer.
_read_paste(p, iomap, result) =
    result isa NamedTuple ?
        _read_placed_operation(p, iomap, result.place, result.operation; description = "Paste") :
        result

function _text_target_copy(p, input)
    target = _find_text_target(input; writes = false)
    (target === nothing || target.start == target.stop) && return nothing
    text = _get_text_target_text(target)
    CompoundOperation(Any[make_replace_document_operation(_field_path("slice"),
                                                          PrimitiveString(text)),
                          ReplaceSelectionOperation(target.path),
                          WriteOsClipboardOperation(text)])
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
        make_replace_document_operation(_field_path("slice"), payload),
        ReplaceSelectionOperation(sel),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Cut: what a copy stores, and the content's answer to Delete at the same
# selection, in one operation. A cut that can not delete stores nothing. A range
# stores its characters. A whole document goes into the slice itself, not a
# copy: it leaves the document, so a cut and a paste move it, a tool too. The
# delete comes last, so the selection is where the delete leaves it.
function _clipboard_cut(p, iomap, input, event)
    stored = _make_cut_store(p, input)
    stored === nothing && return nothing
    delete = _read_delete(p, iomap, event)
    delete === nothing && return nothing
    CompoundOperation(Any[stored, delete])
end

function _make_cut_store(p, input)
    (p.text && input.content isa TextBlock) && return _text_clipboard_copy(p, input)
    text = _text_target_copy(p, input)
    text === nothing || return text
    sel, obj = _selected(input)
    obj isa Document || return nothing
    ops = Any[make_replace_document_operation(_field_path("slice"), obj),
              ReplaceSelectionOperation(sel)]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# The content's answer to Delete at the selection, rooted at the clipboard
# document, or else the delete of the whole selected document, or `nothing`.
function _read_delete(p, iomap, event)
    time = hasproperty(event, :time) ? event.time : 0.0
    answer = _read_content_gesture(iomap, KeyDown(:delete, ModifierKeys(); time))
    answer === nothing ? _read_whole_delete(p, iomap) : answer
end

# The answer of the child on display to `gesture` at the selection, rooted at the
# clipboard document, or `nothing` when the child has none.
function _read_content_gesture(iomap, gesture)
    name, child = _slice_active(iomap)
    answer = read_intent(child.projection, iomap.recursion, Intent(gesture), child)
    operation = answer isa Intent ? answer.operation : answer
    operation isa Operation || return nothing
    reroot_operation(operation, (FieldReferenceStep(name),))
end

# Delete and Backspace with no modifier: the keys that take a whole selected
# document out of its slot when nothing inside answers them.
_is_delete_key(event) =
    event isa KeyDown && event.key in (:delete, :backspace) && event.modifiers == ModifierKeys()

# The delete of the whole selected document, read down to the document that holds
# its slot, so each reader and each history on the way reads it as the answer of
# that document. `nothing` when the host offers no cut, or the slot must not change.
function _read_whole_delete(p, iomap)
    :cut in p.offered_gestures || return nothing
    delete = _make_whole_delete(iomap.input)
    delete === nothing && return nothing
    _read_placed_operation(p, iomap, delete.place, delete.operation; description = "Delete")
end

# `operation`, which is relative to the document that `place` names from the
# clipboard document, read down to that place by its route, and rooted at the
# clipboard document: each reader on the way lifts it, as it lifts the answer to
# a gesture. `nothing` when the readers do not carry it.
function _read_placed_operation(p, iomap, place::Reference, operation; description = "")
    _read_down_to_place(place, operation) do at, edit
        at isa EmptyReference && return edit
        answer = read_intent(p, iomap.recursion,
                             Intent(nothing, edit, String(description), "clipboard", at), iomap)
        rooted = answer isa Intent ? answer.operation : answer
        rooted isa Operation ? rooted : nothing
    end
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
        make_replace_document_operation(_field_path("slice"), obj),
        ReplaceSelectionOperation(sel),
    ]
    _maybe_os_mirror!(ops, p, obj)
    CompoundOperation(ops)
end

# Paste: replace the selection target with the stored slice. The trailing
# ReplaceSelectionOperation pins the selection to the pasted target (rather than
# letting it follow the slice's stale inner selection). When the internal slice is
# empty, fall back to the OS clipboard via the projection's `from_text` converter:
# in a reader that is a `PasteOsClipboardOperation`, whose evaluation reads it.
function _clipboard_paste(p, input; os = UNREAD_OS_TEXT)
    (p.text && input.content isa TextBlock) && return _text_clipboard_paste(p, input; os)
    taken = _document_target_paste(input, input.slice)
    taken === nothing || return taken
    text = _text_target_paste(p, input; os)
    text === nothing || return text
    _is_whole_value_paste(p, input) && return _text_target_paste(p, input; os, whole = true)
    slice = input.slice
    if !(slice isa Document)
        p.from_text === nothing && return nothing
        os === UNREAD_OS_TEXT && return _paste_os_text(p)
        doc = _os_paste_document(p, os)
        doc === nothing && return nothing
        sel = _find_paste_target(input, doc)
        sel === nothing && return nothing
        return _make_replace_edit(input, sel, doc)
    end
    value = _make_pasted_value(input, slice)
    sel = _find_paste_target(input, value)
    sel === nothing && return nothing
    _make_replace_edit(input, sel, value)
end

# A stored document that is no plain text can go into a document in its own way
# (`make_pasted_document_operation`), as the draft of a conversation takes a plot
# as a part. At a text cursor, each document on the path of the cursor, from the
# deepest, can take it, and when none does the paste goes to the text. When the
# selection names a whole document, that document can take it, and when it does
# not the paste replaces it. Paste-copy gives a fresh copy.
function _document_target_paste(input, slice; copy::Bool = false)
    (slice isa Document && _slice_text(slice) === nothing) || return nothing
    input.selection isa ConcreteReference || return nothing
    at_text = _find_text_target(input; writes = true) !== nothing
    (at_text || try_evaluate_reference(input, input.selection, missing) isa Document) || return nothing
    value = copy ? _make_clipboard_copy(slice) : slice
    value === nothing && return nothing
    copy && clear_selection!(value)
    steps = get_reference_steps(strip_reference_types(input.selection))
    for count in (at_text ? (length(steps):-1:1) : (length(steps):length(steps)))
        path = _make_steps_path(steps[1:count])
        document = try_evaluate_reference(input, path, missing)
        document isa Document || continue
        operation = make_pasted_document_operation(document, path, value)
        operation === nothing || return (; place = path, operation)
    end
    nothing
end

# Paste-copy: like paste, but a fresh deep copy each time. The OS fallback already
# produces a fresh document per read, so it needs no extra copy. In text mode it is
# identical to paste (splicing a string needs no copy).
function _clipboard_paste_copy(p, input; os = UNREAD_OS_TEXT)
    (p.text && input.content isa TextBlock) && return _text_clipboard_paste(p, input; os)
    taken = _document_target_paste(input, input.slice; copy = true)
    taken === nothing || return taken
    text = _text_target_paste(p, input; os, copy = true)
    text === nothing || return text
    _is_whole_value_paste(p, input) && return _text_target_paste(p, input; os, copy = true, whole = true)
    slice = input.slice
    if !(slice isa Document)
        p.from_text === nothing && return nothing
        os === UNREAD_OS_TEXT && return _paste_os_text(p; copy = true)
        doc = _os_paste_document(p, os)
        doc === nothing && return nothing
        sel = _find_paste_target(input, doc)
        sel === nothing && return nothing
        return _make_replace_edit(input, sel, doc)
    end
    value = _make_pasted_value(input, slice)
    sel = _find_paste_target(input, value)
    sel === nothing && return nothing
    # A converted text is fresh already.
    fresh = value === slice ? _make_clipboard_copy(slice) : value
    fresh === nothing && return nothing
    clear_selection!(fresh)                    # pasted content starts with no cursor
    _make_replace_edit(input, sel, fresh)
end

# ── Readers ─────────────────────────────────────────────────────────────────

# Own gestures, reified as a `get_projection_gesture_bindings` table so the same set that
# fires (via `read_projection_gesture`) is the one a listing shows. The
# operations capture the projection `p` (for the display toggle) and the IO map
# (a cut reads the content's delete through it), and take the clipboard document
# as their `doc` argument; they return `nothing` to decline (e.g. no usable
# selection), falling through to the content-child delegation.
# ModifierKeys are matched exactly, so `Ctrl+Shift+V` (paste-copy) and `Ctrl+V`
# (paste) are distinct — order between them is therefore immaterial.
function get_projection_gesture_bindings(p::ClipboardSliceToAnyProjection, iomap)
    named = (:toggle, :copy, :copy_reference, :cut, :note, :paste_copy, :paste)
    GestureBinding[binding for (name, binding) in zip(named, _make_clipboard_bindings(p, iomap))
                   if name in p.offered_gestures]
end

function _make_clipboard_bindings(p::ClipboardSliceToAnyProjection, iomap)
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
                       (doc, event) -> _clipboard_cut(p, iomap, doc, event); description = "Cut",
                       domain = "clipboard", name = "Cut"),
        GestureBinding(KeyDownPattern(:n; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_note(p, doc); description = "Note",
                       domain = "clipboard", name = "Note"),
        GestureBinding(KeyDownPattern(:v; modifiers = [:ctrl, :shift]),
                       (doc, event) -> _read_paste(p, iomap, _clipboard_paste_copy(p, doc));
                       description = "Paste copy", domain = "clipboard",
                       name = "Paste copy"),
        GestureBinding(KeyDownPattern(:v; modifiers = [:ctrl]),
                       (doc, event) -> _read_paste(p, iomap, _clipboard_paste(p, doc));
                       description = "Paste",
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
    inner = reroot_operation(read_intent(child.projection, recursion, change, child).operation, steps)
    # Delete and Backspace that nothing inside answered take a whole selected
    # document out of its slot.
    if !(inner isa Operation) && _is_delete_key(change.gesture)
        whole = _read_whole_delete(p, iomap)
        whole === nothing || return Intent(change.gesture, whole)
    end
    Intent(change.gesture, inner)
end

# 3-arg payload form (used by tests and any parent that hands a bare payload).
read_intent(p::ClipboardSliceToAnyProjection, iomap::ClipboardSliceToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
