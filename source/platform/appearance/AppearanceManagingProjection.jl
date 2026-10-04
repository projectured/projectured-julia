# Fragment of `AppearanceModule` — the projection that shows the content of an
# `AppearanceDocument` and makes the view print again after a change of the
# appearance.

"""
    AppearanceManagingProjection(inner)

Show the content of an [`AppearanceDocument`](@ref) through `inner`, and handle
a change of its `Appearance`.

The content reads each input first. When it declines, the keys of the
`AppearanceDocument` answer: the zoom and the scales. In the answer, each write of
a field of a theme of the appearance, alone or inside a compound or a wrapping
operation, becomes a [`ReplaceThemeValueOperation`](@ref), which prints the view
again, and so does its inverse; so a history that records the write, such as the
one of a window around the appearance tab, takes it back with the view. An answer
that changes the appearance ([`is_appearance_change`](@ref)) gets
`InvalidateProjectionOperation` after it, so the editor prints the whole view
again in the frame, and the inputs after it wait for the new view. The projections read their scaled themes with
no edge, so this is the one place that a change of the appearance reaches the
view. The projection holds no cell and no edge.
"""
struct AppearanceManagingProjection <: Projection
    inner::Projection
end

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct AppearanceManagingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::AppearanceManagingIoMap) = Any[iomap.child_iomap]

const _CONTENT_STEPS = (FieldReferenceStep("content"),)

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::AppearanceManagingProjection, recursion, input::AppearanceDocument, ctx)
    child = make_reconciled_child_iomap_cell(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    AppearanceManagingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::AppearanceManagingProjection, recursion, change::Intent,
                     iomap::AppearanceManagingIoMap)
    child = iomap.child_iomap
    # A collection takes every answer: the keys of the content, rerooted, then
    # the keys of the appearance.
    if change.gesture isa CollectIntents
        inner = read_intent(p.inner, recursion, change, child)
        inner_operation = reroot_operation(inner isa Intent ? inner.operation : inner, _CONTENT_STEPS)
        own = read_gesture(iomap.input, change.gesture)
        return Intent(change.gesture,
                      merge_collected_intents(_get_collected_intents(inner_operation),
                                              _get_collected_intents(own)))
    end
    # An operation with a route goes to the content.
    if change.route !== nothing
        routed = follow_intent_route(change, _CONTENT_STEPS...)
        routed === nothing && return Intent(change.gesture, nothing)
        answer = read_routed_intent(p.inner, recursion, routed, child)
        operation = reroot_operation(answer isa Intent ? answer.operation : answer, _CONTENT_STEPS)
        return Intent(change.gesture, _mark_appearance_change(iomap.input, operation))
    end
    answer = read_intent(p.inner, recursion, change, child)
    operation = reroot_operation(answer isa Intent ? answer.operation : answer, _CONTENT_STEPS)
    operation isa Operation || (operation = read_gesture(iomap.input, _get_device_event(change.gesture)))
    Intent(change.gesture, _mark_appearance_change(iomap.input, operation))
end

read_intent(p::AppearanceManagingProjection, iomap::AppearanceManagingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The event of a device under the window that it came from: the keys of the
# appearance read the key, whatever window holds the focus.
_get_device_event(gesture::WindowInput) = gesture.event
_get_device_event(gesture) = gesture

_get_collected_intents(operation::CollectedIntentsOperation) = operation
_get_collected_intents(_) = nothing

# `operation` with each write of a theme made a `ReplaceThemeValueOperation`, and
# with `InvalidateProjectionOperation` after it when it changes the appearance of
# `document`.
function _mark_appearance_change(document::AppearanceDocument, operation)
    operation = _wrap_theme_writes(document.appearance, operation)
    is_appearance_change(document.appearance, operation) ?
        CompoundOperation(Any[operation, InvalidateProjectionOperation()]) : operation
end

# `operation` with each write of a field of a theme of `appearance` made a
# `ReplaceThemeValueOperation`, also inside a compound or a wrapping operation.
_wrap_theme_writes(appearance::Appearance, operation) = operation
_wrap_theme_writes(appearance::Appearance, operation::ReplaceThemeValueOperation) = operation
_wrap_theme_writes(appearance::Appearance, operation::ReplaceReferencedValueOperation) =
    _is_appearance_theme(appearance, operation.document) ?
        ReplaceThemeValueOperation(operation) : operation
_wrap_theme_writes(appearance::Appearance, operation::CompoundOperation) =
    CompoundOperation(Any[_wrap_theme_writes(appearance, member) for member in operation.operations])
_wrap_theme_writes(appearance::Appearance, operation::WrappingOperation) =
    rewrap_operation(operation, _wrap_theme_writes(appearance, get_wrapped_operation(operation)))

"""
    is_appearance_change(appearance, operation) -> Bool

Whether `operation` changes `appearance`: a step of its zoom or of one of its
scales, a load of a saved appearance, or a write into the appearance or into one
of its themes, alone or inside a compound or a wrapping operation. A write of the
place of the appearance tab or of its open sections changes no look: the tab
follows it, and no view prints again.
"""
is_appearance_change(appearance::Appearance, operation) = false
is_appearance_change(appearance::Appearance,
                     operation::Union{AdjustZoomOperation, AdjustScaleOperation, LoadAppearanceOperation}) =
    operation.appearance === appearance
is_appearance_change(appearance::Appearance, operation::CompoundOperation) =
    any(member -> is_appearance_change(appearance, member), operation.operations)
is_appearance_change(appearance::Appearance, operation::WrappingOperation) =
    is_appearance_change(appearance, get_wrapped_operation(operation))
is_appearance_change(appearance::Appearance, operation::ReplaceReferencedValueOperation) =
    _is_appearance_part(appearance, operation.document) && !_is_tab_state_write(appearance, operation)

# The fields of an `Appearance` that hold the state of the appearance tab.
const _TAB_STATE_FIELDS = ("scroll_position", "open_sections")

# Whether `write` writes one field of `appearance` that holds the state of the tab.
function _is_tab_state_write(appearance::Appearance, write::ReplaceReferencedValueOperation)
    write.document === appearance || return false
    reference = strip_reference_types(write.reference)
    reference isa ConcreteReference && get_reference_tail(reference) isa EmptyReference ||
        return false
    head = get_reference_head(reference)
    head isa AFieldReferenceStep && head.name in _TAB_STATE_FIELDS
end

# Whether `object` is `appearance`, or the theme or the scaled theme of one of
# its domains, or one of its colour themes.
function _is_appearance_part(appearance::Appearance, object)
    object === appearance && return true
    _is_appearance_theme(appearance, object) ||
        any(entry -> object === entry.scaled, values(appearance.themes))
end

# Whether `object` is the theme of a domain of `appearance` or one of its colour
# themes: a write of it is a write of a theme.
_is_appearance_theme(appearance::Appearance, object) =
    any(entry -> object === entry.theme, values(appearance.themes)) ||
    any(theme -> object === theme, values(appearance.color_themes))

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::AppearanceManagingProjection, iomap::AppearanceManagingIoMap,
                               reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::AppearanceManagingProjection, iomap::AppearanceManagingIoMap,
                                reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
