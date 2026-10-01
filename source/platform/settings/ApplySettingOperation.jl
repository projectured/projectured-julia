# Fragment of `SettingsModule` — the write of a setting and its apply, and the seam
# that copies a group to the place where it acts.

"""
    apply_settings!(target, group) -> nothing

Copy the values of `group` to `target`, where they act outside the documents: a
field of a backend, the fault policy of an editor. The default does nothing. The
slice or the package that owns a target adds a method for each group that acts on
it, and the method can also ask for a new print of the view.

[`ApplySettingOperation`](@ref) calls it with the editor and with its backend, and
the `settings` wrapper calls it once for each group when the editor starts.
"""
apply_settings!(target, group::SettingsGroup) = nothing

"""
    is_settings_target(target, group) -> Bool

Whether a method of [`apply_settings!`](@ref) copies `group` to `target`. A view of
the settings shows a group that no target of its editor applies as not used.
"""
is_settings_target(target, group::SettingsGroup) =
    which(apply_settings!, Tuple{typeof(target), typeof(group)}).sig !=
        Tuple{typeof(apply_settings!), Any, SettingsGroup}

"""
    apply_settings_to_editor!(editor, group) -> nothing

Apply `group` to each target of `editor`: the editor, and its backend.
"""
function apply_settings_to_editor!(editor, group::SettingsGroup)
    apply_settings!(editor, group)
    hasproperty(editor, :backend) && apply_settings!(editor.backend, group)
    nothing
end

"""
    ApplySettingOperation(write)
    ApplySettingOperation(group, name, value)

`write`, a `ReplaceReferencedValueOperation` of one setting of a settings group,
and then the apply of the group. The evaluation checks the value against the
description of the setting, converts it, writes it, and applies the group to the
editor and to its backend with [`apply_settings_to_editor!`](@ref). A value that
does not fit changes nothing, and the evaluation writes a warning to the log.

The inverse writes the old value and then applies the group, so the targets get
the old value back. The `settings` wrapper makes this operation from a normal edit
of a group, and any other path, such as the inbox, can post it as it is.
"""
struct ApplySettingOperation <: WrappingOperation
    operation::ReplaceReferencedValueOperation
    function ApplySettingOperation(operation::ReplaceReferencedValueOperation)
        operation.document isa SettingsGroup ||
            throw(ArgumentError("ApplySettingOperation writes into a settings group, " *
                                "not into $(typeof(operation.document))"))
        _get_setting_name(operation.reference) === nothing &&
            throw(ArgumentError("ApplySettingOperation writes one field of a group, " *
                                "not $(operation.reference)"))
        new(operation)
    end
end

function ApplySettingOperation(group::SettingsGroup, name::Symbol, value)
    reference = ConcreteReference(FieldReferenceStep(String(name)), EmptyReference())
    ApplySettingOperation(ReplaceReferencedValueOperation(group, reference, value))
end

get_wrapped_operation(operation::ApplySettingOperation) = operation.operation
rewrap_operation(::ApplySettingOperation, inner) = ApplySettingOperation(inner)

# The name of the field that a write into a group names, or `nothing` for a
# reference that is not one field.
function _get_setting_name(reference)
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    head isa AFieldReferenceStep && get_reference_tail(reference) isa EmptyReference ||
        return nothing
    Symbol(head.name)
end

_find_setting_description(operation::ApplySettingOperation) =
    find_setting_description(get_settings_group_type(operation.operation.document),
                             _get_setting_name(operation.operation.reference))

function evaluate_operation(editor, operation::ApplySettingOperation)
    write = operation.operation
    group = write.document
    description = _find_setting_description(operation)
    if description === nothing
        @warn "The group $(get_settings_group_type(group)) has no setting " *
              "$(_get_setting_name(write.reference))."
        return nothing
    end
    value = convert_setting_value(description, write.value)
    if value === nothing
        @warn "The setting \"$(description.label)\" can not take $(repr(write.value))."
        return nothing
    end
    evaluate_operation(editor,
                       ReplaceReferencedValueOperation(group, write.reference, value))
    apply_settings_to_editor!(editor, group)
    nothing
end

function make_inverse_operation(document, operation::ApplySettingOperation)
    inverse = make_inverse_operation(document, operation.operation)
    inverse isa ReplaceReferencedValueOperation ? ApplySettingOperation(inverse) : inverse
end

function describe_operation(operation::ApplySettingOperation)
    description = _find_setting_description(operation)
    label = description === nothing ?
        string(_get_setting_name(operation.operation.reference)) :
        lowercase(description.label)
    "set " * label * " to " * _describe_setting_value(operation.operation.value)
end

_describe_setting_value(value::Bool) = value ? "on" : "off"
_describe_setting_value(value::Symbol) = String(value)
_describe_setting_value(value) = repr(value)

# It carries the group that it writes, so it travels up a chain as it is.
operation_travels_unchanged(::ApplySettingOperation) = true
