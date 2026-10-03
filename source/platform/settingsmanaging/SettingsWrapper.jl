# Fragment of `SettingsManagingModule` — the `settings` wrapper of `build_editor`.

"""
    settings = true | Settings

The wrapper of `build_editor` that puts the root document inside a
[`SettingsDocument`](@ref) and the projection inside a
[`SettingsManagingProjection`](@ref), around everything but the appearance
wrapper, which stays the root. It is on by default.

Its argument is the `Settings` of the editor. A main builder makes it, fills it
from its sources, builds the projection with it, and passes it. For `true` the
wrapper makes a new one with the default group of each loaded group type, whose
values come from the editor when it starts. Another wrapper reads it from
`EditorParts.arguments`, as the `window` wrapper does for the pointer.

A start step brings the values to the places where they act, once the editor
exists ([`start_settings!`](@ref)).
"""
function wrap_editor!(::Val{:settings}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa SettingsDocument && return parts
    settings = make_wrapper_argument(Val(:settings), argument)::Settings
    parts.document = make_settings_document(parts.document, settings)
    parts.projection = SettingsManagingProjection(parts.projection)
    push!(parts.start_steps, editor -> start_settings!(editor, settings))
    parts
end

function make_wrapper_argument(::Val{:settings}, argument::Bool)
    settings = make_settings()
    settings.is_read_from_targets = true
    settings
end
make_wrapper_argument(::Val{:settings}, argument::Settings) = argument

get_wrapper_layers(::Val{:settings}) = (:screen => -10,)
is_wrapper_default(::Val{:settings}) = true

"""
    start_settings!(editor, settings) -> nothing

The start step of the `settings` wrapper. When `settings.is_read_from_targets`
is `true`, read each group from `editor` and its backend, and then the
environment, which wins for one run. Then apply each group to `editor` and to its
backend, and keep the types of the groups that the editor does not use.
"""
function start_settings!(editor, settings::Settings)
    if settings.is_read_from_targets
        for group in get_settings_groups(settings)
            read_settings_from_editor!(editor, group)
        end
        read_settings_environment!(settings)
    end
    for group in get_settings_groups(settings)
        apply_settings_to_editor!(editor, group)
    end
    settings.unused_types = Any[get_settings_group_type(group)
                                for group in get_settings_groups(settings)
                                if !is_settings_group_used(editor, group)]
    nothing
end
