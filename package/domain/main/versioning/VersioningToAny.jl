"""
    VersioningToAnyProjectionModule

The version-elimination projection — the direct analogue of
`ClipboardSliceToAnyProjection` (`ClipboardToAnyProjectionModule`).

`VersioningToAnyProjection` sits on top of a `VersionedObject` document. Its
printer selects one `ObjectVersion` according to the document's `criterion`
(`select_version`) and projects that version's **value object** in place of the
wrapper — so the output is a plain, non-versioned document and the wrapper
vanishes. Because the elimination is purely structural and recurses through
`print_child`, nested `VersionedObject`s inside a selected value
resolve automatically, each by its own criterion.

The reader delegates non-versioning gestures into the selected value's child
reader and re-roots the returned operation under `versions[idx].value` (the
School-A pattern — delegate through the stored child IoMap, never re-walk by
document type). Own gestures snapshot a new version
(`insert_elements` on `versions`) or remove the active one (`delete_elements`) —
the same standard, universally-rerooted sequence splices the clipboard uses;
`SetVersionCriterionOperation` switches the active criterion.

## Criterion swapping

`criterion` lives on the document as a `Cell`, and the printer defers
`select_version` into a derived `selection_cell`, so `SetVersionCriterionOperation`
is a plain reactive cell write: the new version is selected and re-printed and the
reactive `ChainingProjection` re-pulls the output downstream, with **no
`editor.iomap` drop** (mirroring `ToggleClipboardSliceDisplayOperation`).

## Empty / no-match

When `select_version` returns `nothing` (an empty `versions` list, or a
criterion that matches no version) the printer emits a `DocumentNothing`,
mirroring `ClipboardSlice`'s empty-slice fallback. The reference maps and the
delegating reader then have no child to descend into and decline.
"""
module VersioningToAnyProjectionModule

import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation,
                          insert_elements, delete_elements, CompoundOperation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentCoreModule: DocumentNothing
import ..DocumentModule: copy_document
import ..SelectionApiModule: clear_selection!
import ..VersioningModule: VersionedObject, ObjectVersion, VersionProperties,
                          VersionCriterion, VersionCriterionLatest, select_version
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, RangeReferenceStep, ElementReferenceStep,
                          evaluate_reference, head, tail
import ..PrinterContextModule: PrinterContext, make_child_context
import ..IoMapApiModule: IoMap
import ..GestureBindingModule: GestureBinding
import ..EventPatternModule: KeyDownPattern
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings, read_projection_gesture, collect_gesture_bindings

export VersioningToAnyProjection, VersioningToAnyProjectionIoMap,
       SetVersionCriterionOperation

# ── Projection ────────────────────────────────────────────────────────────────

"""
    VersioningToAnyProjection()

Projects a `VersionedObject`. The output is the projection of the value object
of the version selected by the document's own `criterion`; the wrapper vanishes.
When no version matches, the output is a `DocumentNothing`. The criterion lives
on the document (not the projection) so different versioned nodes in one tree can
be viewed under different criteria simultaneously, and a single projection
instance serves every versioned node.
"""
struct VersioningToAnyProjection <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────────

# `selection_cell` holds `(idx, value_iomap)` for the version `criterion` currently
# selects, or `nothing`. It is derived from `input.criterion`, so a criterion change
# re-derives it (re-printing the newly-selected version's value) with no
# `editor.iomap` drop. `output`/`index`/`value_iomap` read it transparently via
# `getproperty`, so the reference maps and reader see the *current* selection and the
# reactive `ChainingProjection` re-pulls the output downstream.
struct VersioningToAnyProjectionIoMap <: IoMap
    projection::VersioningToAnyProjection
    input::Any                # VersionedObject
    selection_cell::Cell      # Cell of (idx, value_iomap) or nothing
    output_cell::Cell         # derived: value child output, or DocumentNothing
end

function Base.getproperty(io::VersioningToAnyProjectionIoMap, name::Symbol)
    name === :output       && return getfield(io, :output_cell)[]
    if name === :index || name === :value_iomap
        sel = getfield(io, :selection_cell)[]
        sel === nothing && return nothing
        return name === :index ? sel[1] : sel[2]
    end
    getfield(io, name)
end

# ── Printer ───────────────────────────────────────────────────────────────────

function print_document(p::VersioningToAnyProjection, recursion, input::VersionedObject, ctx)
    selection_cell = Cell(() -> begin
        selected = select_version(input)
        selected === nothing && return nothing
        idx, version = selected
        value_iomap = print_child(recursion, version.value,
                          make_child_context(ctx, FieldReferenceStep("versions"),
                                        ElementReferenceStep(idx), FieldReferenceStep("value")))
        (idx, value_iomap)
    end)
    output_cell = Cell(() -> begin
        sel = selection_cell[]
        sel === nothing ? DocumentNothing() : sel[2].output
    end)
    VersioningToAnyProjectionIoMap(p, input, selection_cell, output_cell)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the selected value's output directly (the wrapper is invisible),
# so the maps are asymmetric: forward peels the three steps that reach
# `versions[idx].value` and returns the child's reference unwrapped; backward
# delegates to the child and prepends those same three steps so the path is
# rooted at the VersionedObject.

function map_reference_forward(::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, reference)
    reference isa ConcreteReference || return reference
    child = iomap.value_iomap
    child === nothing && return nothing
    idx = iomap.index
    # Require the path to descend through versions[idx].value, stripping all three.
    h = head(reference)
    (h isa FieldReferenceStep && h.name == "versions") || return nothing
    rest = tail(reference)
    rest isa ConcreteReference || return nothing
    e = head(rest)
    (e isa RangeReferenceStep && e.start + 1 == idx) || return nothing
    rest2 = tail(rest)
    rest2 isa ConcreteReference || return nothing
    f = head(rest2)
    (f isa FieldReferenceStep && f.name == "value") || return nothing
    map_reference_forward(child.projection, child, tail(rest2))
end

function map_reference_backward(::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, reference)
    child = iomap.value_iomap
    child === nothing && return nothing
    idx = iomap.index
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep("versions"),
        ConcreteReference(ElementReferenceStep(idx),
            ConcreteReference(FieldReferenceStep("value"), mapped)))
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
    SetVersionCriterionOperation(target, criterion)

Replace the `criterion` of the `target` `VersionedObject` (e.g. switch from
*latest* to *as-of T*, or pin an index). A plain reactive cell write: the
projection's `selection_cell` is derived from `criterion`, so the new version is
selected (and re-printed) and the reactive `ChainingProjection` re-pulls it
downstream — no `editor.iomap` drop (see `ToggleClipboardSliceDisplayOperation`).
"""
struct SetVersionCriterionOperation <: Operation
    target::Any
    criterion::VersionCriterion
end

function evaluate_operation(editor, op::SetVersionCriterionOperation)
    op.target === nothing && return
    op.target.criterion = op.criterion   # reactive cell write — selection re-derives
end

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReference(FieldReferenceStep(name), EmptyReference())

# Snapshot the current selected value into a new ObjectVersion (deep-copied) and
# push it to the front of `versions` (index 0, newest-first). A standard sequence
# splice (insert_elements) so every ancestor projection re-roots it. Returns
# nothing when there is no selected value to snapshot.
function _create_version(iomap::VersioningToAnyProjectionIoMap)
    version = iomap.index === nothing ? nothing : iomap.input.versions[iomap.index]
    version isa ObjectVersion || return nothing
    saved_value = copy_document(version.value)
    clear_selection!(saved_value)               # a saved version carries no cursor
    snapshot = ObjectVersion(saved_value)
    insert_elements(_field_path("versions"), 0, Any[snapshot])
end

# Delete the currently selected version (the active one). A standard sequence
# splice (delete_elements, 0-based index), re-rooted by every ancestor.
function _delete_version(iomap::VersioningToAnyProjectionIoMap)
    iomap.index === nothing && return nothing
    delete_elements(_field_path("versions"), iomap.index - 1)
end

# Own gestures, reified as a `get_projection_gesture_bindings` table so the same set that
# fires (via `read_projection_gesture`) is the one `collect_gesture_bindings` shows. The
# operations capture `iomap` (they snapshot/delete the selected version) and
# return `nothing` to decline (no selected version), falling through to the
# value-child delegation. ModifierKeys are matched exactly.
function get_projection_gesture_bindings(p::VersioningToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:s, [:ctrl, :shift], nothing),
            (doc, event) -> _create_version(iomap),
            (doc, sel) -> true, "Create version", "versioning"),
        GestureBinding(KeyDownPattern(:delete, [:ctrl], nothing),
            (doc, event) -> _delete_version(iomap),
            (doc, sel) -> true, "Delete version", "versioning"),
    ]
end

# ── Reader ─────────────────────────────────────────────────────────────────────

function read_intent(p::VersioningToAnyProjection, recursion, change::Intent,
                         iomap::VersioningToAnyProjectionIoMap)
    own = read_projection_gesture(p, iomap, change.gesture)
    own !== nothing && return Intent(change.gesture, own)
    vim = iomap.value_iomap
    vim === nothing && return Intent(change.gesture, nothing)
    inner = read_intent(vim.projection, recursion, change, vim)
    Intent(change.gesture, _prefix_op(inner.operation,
        (FieldReferenceStep("versions"), ElementReferenceStep(iomap.index), FieldReferenceStep("value"))))
end

# 3-arg payload form (used by tests and any parent that hands a bare payload).
read_intent(p::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Own gestures (create/delete version) plus the selected value's, so the help
# window shows both -- the collector mirrors the reader's own-then-delegate shape.
function collect_gesture_bindings(p::VersioningToAnyProjection, recursion, iomap::VersioningToAnyProjectionIoMap)
    result = GestureBinding[]
    append!(result, get_projection_gesture_bindings(p, iomap))
    vim = iomap.value_iomap
    vim === nothing || append!(result, collect_gesture_bindings(vim.projection, recursion, vim))
    result
end

# ── Operation re-rooting ───────────────────────────────────────────────────────
# Prepend `steps` to the reference path carried by a delegated value operation,
# so it is rooted at the VersionedObject rather than at the selected value.

function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        ReplaceSelectionOperation(_prepend(steps, op.path))
    elseif op isa ReplaceStringRangeOperation
        ReplaceStringRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        ReplaceNumberRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceReferencedValueOperation
        op.document === nothing ?
            ReplaceReferencedValueOperation(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
    else
        op
    end
end

function _prepend(steps::Tuple, path::Reference)
    result = path
    for step in reverse(steps)
        result = ConcreteReference(step, result)
    end
    result
end

end # module
