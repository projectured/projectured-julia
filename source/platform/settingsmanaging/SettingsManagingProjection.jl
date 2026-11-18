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
    child = make_reconciled_child_iomap_cell(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    SettingsManagingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

# The content reads a change first, and the commands of the settings answer what the
# content declines (`read_gesture` below). `wrap_setting_writes` marks each answer
# that writes a setting.
function read_intent(p::SettingsManagingProjection, recursion, change::Intent,
                     iomap::SettingsManagingIoMap)
    answer = read_child_intent(p, recursion, change, iomap, iomap.child_iomap, _CONTENT_STEPS;
                               read_child = (_, r, c, child) -> read_routed_intent(p.inner, r, c, child))
    change.gesture isa CollectIntents && return answer
    Intent(answer.gesture, wrap_setting_writes(iomap.input.settings, answer.operation),
           answer.description, answer.domain)
end

# The event of a device under the window that it came from: the commands read the
# event, whatever window holds the focus.
_get_device_event(gesture::WindowInput) = gesture.event
_get_device_event(gesture) = gesture

# The table of the settings reads the event of the device, whatever window holds the
# focus.
read_gesture(p::SettingsManagingProjection, iomap::SettingsManagingIoMap, gesture; answer = nothing) =
    invoke(read_gesture, Tuple{Projection, Any, Any}, p, iomap, _get_device_event(gesture); answer)

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
