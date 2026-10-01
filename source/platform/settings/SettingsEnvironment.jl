# Fragment of `SettingsModule` — the environment variables that set a setting for
# one run.

"""
    get_setting_environment_names(T) -> NamedTuple

The environment variables that set settings of the group type `T` for one run, by
the name of each setting, as `(partial_render = "PROJECTURED_PARTIAL_RENDER",)`.
None by default; the slice that declares the group adds the method.
"""
get_setting_environment_names(::Type) = (;)

"""
    read_settings_environment!(settings, environment = ENV) -> Settings

Write into each group of `settings` the value of each environment variable that
[`get_setting_environment_names`](@ref) names for it and that `environment`
holds. This is the one place that reads these variables. A variable that is empty
is left out. A value that does not fit is left out with a warning. A `Bool`
takes `1`, `true`, `yes` or `on`, and `0`, `false`, `no` or `off`.

Call it while an editor is built, after the defaults and the file, so a variable
wins for one run.
"""
function read_settings_environment!(settings::Settings, environment = ENV)
    for group in values(settings.groups)
        T = get_settings_group_type(group)
        for (name, variable) in pairs(get_setting_environment_names(T))
            text = strip(get(environment, variable, ""))
            isempty(text) && continue
            description = find_setting_description(T, name)
            value = convert_setting_value(description,
                                          _parse_environment_value(description.type, text))
            if value === nothing
                @warn "The environment variable $variable can not set " *
                      "\"$(description.label)\" to $(repr(String(text)))."
                continue
            end
            setproperty!(group, name, value)
        end
    end
    settings
end

function _parse_environment_value(::Type{Bool}, text::AbstractString)
    word = lowercase(text)
    word in ("1", "true", "yes", "on") ? true :
    word in ("0", "false", "no", "off") ? false : text
end
_parse_environment_value(::Type, text::AbstractString) = text
