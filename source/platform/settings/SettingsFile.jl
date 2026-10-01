# Fragment of `SettingsModule` — the settings file: where it is, how it is read and
# written, and the operations of the buttons that save and load it.

"""
    get_configuration_folder() -> String

The folder of the configuration files of ProjecturEd: `projectured` in
`XDG_CONFIG_HOME`, by default `~/.config/projectured`.
"""
function get_configuration_folder()
    base = get(ENV, "XDG_CONFIG_HOME", "")
    joinpath(isempty(base) ? joinpath(homedir(), ".config") : base, "projectured")
end

"""
    get_settings_file() -> String

The settings file of the application: `settings.toml` in the configuration folder.
"""
get_settings_file() = joinpath(get_configuration_folder(), "settings.toml")

"""
    write_settings_file!(settings, path) -> nothing

Write `settings` to the TOML file `path`: one table for each group, named by
`get_settings_name`, and one key for each setting. The folder is made when it is
missing.
"""
function write_settings_file!(settings::Settings, path::AbstractString)
    tables = Dict{String,Any}()
    for group in get_settings_groups(settings)
        T = get_settings_group_type(group)
        tables[get_settings_name(T)] =
            Dict{String,Any}(String(description.name) =>
                                 _make_file_value(getproperty(group, description.name))
                             for description in get_setting_descriptions(T))
    end
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, tables; sorted = true)
    end
    nothing
end

_make_file_value(value::Symbol) = String(value)
_make_file_value(value) = value

"""
    read_settings_file!(settings, path) -> Settings

Write into the groups of `settings` the values of the TOML file `path`, while an
editor is built. A file that does not exist changes nothing. A key that is
missing keeps its value. A table or a key that is not known, and a value that
does not fit, write one warning each to the log, and none of them stops the read.
"""
function read_settings_file!(settings::Settings, path::AbstractString)
    for (group, name, value) in _read_settings_values(settings, path)
        setproperty!(group, name, value)
    end
    settings
end

# Each value of the file `path` that fits its setting, as `(group, name, value)`.
function _read_settings_values(settings::Settings, path::AbstractString)
    found = Tuple{Any,Symbol,Any}[]
    isfile(path) || return found
    tables = try
        TOML.parsefile(path)
    catch exception
        @warn "The settings file $path can not be read: $(sprint(showerror, exception))"
        return found
    end
    groups = Dict(get_settings_name(get_settings_group_type(group)) => group
                  for group in values(settings.groups))
    for (table, keys) in tables
        group = get(groups, table, nothing)
        if group === nothing || !(keys isa AbstractDict)
            @warn "The settings file $path has a table [$table] that no group has."
            continue
        end
        T = get_settings_group_type(group)
        for (key, raw) in keys
            description = find_setting_description(T, Symbol(key))
            value = description === nothing ? nothing : convert_setting_value(description, raw)
            if value === nothing
                @warn "The settings file $path can not set $table.$key to $(repr(raw))."
                continue
            end
            push!(found, (group, description.name, value))
        end
    end
    found
end

"""
    SaveSettingsOperation(settings, path)

Write `settings` to the file `path` ([`write_settings_file!`](@ref)). It changes
no document, so its way back is to do nothing, and a history keeps no step for it.
"""
struct SaveSettingsOperation <: Operation
    settings::Settings
    path::String
end

evaluate_operation(editor, operation::SaveSettingsOperation) =
    write_settings_file!(operation.settings, operation.path)

make_inverse_operation(document, ::SaveSettingsOperation) = DoNothingOperation()
describe_operation(operation::SaveSettingsOperation) = "save the settings to " * operation.path
operation_travels_unchanged(::SaveSettingsOperation) = true

"""
    LoadSettingsOperation(settings, path)

Read the file `path` into `settings`: an `ApplySettingOperation` for each value
that differs, so each change reaches the place where it acts. Its way back writes
every setting back to the value that it had before, and applies it.
"""
struct LoadSettingsOperation <: Operation
    settings::Settings
    path::String
end

function evaluate_operation(editor, operation::LoadSettingsOperation)
    for (group, name, value) in _read_settings_values(operation.settings, operation.path)
        getproperty(group, name) == value && continue
        evaluate_operation(editor, ApplySettingOperation(group, name, value))
    end
    nothing
end

make_inverse_operation(document, operation::LoadSettingsOperation) =
    CompoundOperation(Any[ApplySettingOperation(group, description.name,
                                                getproperty(group, description.name))
                          for group in get_settings_groups(operation.settings)
                          for description in
                              get_setting_descriptions(get_settings_group_type(group))])

describe_operation(operation::LoadSettingsOperation) =
    "load the settings from " * operation.path
operation_travels_unchanged(::LoadSettingsOperation) = true
