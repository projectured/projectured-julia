"""
    OperationModule

The built-in operations and the selection machinery that applies them. Holds the
concrete `Operation` subtypes the reader side of the pipeline produces
(`ReplaceSelectionOperation`, `ReplaceReferencedValue`, the window/zoom/collapse
operations, `CompoundOperation`, …) with their `evaluate_operation` methods, the
`clear_selection!` / `set_selection!` / `update_selection!` propagation over the
document tree, and the `splice_*` text-edit helpers. The abstract `Operation`
vocabulary and the `evaluate_operation` generic live in the pure `OperationApiModule`
(`api/Operation.jl`); this module carries the implementations.

`evaluate_operation` is duck-typed on `editor`, so nothing here references a
concrete editor type — the module loads early (well before the editor loop) and
still works against whatever object carries `editor.document`.
"""
module OperationModule

import ..OperationApiModule: Operation, evaluate_operation
import ..DocumentApiModule: Document, clear_selection!, set_selection!, with_selection
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference, TypeReference, is_element_reference, evaluate_reference, reference_equal, annotate_reference_types, strip_reference_types, append_reference, concat_references, reference_steps
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
export NoOperation, ReplaceSelectionOperation, QuitEditorOperation, QuitEditorException, replace_selection!,
       OpenWindowOperation, OpenPopupOperation, CloseWindowOperation, ResizeWindowOperation, ToggleCollapseOperation,
       ReplaceReferencedValue, replace_document, insert_elements, delete_elements, SelectNextInsertionOperation,
       CompoundOperation, AdjustZoomOperation, AdjustFontZoomOperation, update_selection!,
       splice_string, splice_number, splice_value!

"""
    NoOperation()

An operation that does nothing when applied. Its purpose is to *consume* a
gesture without effecting a change: a reader (or a per-instance gesture binding)
returns `NoOperation()` to say "this gesture is handled — stop looking",
distinct from returning `nothing`, which means "declined, keep looking / fall
through". The canonical way for a per-instance binding to **suppress** a default
behavior (see `instance_gestures`) is to map the pattern to a `NoOperation()`.
"""
struct NoOperation <: Operation end

evaluate_operation(editor, ::NoOperation) = nothing
function evaluate_operation(editor, op::Nothing) end

# Catch-all: silently ignore anything that is not an Operation. Unlike the device
# I/O generics (which deliberately omit a catch-all so an unimplemented backend
# fails loudly), this one is *meant* to swallow: a reader that declines returns a
# raw gesture/event or `nothing`, and those flow all the way up to here, where
# "not an operation" simply means "nothing to apply".
function evaluate_operation(editor, op) end

# ── Text-splice helpers ─────────────────────────────────────────────────────
# The canonical text-replace primitives every domain routes through. They are
# implementations (single algorithm / a small representation-dispatched method
# set), so they live here rather than in the pure `OperationApiModule` interface.

"""
    splice_string(old, s, e, replacement) -> String

Replace the characters of `old` between 0-based boundaries `[s, e]` with
`replacement`. Character-aware, so multi-byte characters survive intact.
Boundaries are clamped: `s <= 0` keeps nothing on the left, `e >= length(old)`
keeps nothing on the right. This is the one canonical text splice — every
text-replace edit in every domain routes through it.
"""
function splice_string(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

"""
    splice_number(old_str, s, e, replacement) -> Union{Float64, Nothing}

Splice the textual form of a number between 0-based boundaries `[s, e]`, then
parse the result back to a `Float64`. Returns `nothing` for an empty result or
unparseable input (the value cell tolerates `nothing` as the empty sentinel).
"""
function splice_number(old_str::AbstractString, s::Int, e::Int, replacement::AbstractString)
    new_str = splice_string(old_str, s, e, replacement)
    isempty(new_str) ? nothing : tryparse(Float64, new_str)
end

"""
    splice_value!(owner, field, value, s, e, replacement)

Apply a text-replace edit to `owner.<field>` between 0-based boundaries `[s, e]`.
Dispatch is on the *representation* of the current `value` (read from the field
by the caller), not on the document type — so a single small set of methods
covers every domain:

- `AbstractString` — write the spliced string back through the field.
- `Nothing`        — a cleared text field; splice against the empty string.
- `Number`         — splice the textual form and reparse (editing a number's text
                     means "reparse it"; see [`splice_number`](@ref)).

A domain whose field holds a richer text representation (a styled span, or a
sequence of spans) adds its own method here; those methods live in the module
that owns those types. A later unification of all replace-part operations around
a reference will add a sequence/`CellVector` method here for structural element
edits.
"""
function splice_value! end

splice_value!(owner, field::Symbol, value::AbstractString, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string(value, s, e, replacement))

splice_value!(owner, field::Symbol, ::Nothing, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string("", s, e, replacement))

splice_value!(owner, field::Symbol, value::Number, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_number(string(value), s, e, replacement))

struct QuitEditorException <: Exception end

"""
    CompoundOperation(operations)

Apply a sequence of operations in order, as a single editor step. The Julia
counterpart of Lisp's `make-operation/compound`: a reader returns one
`CompoundOperation` and `evaluate_operation` runs each member operation against
the same editor in turn — for an intent that is naturally several writes at once
(e.g. a cut that both saves the selected value and clears the slot it came from).
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

Operation that signals the editor to stop, by throwing `QuitEditorException`
(which the editor loop catches to exit).
"""
struct QuitEditorOperation <: Operation end

function evaluate_operation(editor, op::QuitEditorOperation)
    throw(QuitEditorException())
end

"""
    AdjustZoomOperation(delta)

Editor-global *uniform* readability zoom: `delta` is +1 (in), -1 (out) or 0
(reset). Magnifies the whole editor. The concrete behaviour — rescaling the
display factor, reflowing and repainting — lives in a rendering backend's
`evaluate_operation`; the generic no-op fallback above keeps it harmless under
backends that do not implement it.
"""
struct AdjustZoomOperation <: Operation
    delta::Int
end

"""
    AdjustFontZoomOperation(delta)

Editor-global *font-only* readability zoom, like [`AdjustZoomOperation`](@ref)
but scaling only text, so fixed graphics and spacing keep their size. Behaviour
also lives in a rendering backend.
"""
struct AdjustFontZoomOperation <: Operation
    delta::Int
end

"""
    ReplaceSelectionOperation(path)

Operation that replaces the current selection with `path`. Produced by the reader
side of the projection pipeline and applied by `evaluate_operation`.

Click-versus-keyboard disambiguation does **not** ride on this operation. A
projection that wants a glyph to behave differently on click than under keyboard
navigation keys that off the originating gesture (`change.gesture isa MousePress`),
which travels the reader chain in the `Change`, rather than off a flag on this
operation.
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


# Split a non-empty path into (everything-but-last-step, last-step). The prefix is
# rebuilt as a plain skeleton (callers pass an already type-stripped path).
function _split_terminal_step(path::ConcreteReferencePath)
    steps = reference_steps(path)
    (ReferencePath(steps[1:end-1]...), steps[end])
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
        ReplaceSelectionOperation(concat_references(strip_reference_types(path), inner_sel)),
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
for an identity-rooted splice against a document that is not in the tree.
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

# ─────────────────────────────────────────────────────────────────────────
# SelectNextInsertionOperation — move the cursor to the next "hole"
#
# An editor-global navigation step: walk `editor.document` in pre-order and move
# the selection to the first Document satisfying `predicate` (a "hole", e.g. an
# insertion placeholder) that comes *after* the currently-selected node, placing
# the cursor at `<hole> ⧺ cursor` (the hole's own char cursor, e.g. `value{0}`).
# It carries no reference of its own, so it bubbles up the reader chain unchanged
# (the pass-through arms in the default `projection_read` and the else-branch of
# `prepend_steps_to_op`). A domain gesture supplies the predicate/cursor, so the
# kernel stays domain-agnostic — e.g. a "jump to next hole" key builds
# `SelectNextInsertionOperation(d -> d isa SomeInsertion, @reference value{0})`.
"""
    SelectNextInsertionOperation(predicate[, cursor])

Move the selection to the next hole (a Document for which `predicate` holds) after
the currently-selected node, in document pre-order, and place the cursor at that
hole's `cursor` suffix (default whole-element). Clamps at the last hole.
"""
struct SelectNextInsertionOperation <: Operation
    predicate::Any        # (node::Document) -> Bool ; true marks a hole to land on
    cursor::ReferencePath # suffix appended to the found hole's path (e.g. value{0})
end

SelectNextInsertionOperation(predicate) =
    SelectNextInsertionOperation(predicate, EmptyReferencePath())

function evaluate_operation(editor, op::SelectNextInsertionOperation)
    root = editor.document
    root isa Document || return
    nodes = Tuple{ReferencePath,Any}[]
    _preorder_documents!(root, EmptyReferencePath(), Base.IdSet{Any}(), nodes)
    owner = _selection_owner_node(root, getfield(root, :selection)[])
    cur = 0
    if owner !== nothing
        for (i, (_, nd)) in enumerate(nodes)
            nd === owner && (cur = i; break)
        end
    end
    for j in (cur + 1):length(nodes)
        if op.predicate(nodes[j][2])
            set_selection!(root, concat_references(nodes[j][1], op.cursor))
            return
        end
    end
    return
end

# Pre-order Document walk building set_selection!-compatible paths: FieldReference
# for fields, RangeReference(i-1, i) for CellVector elements (a raw `CellVector`
# field is itself a Document, reached by its field then indexed). Skips `selection`
# and guards cycles/shared substructure by identity. Matching `CellVector` by `isa`
# (CollectionModule loads before this file) keeps an `@forward_vector` Document
# (indexable but holding its sequence in a field) from being mistaken for a raw
# element vector.
function _preorder_documents!(node, path::ReferencePath, seen, out)
    node isa Document || return
    node in seen && return
    push!(seen, node)
    push!(out, (path, node))
    if node isa CellVector
        for i in 1:length(node)
            _preorder_documents!(node[i], append_reference(path, RangeReference(i - 1, i)), seen, out)
        end
        return
    end
    for nm in fieldnames(typeof(node))
        nm === :selection && continue
        raw = getfield(node, nm)
        val = raw isa Cell ? raw[] : raw
        val isa Document || continue
        _preorder_documents!(val, append_reference(path, FieldReference(string(nm))), seen, out)
    end
    return
end

# The deepest Document a selection anchors at: strip type checkpoints, then drop
# trailing steps until the path resolves to a Document (a `value{k}` char cursor
# resolves to a String, so it is dropped to reach the owning leaf). Empty ⇒ root.
function _selection_owner_node(root, sel)
    sel === nothing && return nothing
    p = strip_reference_types(sel)
    while true
        v = try evaluate_reference(root, p) catch; nothing end
        v isa Document && return v
        p isa EmptyReferencePath && return root
        (p, _) = _split_terminal_step(p)
    end
end

"""
    ToggleCollapseOperation([target])

Operation that flips the `collapsed` field of a single collapsible node.

`target` is the node whose `collapsed` cell should be toggled, or `nothing`.
A `nothing` target is resolved by whichever projection owns the collapse state to
the **innermost** collapsible node containing the current selection, before the
operation propagates back up — so `evaluate_operation` only ever sees a concrete
`target` (a click that already knows the node it hit supplies one directly).

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
    auto_dismiss::Bool
    modal::Bool
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
                      auto_dismiss::Bool = false,
                      modal::Bool = false,
                      content::Document) =
    OpenWindowOperation(id, String(title), Int(x), Int(y), Int(width), Int(height),
                        (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
                        style, auto_dismiss, modal, content)

"""
    OpenPopupOperation(; id, anchor, dx, dy, width, height, auto_dismiss, content)

Request a popup window **anchored to a widget** rather than at absolute
coordinates. `anchor` is a `ReferencePath` (captured at print time by the
trigger, e.g. a `WidgetSelect`) naming the widget to anchor under; `(dx, dy)` is
the trigger-supplied offset (the trigger bakes its own size in, so "below the
box" is `(0, box_height + gap)`).

A content-level resolver projection intercepts it, resolves `anchor` to the
widget's absolute position via `map_reference_forward` / `anchor_point`, and
turns it into an `OpenWindowOperation` at `position + (dx, dy)` — so the deep
trigger reader never needs to know its own absolute coordinates. Never reaches
`evaluate_operation` (the resolver consumes it before the WindowManager).
"""
struct OpenPopupOperation <: Operation
    id::Symbol
    anchor::ReferencePath
    dx::Int
    dy::Int
    width::Int
    height::Int
    auto_dismiss::Bool
    content::Document
end

OpenPopupOperation(; id::Symbol, anchor::ReferencePath,
                     dx::Integer = 0, dy::Integer = 0,
                     width::Integer = 0, height::Integer = 0,
                     auto_dismiss::Bool = true, content::Document) =
    OpenPopupOperation(id, anchor, Int(dx), Int(dy), Int(width), Int(height),
                       auto_dismiss, content)

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
    # Descend into the child the path's head step routes to (see `_selection_child`,
    # which returns `nothing` when the head terminates here — a leaf char cursor,
    # a stale/cross-domain step, or a non-Document field) and clear it too.
    child = _selection_child(document, path)
    child === nothing && return
    clear_selection!(child)
end

"""
    set_selection!(document, path)

Recursively sets the selection on `document` and its children to `path`.

The path is first **canonicalized** against `document`: it is stripped to its
plain navigation skeleton and then re-annotated so every node records the
`typeof` the document it stands on (see `annotate_reference_types` — in the
folded model the type is a *field* on each path node, not a separate step). This
is the single binding point that makes every stored selection self-describing —
callers hand in a plain navigation skeleton (built with `@reference`) and it
becomes canonical against the live document. Annotation is idempotent on an
unchanged document.
"""
function set_selection!(document, path)
    canonical = path === nothing ? path :
                annotate_reference_types(document, strip_reference_types(path))
    _set_selection_walk!(document, canonical)
end

"""
    with_selection(document, path) -> document

Construct-and-select convenience: `set_selection!(document, path)` then return
`document`, so a freshly-built document literal can be selected in a single
expression. See [`set_selection!`](@ref) for the propagation/canonicalization
semantics.
"""
with_selection(document, path) = (set_selection!(document, path); document)

# Internal recursive walker: assumes `path` is already canonical and writes each
# suffix into the matching child's selection cell, descending one navigation step
# per level.
function _set_selection_walk!(document, path)
    if hasproperty(document, :selection)
        getfield(document, :selection)[] = path
    end
    path isa ConcreteReferencePath || return
    # Descend into the child this step routes to and write the remaining tail there
    # (see `_selection_child`: `nothing` means the step terminates at a leaf here).
    child = _selection_child(document, path)
    child === nothing && return
    _set_selection_walk!(child, path.tail)
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
# or a non-Document field). This is the single descent helper shared by
# `clear_selection!`, `_set_selection_walk!`, and `_sync_selection!`.
function _selection_child(document, path::ConcreteReferencePath)
    h = path.head
    child = if h isa FieldReference
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. In the folded
        # model `h` is always the navigation step (the node type is a field), so
        # guard the field's presence explicitly.
        hasproperty(document, sym) || return nothing
        f = getfield(document, sym)
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
