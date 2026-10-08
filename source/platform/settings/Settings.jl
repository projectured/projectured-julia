# Fragment of `SettingsModule` — the settings groups of one editor.

"""
    Settings()

The settings of one editor: one group of each type, found by the type of the
group, as an `Appearance` holds the themes of an editor.

The main builder of an editor makes one, builds its projection with it, and gives
it to the `settings` wrapper of `build_editor`. A part that acts on a setting
takes its group with [`get_settings_group!`](@ref) while it is built.

`is_read_from_targets` says where the values come from when the editor starts.
When it is `false`, the values of the groups win, as a main builder that read a
file wants. When it is `true`, as for the `Settings` that the wrapper makes for a
caller that gives none, the start step first reads each group from the editor
and its backend with [`read_settings!`](@ref), so a value that the caller gave a
target directly stays.

`unused_types` holds the group types that no target of the editor applies,
which the start step finds with [`is_settings_group_used`](@ref), so a view can
show them as not used.

`file` is the settings file that Save and Load of a view use, or empty for
settings with no file, such as those of a test.
"""
@document struct Settings
    groups::Dict{Type,Any} = Dict{Type,Any}()
    is_read_from_targets::Bool = false
    unused_types::Vector{Any} = Any[]
    file::String = ""
end

# A tab that shows the settings is named so, whatever opens it.
get_document_title(::Settings) = "Settings"

"""
    compute_loaded_settings_types() -> Vector{Type}

The settings group types of the loaded packages, in the order of their names in a
settings file. `@settings` adds a method of `get_setting_descriptions` for each
group type, so the method table is the list, and no table names the groups.
"""
function compute_loaded_settings_types()
    types = Type[]
    for method in methods(get_setting_descriptions)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        argument = signature.parameters[2]
        (argument isa DataType && argument <: Type && length(argument.parameters) == 1) ||
            continue
        T = argument.parameters[1]
        T isa Type && push!(types, T)
    end
    sort!(unique!(types); by = get_settings_name)
end

"""
    make_settings(groups...) -> Settings

A new `Settings` that holds `groups`, and the default group of each other group
type of the loaded packages.
"""
function make_settings(groups::SettingsGroup...)
    settings = Settings()
    for group in groups
        set_settings_group!(settings, group)
    end
    for T in compute_loaded_settings_types()
        get_settings_group!(settings, T)
    end
    settings
end

"""
    get_settings_group!(settings, T) -> SettingsGroup

The group of the type `T` in `settings`. When `settings` holds no group of `T`,
this makes the default group `T()`, puts it into `settings`, and answers it.

Call it while a part of the editor is built, never while it prints: it writes
into `settings`.
"""
function get_settings_group!(settings::Settings, T::Type{<:SettingsGroup})
    group = get(settings.groups, T, nothing)
    group === nothing ? set_settings_group!(settings, T()) : group
end

"""
    set_settings_group!(settings, group) -> SettingsGroup

Put `group` into `settings` in place of the group of its type, and answer it.
"""
function set_settings_group!(settings::Settings, group::SettingsGroup)
    settings.groups[get_settings_group_type(group)] = group
    group
end

"""
    get_settings_groups(settings) -> Vector

The groups of `settings`, in the order of their names in a settings file.
"""
get_settings_groups(settings::Settings) =
    sort!(collect(values(settings.groups::Dict{Type,Any}));
          by = group -> get_settings_name(get_settings_group_type(group)))

"""
    is_settings_group(settings, document) -> Bool

Whether `document` is one of the groups of `settings`.
"""
is_settings_group(settings::Settings, document) =
    document isa SettingsGroup &&
        any(group -> group === document, values(settings.groups))

"""
    get_setting_cell(group, name) -> AbstractCell

The cell that holds the setting `name` of `group`. A part that reads the setting
where it acts holds this cell, so a change reaches it with no apply.
"""
get_setting_cell(group::SettingsGroup, name::Symbol) = getfield(group, name)
