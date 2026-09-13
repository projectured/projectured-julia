# ──────────────────────────────────────────────────────────────────────────
# Folded in from ClipboardCollectionToAny.jl.
#
# The internal-clipboard collection projection — Julia port of Lisp's
# `clipboard/collection->t` (`source/projection/primitive/clipboard-to-t.lisp`).
#
# `ClipboardCollectionToAnyProjection` sits on a `ClipboardCollection` document
# and shows either the wrapped `content` or the `elements` collection, toggled by
# `Ctrl+*`. `Ctrl+=` adds the selected object to the collection and `Ctrl+-`
# removes the selected element.
#
# It delegates every non-clipboard gesture into its `content` child reader and
# re-roots the returned operation under the `content` field. That is the School-A
# pattern: delegate through the stored child IoMap, never re-walk by document
# type.
#
# The display flag is a `Cell`, and the projection's `output` is a derived cell
# over it, so to flip the flag re-prints only the downstream stages.

# ── Projection ───────────────────────────────────────────────────────────

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

# ── IoMap ────────────────────────────────────────────────────────────────

@iomap struct ClipboardCollectionToAnyIoMap
    projection::ClipboardCollectionToAnyProjection
    input::Any              # ClipboardCollection
    output::Any             # content child output, or CellVector of element outputs
    content_iomap::Any
    element_iomaps::Any     # Vector of per-element child iomaps
end

# ── Printer ──────────────────────────────────────────────────────────────

function print_document(p::ClipboardCollectionToAnyProjection, recursion, input::ClipboardCollection, ctx)
    content_iomap = print_child(recursion, input.content,
                        make_child_context(ctx, FieldReferenceStep("content")))
    # Reconcile the element children by identity so a structural edit to
    # `elements` reuses surviving child iomaps (PAR-STABLE-IOMAP-IDENTITY).
    element_iomaps = reconcile_child_iomaps(
        () -> input.elements,
        (i, x) -> print_child(recursion, x,
            make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i))))
    # Reactive output (see the slice printer): a derived cell over the display flag,
    # re-pulled by the reactive ChainingProjection — no `editor.iomap` drop.
    output = ComputedCell(() -> p.display_collection[] ?
        CellVector(Cell[Cell(im.output) for im in element_iomaps[]]) :
        content_iomap.output)
    ClipboardCollectionToAnyIoMap(p, input, output, content_iomap, element_iomaps)
end

# ── Reference mapping ────────────────────────────────────────────────────

function map_reference_forward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    if iomap.projection.display_collection[]
        h = head(reference)
        (h isa FieldReferenceStep && h.name == "elements") || return nothing
        rest = tail(reference)
        rest isa ConcreteReference || return nothing
        e = head(rest)
        e isa RangeReferenceStep || return nothing
        i = e.stop
        ims = iomap.element_iomaps[]
        (i < 1 || i > length(ims)) && return nothing
        child = ims[i]
        mapped = map_reference_forward(child.projection, child, tail(rest))
        mapped === nothing && return nothing
        ConcreteReference(e, mapped)
    else
        h = head(reference)
        (h isa FieldReferenceStep && h.name == "content") || return nothing
        child = iomap.content_iomap
        map_reference_forward(child.projection, child, tail(reference))
    end
end

function map_reference_backward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, reference)
    if iomap.projection.display_collection[]
        reference isa ConcreteReference || return reference
        e = head(reference)
        e isa RangeReferenceStep || return nothing
        i = e.stop
        ims = iomap.element_iomaps[]
        (i < 1 || i > length(ims)) && return nothing
        child = ims[i]
        mapped = map_reference_backward(child.projection, child, tail(reference))
        mapped === nothing && return nothing
        ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(e, mapped))
    else
        child = iomap.content_iomap
        mapped = map_reference_backward(child.projection, child, reference)
        mapped === nothing && return nothing
        ConcreteReference(FieldReferenceStep("content"), mapped)
    end
end

# ── Operations ───────────────────────────────────────────────────────────

"""
    ToggleClipboardCollectionOperation(projection)

Flip the `display_collection` `Cell` of a `ClipboardCollectionToAnyProjection`.
A plain reactive cell write (see `ToggleClipboardSliceOperation`).
"""
struct ToggleClipboardCollectionOperation <: Operation
    projection::ClipboardCollectionToAnyProjection
end

function evaluate_operation(editor, op::ToggleClipboardCollectionOperation)
    # Reactive cell write only — NO editor.iomap drop.
    op.projection.display_collection[] = !op.projection.display_collection[]
end

# ── Reader gesture helpers ───────────────────────────────────────────────

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
    path isa ConcreteReference || return nothing
    h = path.head
    (h isa FieldReferenceStep && h.name == "elements") || return nothing
    rest = path.tail
    rest isa ConcreteReference || return nothing
    e = rest.head
    e isa RangeReferenceStep || return nothing
    e.start
end

# ── Readers ──────────────────────────────────────────────────────────────

function get_projection_gesture_bindings(p::ClipboardCollectionToAnyProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:asterisk, [:ctrl], nothing),
            (doc, event) -> ToggleClipboardCollectionOperation(p),
            (doc, sel) -> true, "Toggle collection", "clipboard", false, "Toggle collection"),
        GestureBinding(KeyDownPattern(:equals, [:ctrl], nothing),
            (doc, event) -> _clipboard_collection_add(doc),
            (doc, sel) -> true, "Add to collection", "clipboard", false, "Add to collection"),
        GestureBinding(KeyDownPattern(:minus, [:ctrl], nothing),
            (doc, event) -> _clipboard_collection_remove(doc),
            (doc, sel) -> true, "Remove from collection", "clipboard", false, "Remove from collection"),
    ]
end

function read_intent(p::ClipboardCollectionToAnyProjection, recursion, change::Intent,
                         iomap::ClipboardCollectionToAnyIoMap)
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
read_intent(p::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
