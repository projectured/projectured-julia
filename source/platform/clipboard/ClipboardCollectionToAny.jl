# Fragment of `ClipboardModule`.
#
# The internal-clipboard collection projection — Julia port of Lisp's
# `clipboard/collection->t` (`source/projection/primitive/clipboard-to-t.lisp`).
#
# `ClipboardCollectionToAnyProjection` sits on a `ClipboardCollection` document
# and shows either the wrapped `content` or the `elements` collection, toggled by
# `Ctrl+*`. `Ctrl+=` adds the selected object to the collection and `Ctrl+-`
# removes the selected element.
#
# It prints the child on display through its recursion, with the context of that
# child: the wrapped `content`, or the `elements` vector as one document, which
# only a projection that draws a vector can render. It reads its own gestures
# first, delegates every other gesture to the child on display, and re-roots the
# returned operation under that child's field. That is the School-A pattern:
# delegate through the stored child IoMap, never re-walk by document type.
#
# The display flag is a `Cell`, and the projection's `output` is a derived cell
# over it, so to flip the flag switches the output with no new print of the
# content.

# ── Projection ───────────────────────────────────────────────────────────

"""
    ClipboardCollectionToAnyProjection(; display_collection=false)

Projects a `ClipboardCollection`. When `display_collection` is `false` the output
is the projection of `content`; when `true` it is the projection of the
`elements` vector.
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
    output::Any             # content child output, or the output of the elements vector
    content_iomap::Any
    elements_iomap::Any     # iomap of the elements vector while it is on display, or nothing
end

# ── Printer ──────────────────────────────────────────────────────────────

function print_document(p::ClipboardCollectionToAnyProjection, recursion, input::ClipboardCollection, ctx)
    content_iomap = print_child(recursion, input.content,
                        make_child_context(ctx, FieldReferenceStep("content")))
    # The elements vector is printed as one document, and only while it is on
    # display. The cell reads the flag, so a toggle prints it.
    elements_iomap = reconcile_child_iomap(
        () -> p.display_collection[] ? input.elements : nothing,
        elements -> elements === nothing ? nothing :
            print_child(recursion, elements, make_child_context(ctx, FieldReferenceStep("elements"))))
    # Reactive output (see the slice printer): a derived cell over the display
    # flag, so a toggle switches the output with no `editor.iomap` drop.
    output = Cell(@computation begin
        elements = elements_iomap[]
        elements === nothing ? content_iomap.output : elements.output
    end)
    ClipboardCollectionToAnyIoMap(p, input, output, content_iomap, elements_iomap)
end

# ── Reference mapping ────────────────────────────────────────────────────

# Active child for a collection projection: ("field-name", child-iomap). The
# elements iomap exists only while the elements are on display.
function _collection_active(iomap::ClipboardCollectionToAnyIoMap)
    elements = iomap.elements_iomap
    elements === nothing ? ("content", iomap.content_iomap) : ("elements", elements)
end

function map_reference_forward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    name, child = _collection_active(iomap)
    h = get_reference_head(reference)
    (h isa FieldReferenceStep && h.name == name) || return nothing
    map_reference_forward(child.projection, child, get_reference_tail(reference))
end

function map_reference_backward(::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, reference)
    name, child = _collection_active(iomap)
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep(name), mapped)
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
        GestureBinding(KeyDownPattern(:asterisk; modifiers = [:ctrl]),
                       (doc, event) -> ToggleClipboardCollectionOperation(p);
                       description = "Toggle collection", domain = "clipboard",
                       name = "Toggle collection"),
        GestureBinding(KeyDownPattern(:equals; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_collection_add(doc);
                       description = "Add to collection", domain = "clipboard",
                       name = "Add to collection"),
        GestureBinding(KeyDownPattern(:minus; modifiers = [:ctrl]),
                       (doc, event) -> _clipboard_collection_remove(doc);
                       description = "Remove from collection", domain = "clipboard",
                       name = "Remove from collection"),
    ]
end

function read_intent(p::ClipboardCollectionToAnyProjection, recursion, change::Intent,
                         iomap::ClipboardCollectionToAnyIoMap)
    name, child = _collection_active(iomap)
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
read_intent(p::ClipboardCollectionToAnyProjection, iomap::ClipboardCollectionToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
