"""
    VersioningToAnyProjectionModule

The version-elimination projection — the direct analogue of
`ClipboardSliceToAnyProjection` (`ClipboardToAnyProjectionModule`).

`VersioningToAnyProjection` sits on top of a `VersionedObject` document. Its
printer selects one `ObjectVersion` according to the document's `criterion`
(`select_version`) and projects that version's **value object** in place of the
wrapper — so the output is a plain, non-versioned document and the wrapper
vanishes. Because the elimination is purely structural and recurses through
`projection_printer_recurse`, nested `VersionedObject`s inside a selected value
resolve automatically, each by its own criterion.

The reader delegates non-versioning gestures into the selected value's child
reader and re-roots the returned operation under `versions[idx].value` (the
School-A pattern — delegate through the stored child IoMap, never re-walk by
document type). Own gestures snapshot a new version
(`CollectionInsertOperation` on `versions`) or remove the active one
(`CollectionDeleteOperation`) — the same standard, universally-rerooted
collection operations the clipboard uses; `SetVersionCriterionOperation`
switches the active criterion.

## Criterion swapping

`SetVersionCriterionOperation` swaps which child becomes the output, so it
cannot update reactively in place. Like the clipboard display toggle, it drops
`editor.iomap`, forcing the next `print!` to rebuild the projection on the new
criterion (mirroring `ToggleClipboardSliceDisplayOperation`).

## Empty / no-match

When `select_version` returns `nothing` (an empty `versions` list, or a
criterion that matches no version) the printer emits a `DocumentNothing`,
mirroring `ClipboardSlice`'s empty-slice fallback. The reference maps and the
delegating reader then have no child to descend into and decline.
"""
module VersioningToAnyProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValue,
                          CollectionInsertOperation, CollectionDeleteOperation, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..ReactiveModule: Cell
import ..DocumentModule: Document
import ..DocumentCoreModule: DocumentNothing
import ..DocumentCopyModule: copy_document
import ..VersioningModule: VersionedObject, ObjectVersion, VersionProperties,
                          VersionCriterion, VersionCriterionLatest, select_version
import ..CollectionModule: CellVector
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference, ElementReference,
                          evaluate_reference, head, tail
import ..PrinterContextModule: PrinterContext, child_context
import ..IoMapApiModule: IoMap
import ..KeyboardModule: KeyDown
import ..EventCaseModule: var"@event_case"

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

struct VersioningToAnyProjectionIoMap <: IoMap
    projection::VersioningToAnyProjection
    input::Any              # VersionedObject
    output::Any             # selected version's value child output, or DocumentNothing
    index::Any              # 1-based index of the selected version, or nothing
    value_iomap::Any        # iomap of the selected version's value, or nothing
end

# ── Printer ───────────────────────────────────────────────────────────────────

function projection_print(p::VersioningToAnyProjection, recursion, input::VersionedObject, ctx)
    selected = select_version(input)
    if selected === nothing
        # No matching version: emit a DocumentNothing (the empty-slice fallback).
        return VersioningToAnyProjectionIoMap(p, input, DocumentNothing(), nothing, nothing)
    end
    idx, version = selected
    value_iomap = projection_printer_recurse(recursion, version.value,
                      child_context(ctx, FieldReference("versions"),
                                    ElementReference(idx), FieldReference("value")))
    VersioningToAnyProjectionIoMap(p, input, value_iomap.output, idx, value_iomap)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the selected value's output directly (the wrapper is invisible),
# so the maps are asymmetric: forward peels the three steps that reach
# `versions[idx].value` and returns the child's reference unwrapped; backward
# delegates to the child and prepends those same three steps so the path is
# rooted at the VersionedObject.

function map_reference_forward(::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, reference)
    reference isa ConcreteReferencePath || return reference
    child = iomap.value_iomap
    child === nothing && return nothing
    idx = iomap.index
    # Require the path to descend through versions[idx].value, stripping all three.
    h = head(reference)
    (h isa FieldReference && h.name == "versions") || return nothing
    rest = tail(reference)
    rest isa ConcreteReferencePath || return nothing
    e = head(rest)
    (e isa RangeReference && e.start + 1 == idx) || return nothing
    rest2 = tail(rest)
    rest2 isa ConcreteReferencePath || return nothing
    f = head(rest2)
    (f isa FieldReference && f.name == "value") || return nothing
    map_reference_forward(child.projection, child, tail(rest2))
end

function map_reference_backward(::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, reference)
    child = iomap.value_iomap
    child === nothing && return nothing
    idx = iomap.index
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReferencePath(FieldReference("versions"),
        ConcreteReferencePath(ElementReference(idx),
            ConcreteReferencePath(FieldReference("value"), mapped)))
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
    SetVersionCriterionOperation(target, criterion)

Replace the `criterion` of the `target` `VersionedObject` (e.g. switch from
*latest* to *as-of T*, or pin an index). Like the clipboard display toggle, this
swaps which child becomes the output, so it drops `editor.iomap` to force a
rebuild on the new criterion (see `ToggleClipboardSliceDisplayOperation`).
"""
struct SetVersionCriterionOperation <: Operation
    target::Any
    criterion::VersionCriterion
end

function evaluate_operation(editor, op::SetVersionCriterionOperation)
    op.target === nothing && return
    op.target.criterion = op.criterion
    editor.iomap = nothing
end

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReferencePath(FieldReference(name), EmptyReferencePath())

# Snapshot the current selected value into a new ObjectVersion (deep-copied) and
# push it to the front of `versions` (index 0, newest-first). A standard
# CollectionInsertOperation so every ancestor projection re-roots it. Returns
# nothing when there is no selected value to snapshot.
function _create_version(iomap::VersioningToAnyProjectionIoMap)
    version = iomap.index === nothing ? nothing : iomap.input.versions[iomap.index]
    version isa ObjectVersion || return nothing
    snapshot = ObjectVersion(copy_document(version.value))
    CollectionInsertOperation(_field_path("versions"), 0, Any[snapshot])
end

# Delete the currently selected version (the active one). A standard
# CollectionDeleteOperation (0-based index), re-rooted by every ancestor.
function _delete_version(iomap::VersioningToAnyProjectionIoMap)
    iomap.index === nothing && return nothing
    CollectionDeleteOperation(_field_path("versions"), iomap.index - 1)
end

# ── Reader ─────────────────────────────────────────────────────────────────────

function projection_read(p::VersioningToAnyProjection, recursion, change::Change,
                         iomap::VersioningToAnyProjectionIoMap)
    own = @event_case change.gesture begin
        KeyDown(:s; ctrl, shift) => _create_version(iomap)
        KeyDown(:delete; ctrl)   => _delete_version(iomap)
    end
    own !== nothing && return Change(change.gesture, own)
    vim = iomap.value_iomap
    vim === nothing && return Change(change.gesture, nothing)
    inner = projection_read(vim.projection, recursion, change, vim)
    Change(change.gesture, _prefix_op(inner.operation,
        (FieldReference("versions"), ElementReference(iomap.index), FieldReference("value"))))
end

# 3-arg legacy shim (used by tests and any parent that hands a bare payload).
projection_read(p::VersioningToAnyProjection, iomap::VersioningToAnyProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# ── Operation re-rooting ───────────────────────────────────────────────────────
# Prepend `steps` to the reference path carried by a delegated value operation,
# so it is rooted at the VersionedObject rather than at the selected value.

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
    elseif op isa CollectionInsertOperation
        CollectionInsertOperation(_prepend(steps, op.path), op.index, op.items,
            op.selection === nothing ? nothing : _prepend(steps, op.selection))
    elseif op isa CollectionDeleteOperation
        CollectionDeleteOperation(_prepend(steps, op.path), op.index, op.count)
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
