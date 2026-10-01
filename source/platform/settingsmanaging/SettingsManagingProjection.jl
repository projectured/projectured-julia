# Fragment of `SettingsManagingModule` — the projection that shows the content of
# a `SettingsDocument` and turns each edit of a setting into an applied setting.

"""
    SettingsManagingProjection(inner)

Show the content of a [`SettingsDocument`](@ref) through `inner`, and turn each
normal edit of a settings group into an `ApplySettingOperation`.

The content reads each input first. When it declines, the commands of the
`SettingsDocument` answer. In the answer, each `ReplaceReferencedValueOperation`
whose document is a group of the `Settings`, alone or inside a compound or a
wrapping operation, becomes an `ApplySettingOperation`, which writes the value
and applies the group ([`wrap_setting_writes`](@ref)). So every view of a group
makes the same edit, and none of them contains the effect of a setting. The
projection holds no cell and no edge.
"""
struct SettingsManagingProjection <: Projection
    inner::Projection
end

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct SettingsManagingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::SettingsManagingIoMap) = Any[iomap.child_iomap]

const _CONTENT_STEPS = (FieldReferenceStep("content"),)

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::SettingsManagingProjection, recursion, input::SettingsDocument,
                        ctx)
    child = reconcile_child_iomap(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    SettingsManagingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::SettingsManagingProjection, recursion, change::Intent,
                     iomap::SettingsManagingIoMap)
    child = iomap.child_iomap
    settings = iomap.input.settings
    # A collection takes every answer: the keys of the content, rerooted, then
    # the commands of the settings.
    if change.gesture isa CollectIntents
        inner = read_intent(p.inner, recursion, change, child)
        inner_operation = reroot_operation(inner isa Intent ? inner.operation : inner,
                                           _CONTENT_STEPS)
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
        operation = reroot_operation(answer isa Intent ? answer.operation : answer,
                                     _CONTENT_STEPS)
        return Intent(change.gesture, wrap_setting_writes(settings, operation))
    end
    answer = read_intent(p.inner, recursion, change, child)
    operation = reroot_operation(answer isa Intent ? answer.operation : answer, _CONTENT_STEPS)
    operation isa Operation ||
        (operation = read_gesture(iomap.input, _get_device_event(change.gesture)))
    Intent(change.gesture, wrap_setting_writes(settings, operation))
end

read_intent(p::SettingsManagingProjection, iomap::SettingsManagingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The event of a device under the window that it came from: the commands read the
# event, whatever window holds the focus.
_get_device_event(gesture::WindowInput) = gesture.event
_get_device_event(gesture) = gesture

_get_collected_intents(operation::CollectedIntentsOperation) = operation
_get_collected_intents(_) = nothing

"""
    wrap_setting_writes(settings, operation) -> operation

`operation` with each `ReplaceReferencedValueOperation` of one setting of a group
of `settings` replaced by an `ApplySettingOperation` of it, also inside a
`CompoundOperation` or a `WrappingOperation`. Every other operation stays as it
is.
"""
wrap_setting_writes(settings::Settings, operation) = operation
wrap_setting_writes(settings::Settings, operation::ApplySettingOperation) = operation
wrap_setting_writes(settings::Settings, operation::ReplaceReferencedValueOperation) =
    is_settings_group(settings, operation.document) && is_setting_write(operation) ?
        ApplySettingOperation(operation) : operation
wrap_setting_writes(settings::Settings, operation::CompoundOperation) =
    CompoundOperation(Any[wrap_setting_writes(settings, member)
                          for member in operation.operations])
wrap_setting_writes(settings::Settings, operation::WrappingOperation) =
    rewrap_operation(operation, wrap_setting_writes(settings, get_wrapped_operation(operation)))

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::SettingsManagingProjection, iomap::SettingsManagingIoMap,
                               reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::SettingsManagingProjection, iomap::SettingsManagingIoMap,
                                reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
