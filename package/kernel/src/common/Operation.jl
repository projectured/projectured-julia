"""
    OperationModule

Default evaluate_operation methods for built-in operations. Loaded after
EditorModule so the Editor type is available.
"""
module OperationModule

import ..OperationApiModule: Operation, evaluate_operation
import ..DocumentApiModule: Document, clear_selection!, set_selection!
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference, TypeReference, is_element_reference, evaluate_reference, reference_equal, skip_type_checkpoints, annotate_reference_types, strip_reference_types, append_reference
import ..ReactiveModule: Cell
export ReplaceSelectionOperation, QuitEditorOperation, QuitEditorException, replace_selection!,
       OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation, ToggleCollapseOperation,
       ReplaceReferencedValue, replace_document, insert_elements, delete_elements,
       CompoundOperation

function evaluate_operation(editor, op::Nothing) end

# Fallback for any other input (e.g., raw events returned by reader)
function evaluate_operation(editor, op) end

struct QuitEditorException <: Exception end

"""
    CompoundOperation(operations)

Apply a sequence of operations in order, as a single editor step. The Julia
counterpart of Lisp's `make-operation/compound`: a reader returns one
`CompoundOperation` and the editor's `evaluate_operation` runs each member
operation against the same editor in turn.

Used by the clipboard cut gesture, which both writes the selected object into
the clipboard slice and replaces the selection target with an empty document.
"""
struct CompoundOperation <: Operation
    operations::Vector{Any}
end

CompoundOperation(operations...) = CompoundOperation(Vector{Any}(collect(operations)))

function evaluate_operation(editor, op::CompoundOperation)
    for member in op.operations
        evaluate_operation(editor, member)
    end
end

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
    update_selection!(editor.document, op.path)
end

# ReplaceDocumentOperation was folded into ReplaceReferencedValue + a trailing
# ReplaceSelectionOperation, bundled by `replace_document` (below). It replaced the
# document at `path` (rooted at editor.document) with a new `document`, then moved
# the editor selection to `path ⧺ document.selection` so the cursor landed inside
# the new value. See plan/done/consolidate-operations-replace.md (step 3).

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

# Write `value` into the slot `step` selects on `parent`. A FieldReference names a
# `Cell`-backed field (e.g. `JsonObjectEntry.value`, or a widget's `visible`); a
# RangeReference selects an element of a sequence container (`CellVector`) and
# overwrites it. Shared by `ReplaceReferencedValue` (single-slot writes of either a
# document or a scalar) — terminal-kind dispatch is what unifies the two.
function _write_slot!(parent, step::FieldReference, value)
    f = getfield(parent, Symbol(step.name))
    f isa Cell || error("ReplaceReferencedValue: field $(step.name) of $(typeof(parent)) is not a Cell")
    f[] = value
end

function _write_slot!(parent, step::RangeReference, value)
    parent[step.start + 1] = value
end

# A terminal `RangeReference` whose value is a *vector* of items is a SPLICE:
# replace the half-open element range `[start, stop)` of the sequence container
# with `items` (each wrapped in a `Cell`). Zero-width range ⇒ pure insert; empty
# items ⇒ pure delete; both ⇒ element replacement. This is the folded form of the
# former `CollectionInsertOperation` / `CollectionDeleteOperation` (see
# `insert_elements` / `delete_elements`); a single (non-vector) value still hits the
# element-overwrite method above (the `replace_document` array-element case).
function _write_slot!(parent, step::RangeReference, items::AbstractVector)
    for _ in 1:(step.stop - step.start)
        deleteat!(parent, step.start + 1)
    end
    for (k, item) in enumerate(items)
        insert!(parent, step.start + k, item isa Cell ? item : Cell(item))
    end
end

"""
    ReplaceReferencedValue(document, reference, value)

Set the scalar `value` at `reference` (a `ReferencePath`) resolved against a
root selected by the `document` field:

- **`document !== nothing`** — the root is the carried object, so this works on
  objects that do not live in the document tree (a widget, or a projection's own
  reactive parameter `Cell`s — the controls produced by `ObjectToWidget` edit
  these). The operation is *self-contained* and bubbles up the reader chain
  unchanged.
- **`document === nothing`** — the root is `editor.document` and `reference` is
  rooted there, so container/generic projections reroot the reference as the
  operation flows up (see `OperationRerooting.prepend_steps_to_op` and the default
  `projection_read`). An empty `reference` then means a **whole-root swap** (rebind
  `editor.document`, drop the cached iomap), mirroring `ReplaceDocumentOperation`'s
  empty-path branch.

It is `ReplaceDocumentOperation` generalised: an explicit-or-implicit root + a
reference + a plain value, reusing the same terminal-slot-write split. (Folding
`ReplaceDocumentOperation` and the Group 2–4 single-slot writes into this is the
subject of `plan/done/consolidate-operations-replace.md`.)
"""
struct ReplaceReferencedValue <: Operation
    document::Any
    reference::ReferencePath
    value::Any
end

# Convenience for the common single-field write on a carried root:
# `ReplaceReferencedValue(obj, "field", v)` writes `obj.field = v`. Dispatches by
# the second argument's type (`AbstractString` vs `ReferencePath`), so it never
# collides with the field-by-field constructor above.
ReplaceReferencedValue(document, field::AbstractString, value) =
    ReplaceReferencedValue(document,
        ConcreteReferencePath(FieldReference(field), EmptyReferencePath()), value)

function evaluate_operation(editor, op::ReplaceReferencedValue)
    reference = strip_reference_types(op.reference)
    # `document === nothing` ⇒ the reference is rooted at `editor.document`
    # (where the former `ReplaceDocumentOperation` rooted its path); otherwise the
    # operation carries its own root object (a widget, a projection parameter `Cell`).
    root = op.document === nothing ? editor.document : op.document
    if reference isa EmptyReferencePath
        # Whole-root swap: only meaningful when the root *is* `editor.document`
        # (there is no in-place "replace the object itself" for a carried root).
        # Rebind and drop the cached iomap so the next print rebuilds on the new
        # root — a wholesale swap is not reactive (nested swaps write into Cells).
        op.document === nothing ||
            error("ReplaceReferencedValue: empty reference on a carried root has no slot to write")
        editor.document = op.value
        editor.iomap = nothing
        return
    end
    parent_path, terminal = _split_terminal_step(reference)
    parent = parent_path isa EmptyReferencePath ? root :
             evaluate_reference(root, parent_path)
    _write_slot!(parent, terminal, op.value)
end

"""
    replace_document(path, document) -> CompoundOperation

Replace the document at `path` (rooted at `editor.document`) with `document`, then
move the editor selection to `path ⧺ document.selection` so the cursor lands inside
the freshly-created value. The structural analogue of the primitive replace-range
edits — every JSON/XML type-to-replace gesture (`[` → array, `{` → object, …) and
the clipboard cut/paste produce one.

This is the folded form of the former `ReplaceDocumentOperation`: a
`ReplaceReferencedValue(nothing, path, document)` write paired with a trailing
`ReplaceSelectionOperation`, bundled in a `CompoundOperation` so re-rooting prepends
the same steps to both as the operation bubbles up. An empty `path` is a whole-root
swap (the `ReplaceReferencedValue` rebinds `editor.document` and drops the iomap).
"""
function replace_document(path::ReferencePath, document)
    inner_sel = getfield(document, :selection)[]
    inner_sel === nothing && (inner_sel = EmptyReferencePath())
    CompoundOperation(Any[
        ReplaceReferencedValue(nothing, path, document),
        ReplaceSelectionOperation(_concat_paths(strip_reference_types(path), inner_sel)),
    ])
end

"""
    insert_elements(path, index, items[, selection]; root=nothing) -> operation

Insert each of `items` into the sequence container at `path` (a `CellVector` such
as a JSON array's `.elements`), at the 0-based `index`. Expressed as a splice — a
`ReplaceReferencedValue` whose terminal step is a **zero-width** `RangeReference(index, index)`
and whose value is the item vector. When `selection` is non-`nothing`, a trailing
`ReplaceSelectionOperation` is appended in a `CompoundOperation` to drop the cursor
into the new element (re-rooting prepends the same steps to both members).

`root` defaults to `nothing` (rooted at `editor.document`); pass a carried object
for an identity-rooted splice (e.g. a `WorkbenchPage`).
"""
function insert_elements(path::ReferencePath, index::Integer, items, selection=nothing; root=nothing)
    write = ReplaceReferencedValue(root, append_reference(path, RangeReference(index, index)),
                                   Vector{Any}(items))
    selection === nothing ? write :
        CompoundOperation(Any[write, ReplaceSelectionOperation(selection)])
end

"""
    delete_elements(path, index[, count]; root=nothing) -> operation

Remove `count` (default 1) elements from the sequence container at `path`, starting
at the 0-based `index`. Expressed as a splice — a `ReplaceReferencedValue` whose
terminal step is `RangeReference(index, index+count)` and whose value is the empty
vector (replace the range with nothing). The inverse of `insert_elements`.
"""
delete_elements(path::ReferencePath, index::Integer, count::Integer=1; root=nothing) =
    ReplaceReferencedValue(root, append_reference(path, RangeReference(index, index + count)), Any[])

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
    ResizeWindowOperation(target, width, height)

Set the `width`/`height` cells of `target` (a `WindowDocument`) to a new pixel
size. Produced by `WindowManagerProjection` when the user resizes the native
window frame. Because those cells are the
`available_width`/`available_height` the printer threads into the window's
content, writing them re-lays-out the content reactively — no re-projection.
The output `WindowDocument` shares the same cells (a `CopyingProjection`
property), so the backend reconciler also sees the new size on the next frame.

Carries the target document directly (like `ToggleCollapseOperation`), so it
bubbles up through every reader layer unchanged and is applied by the editor's
`evaluate_operation`.
"""
struct ResizeWindowOperation <: Operation
    target::Any
    width::Int
    height::Int
end

function evaluate_operation(editor, op::ResizeWindowOperation)
    op.target === nothing && return
    op.target.width = op.width
    op.target.height = op.height
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
    # Skip leading type checkpoints: a TypeReference is a non-navigating
    # assertion on the current node, so descent is driven by the next
    # navigation step (mirrors evaluate_reference / skip_type_checkpoints).
    nav = skip_type_checkpoints(path)
    nav isa ConcreteReferencePath || return
    h = nav.head
    rest = nav.tail
    child = if h isa FieldReference
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. Mirrors the
        # hasproperty guard in annotate_reference_types.
        hasproperty(document, sym) || return
        f = getfield(document, sym)
        f isa Cell ? f[] : f
    elseif h isa RangeReference
        # A RangeReference into a string leaf is a character cursor/range that
        # terminates here — there is no child Document to descend into, and
        # byte-indexing a multibyte String by a character position throws.
        document isa AbstractString && return
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return
        document[idx]
    else
        return
    end
    # Only descend into child Documents (which carry their own selection cell);
    # leaf values (String/Char/Number) hold no selection and are not navigable.
    child isa Document || return
    clear_selection!(child)
end

"""
    set_selection!(document, path)

Recursively sets the selection on `document` and its children to `path`.

The path is first **canonicalized** against `document`: any existing type
checkpoints are stripped and a fresh `TypeReference(typeof(node))` is inserted
before every navigation step (see `annotate_reference_types`). This is the single
binding point that makes every stored selection self-describing — callers hand in
a plain navigation skeleton (built with `@reference`) and it becomes canonical
against the live document. Annotation is idempotent on an unchanged document.
"""
function set_selection!(document, path)
    canonical = path === nothing ? path :
                annotate_reference_types(document, strip_reference_types(path))
    _set_selection_walk!(document, canonical)
end

# Internal recursive walker: assumes `path` is already canonical and writes each
# suffix into the matching child's selection cell, skipping type checkpoints to
# find the navigation step that descends.
function _set_selection_walk!(document, path)
    if hasproperty(document, :selection)
        getfield(document, :selection)[] = path
    end
    path isa ConcreteReferencePath || return
    # Skip leading type checkpoints to find the navigation step that descends
    # into a child; the checkpoint stays on the current node (canonical paths
    # carry a TypeReference before every navigation step).
    nav = skip_type_checkpoints(path)
    nav isa ConcreteReferencePath || return
    h = nav.head
    rest = nav.tail
    child = if h isa FieldReference
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. Mirrors the
        # hasproperty guard in annotate_reference_types.
        hasproperty(document, sym) || return
        f = getfield(document, sym)
        f isa Cell ? f[] : f
    elseif h isa RangeReference
        # A RangeReference into a string leaf is a character cursor/range that
        # terminates here — there is no child Document to descend into, and
        # byte-indexing a multibyte String by a character position throws.
        document isa AbstractString && return
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return
        document[idx]
    else
        return
    end
    # Only descend into child Documents (which carry their own selection cell);
    # leaf values (String/Char/Number) hold no selection and are not navigable.
    child isa Document || return
    _set_selection_walk!(child, rest)
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

# ── Incremental selection replacement ──────────────────────────────────────
#
# `update_selection!` is the caret-move fast path used by
# `ReplaceSelectionOperation`. It produces exactly the same stored state as
# `replace_selection!` (each level still holds the *whole remaining reference*,
# so every reader is unaffected), but writes the **shared selection chain in
# place**, touching only the cells whose content actually changed:
#
#   * `set_selection!` stores `child.selection === parent.selection.tail` (the
#     same path objects), and `ConcreteReferencePath`'s head/tail — and a
#     `RangeReference`'s start/stop — are themselves `Cell`s. A caret move
#     within a leaf therefore differs from the stored selection only in the
#     terminal cursor step's start/stop: we mutate those two cells in place and
#     rewrite **no** `selection` cell on the path. Unchanged routing ancestors
#     (e.g. a tabbed pane's active-tab cell, which reads only the head step)
#     are not invalidated, so partial rendering repaints only the caret.
#
#   * Where the path structurally diverges, we clear just the old divergent
#     branch and `set_selection!` the new suffix from the divergence point down,
#     then fix the parent path's `.tail` cell in place to keep the chain shared
#     — so cells *above* the divergence stay untouched too.
#
# The eager reactive engine has no value-equality short-circuit (see
# Reactive.jl), so the whole point is to avoid the *writes*, not to rely on the
# engine to absorb redundant ones.
function update_selection!(document, path)
    hasproperty(document, :selection) || return
    _sync_selection!(document, path)
    return
end

# Sync `document`'s selection subtree to `path`, reusing the existing chain in
# place wherever possible. Returns the value now held by `document.selection`
# so the caller can keep its own path tail pointing at it (chain sharing).
function _sync_selection!(document, path)
    hasproperty(document, :selection) || return path
    cell = getfield(document, :selection)
    old = cell[]
    (old isa ReferencePath && path isa ReferencePath && reference_equal(old, path)) && return old

    if old isa ConcreteReferencePath && path isa ConcreteReferencePath
        old_child = _selection_child(document, old)
        new_child = _selection_child(document, path)
        # Same routing step into the same child Document: keep this cell, recurse
        # into the child and only re-point our tail if the child's value changed.
        if new_child !== nothing && old_child === new_child && old.head == path.head
            new_tail = _sync_selection!(new_child, path.tail)
            getfield(old, :tail)[] === new_tail || (getfield(old, :tail)[] = new_tail)
            return old
        end
        # Terminal cursor moved within the same leaf step: mutate start/stop in
        # place, leaving every selection cell on the path untouched.
        if new_child === nothing && old_child === nothing &&
           reference_equal(old.tail, path.tail) && _mutate_terminal_step!(old.head, path.head)
            return old
        end
    end

    # Divergence: clear the old branch hanging here, install the new suffix.
    if old isa ConcreteReferencePath
        oc = _selection_child(document, old)
        oc === nothing || clear_selection!(oc)
    end
    cell[] = path
    if path isa ConcreteReferencePath
        nc = _selection_child(document, path)
        nc === nothing || set_selection!(nc, path.tail)
    end
    return path
end

# The child Document that `path`'s head step descends into, or `nothing` when
# the head terminates at `document` (a leaf cursor: string char, out-of-range,
# or a non-Document field). Mirrors the descent in clear_selection!/set_selection!.
function _selection_child(document, path::ConcreteReferencePath)
    h = path.head
    child = if h isa FieldReference
        f = getfield(document, Symbol(h.name))
        f isa Cell ? f[] : f
    elseif h isa RangeReference
        document isa AbstractString && return nothing
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return nothing
        document[idx]
    else
        return nothing
    end
    child isa Document ? child : nothing
end

# Mutate a terminal cursor step `old` in place to match `new`, returning `true`
# on success. Only `RangeReference` (a character cursor/range) is updated this
# way — its start/stop are `Cell`s shared across every path level, so one write
# moves the caret everywhere it is observed. Any other step type returns
# `false`, leaving the caller to rewrite the selection cell wholesale.
function _mutate_terminal_step!(old::RangeReference, new::RangeReference)
    getfield(old, :start)[] === new.start || (getfield(old, :start)[] = new.start)
    getfield(old, :stop)[]  === new.stop  || (getfield(old, :stop)[]  = new.stop)
    true
end
_mutate_terminal_step!(::Any, ::Any) = false

end # module
