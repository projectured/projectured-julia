# Fragment of `VersioningModule`.
#
# The version-elimination projection — the direct analogue of
# `ClipboardSliceToAnyProjection` (`ClipboardModule`).
#
# `VersioningToAnyProjection` sits on top of a `VersionedObject` document. Its
# printer selects one `ObjectVersion` according to the document's `criterion`
# (`select_version`) and projects that version's **value object** in place of the
# wrapper — so the output is a plain, non-versioned document and the wrapper
# vanishes. Because the elimination is purely structural and recurses through
# `print_child`, nested `VersionedObject`s inside a selected value
# resolve automatically, each by its own criterion.
#
# The reader delegates non-versioning gestures into the selected value's child
# reader and re-roots the returned operation under `versions[idx].value` (the
# School-A pattern — delegate through the stored child IoMap, never re-walk by
# document type). Own gestures snapshot a new version
# (`insert_elements` on `versions`) or remove the active one (`delete_elements`) —
# the same standard, universally-rerooted sequence splices the clipboard uses;
# `SetVersionCriterionOperation` switches the active criterion.
#
# ## Criterion swapping
#
# `criterion` lives on the document as a `Cell`, and the printer defers
# `select_version` into a derived `selection_cell`, so `SetVersionCriterionOperation`
# is a plain reactive cell write: the new version is selected and re-printed and the
# reactive `ChainingProjection` re-pulls the output downstream, with **no
# `editor.iomap` drop** (mirroring `ToggleClipboardSliceOperation`).
#
# ## Empty / no-match
#
# When `select_version` returns `nothing` (an empty `versions` list, or a
# criterion that matches no version) the printer emits a `DocumentNothing`,
# mirroring `ClipboardSlice`'s empty-slice fallback. The reference maps and the
# delegating reader then have no child to descend into and decline.
# ── Projection ────────────────────────────────────────────────────────────────

"""
    VersioningToAnyProjection(; author = nothing)

Projects a `VersionedObject`. The output is the projection of the value object
of the version selected by the document's own `criterion`; the wrapper vanishes.
When no version matches, the output is a `DocumentNothing`. The criterion lives
on the document (not the projection) so different versioned nodes in one tree can
be viewed under different criteria simultaneously, and a single projection
instance serves every versioned node.

A version that Ctrl+Shift+S makes gets `author` and the time, `time()`, as its
properties. `author = nothing` names the user of the system, `Sys.username()`,
when the version is made.
"""
struct VersioningToAnyProjection <: Projection
    author::Union{Nothing, String}
end

VersioningToAnyProjection(; author = nothing) =
    VersioningToAnyProjection(author === nothing ? nothing : String(author))

# ── IoMap ─────────────────────────────────────────────────────────────────────

# `selection_cell` holds `(idx, value_iomap)` for the version `criterion` currently
# selects, or `nothing`. It is derived from `input.criterion`, so a criterion change
# re-derives it (re-printing the newly-selected version's value) with no
# `editor.iomap` drop. `output`/`index`/`value_iomap` read it transparently via
# `getproperty`, so the reference maps and reader see the *current* selection and the
# reactive `ChainingProjection` re-pulls the output downstream.
@iomap struct VersioningToAnyIoMap
    projection::Any
    input::Any                # VersionedObject
    selection_cell::Any       # Cell of (idx, value_iomap) or nothing
    output::Any               # computed: value child output, or DocumentNothing
    index::Any                # computed: selected version index, or nothing
    value_iomap::Any          # computed: the selected value's child IoMap, or nothing
end

# ── Printer ───────────────────────────────────────────────────────────────────

function print_document(p::VersioningToAnyProjection, recursion, input::VersionedObject, ctx)
    selection_cell = Cell(Computed(() -> begin
        selected = select_version(input)
        selected === nothing && return nothing
        idx, version = selected
        value_iomap = print_child(recursion, version.value,
                          make_child_context(ctx, FieldReferenceStep("versions"),
                                        ElementReferenceStep(idx), FieldReferenceStep("value")))
        (idx, value_iomap)
    end))
    output = Cell(Computed(() -> begin
        sel = selection_cell[]
        sel === nothing ? DocumentNothing() : sel[2].output
    end))
    index = Cell(Computed(() -> (sel = selection_cell[]; sel === nothing ? nothing : sel[1])))
    value_iomap = Cell(Computed(() -> (sel = selection_cell[]; sel === nothing ? nothing : sel[2])))
    VersioningToAnyIoMap(p, input, selection_cell, output, index, value_iomap)
end

# ── Reference mapping ─────────────────────────────────────────────────────────
# The output is the selected value's output directly (the wrapper is invisible),
# so the maps are asymmetric: forward peels the three steps that reach
# `versions[idx].value` and returns the child's reference unwrapped; backward
# delegates to the child and prepends those same three steps so the path is
# rooted at the VersionedObject.

function map_reference_forward(::VersioningToAnyProjection, iomap::VersioningToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    child = iomap.value_iomap
    child === nothing && return nothing
    idx = iomap.index
    # Require the path to descend through versions[idx].value, stripping all three.
    h = get_reference_head(reference)
    (h isa FieldReferenceStep && h.name == "versions") || return nothing
    rest = get_reference_tail(reference)
    rest isa ConcreteReference || return nothing
    e = get_reference_head(rest)
    (e isa RangeReferenceStep && e.start + 1 == idx) || return nothing
    rest2 = get_reference_tail(rest)
    rest2 isa ConcreteReference || return nothing
    f = get_reference_head(rest2)
    (f isa FieldReferenceStep && f.name == "value") || return nothing
    map_reference_forward(child.projection, child, get_reference_tail(rest2))
end

function map_reference_backward(::VersioningToAnyProjection, iomap::VersioningToAnyIoMap, reference)
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
downstream — no `editor.iomap` drop (see `ToggleClipboardSliceOperation`).
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
# splice (insert_elements) so every ancestor projection re-roots it. The version
# has the author of the projection and the time as its properties. Returns
# nothing when there is no selected value to snapshot.
function _create_version(p::VersioningToAnyProjection, iomap::VersioningToAnyIoMap)
    version = iomap.index === nothing ? nothing : iomap.input.versions[iomap.index]
    version isa ObjectVersion || return nothing
    saved_value = copy_document(version.value)
    clear_selection!(saved_value)               # a saved version carries no cursor
    snapshot = ObjectVersion(saved_value; timestamp = time(),
                             author = p.author === nothing ? Sys.username() : p.author)
    insert_elements(_field_path("versions"), 0, Any[snapshot])
end

# Delete the currently selected version (the active one). A standard sequence
# splice (delete_elements, 0-based index), re-rooted by every ancestor.
function _delete_version(iomap::VersioningToAnyIoMap)
    iomap.index === nothing && return nothing
    delete_elements(_field_path("versions"), iomap.index - 1)
end

# Own gestures, reified as a `get_projection_gesture_bindings` table so the same set that
# fires (via `read_projection_gesture`) is the one a listing shows. The
# operations capture `iomap` (they snapshot/delete the selected version) and
# return `nothing` to decline (no selected version), falling through to the
# value-child delegation. ModifierKeys are matched exactly.
function get_projection_gesture_bindings(p::VersioningToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:s; modifiers = [:ctrl, :shift]),
                       (doc, event) -> _create_version(p, iomap);
                       description = "Create version", domain = "versioning",
                       name = "Create version"),
        GestureBinding(KeyDownPattern(:delete; modifiers = [:ctrl]),
                       (doc, event) -> _delete_version(iomap);
                       description = "Delete version", domain = "versioning",
                       name = "Delete version"),
    ]
end

# ── Reader ─────────────────────────────────────────────────────────────────────

function read_intent(p::VersioningToAnyProjection, recursion, change::Intent,
                         iomap::VersioningToAnyIoMap)
    own = read_projection_gesture(p, iomap, change.gesture)
    vim = iomap.value_iomap
    # The steps exist only when a version is selected — `iomap.index` is `nothing`
    # otherwise, so build them behind the same guard the delegation uses.
    value_steps() = (FieldReferenceStep("versions"), ElementReferenceStep(iomap.index),
                     FieldReferenceStep("value"))
    # Routing one gesture stops at the first answer; a collection takes both, with
    # the value's prefixed exactly as its operations are.
    if change.gesture isa CollectIntents
        child = vim === nothing ? nothing :
                _prefix_op(read_intent(vim.projection, recursion, change, vim).operation,
                           value_steps())
        return Intent(change.gesture,
                      merge_collected_intents(_collected_intents(own),
                                              _collected_intents(child)))
    end
    own !== nothing && return Intent(change.gesture, own)
    vim === nothing && return Intent(change.gesture, nothing)
    inner = read_intent(vim.projection, recursion, change, vim)
    Intent(change.gesture, _prefix_op(inner.operation, value_steps()))
end

# 3-arg payload form (used by tests and any parent that hands a bare payload).
read_intent(p::VersioningToAnyProjection, iomap::VersioningToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Operation re-rooting ───────────────────────────────────────────────────────
# Prepend `steps` to the reference path carried by a delegated value operation,
# so it is rooted at the VersionedObject rather than at the selected value.

# Only a real collection merges; anything else a reader returned is not one.
_collected_intents(op::CollectedIntentsOperation) = op
_collected_intents(::Any) = nothing

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
    elseif op isa WrappingOperation
        rewrap_operation(op, _prefix_op(get_wrapped_operation(op), steps))
    elseif op isa CollectedIntentsOperation
        # Every seam that prefixes a compound must prefix a collection the same way.
        CollectedIntentsOperation([Intent(i.gesture, _prefix_op(i.operation, steps),
                                          i.description, i.domain)
                                   for i in op.intents])
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
