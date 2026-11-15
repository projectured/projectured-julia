# Fragment of `PrecompileModule` — the two preferences of a package: how much it
# compiles ahead of time, and what a failure of that does.

"""
    PRECOMPILE_CALLS_VALUES

The values of the preference `precompile_calls` of a package, in the order of
how much they compile:

- `"none"`: nothing.
- `"recorded"`: the calls in the files of `precompile/` of the package. This is
  the default.
- `"live"`: the calls that the workload of the package makes, by a run of it.
"""
const PRECOMPILE_CALLS_VALUES = ("none", "recorded", "live")

"""
    PRECOMPILE_FAILURE_VALUES

The values of the preference `precompile_failure` of a package:

- `"error"`: the build of the package stops.
- `"warning"`: the build continues, and the package shows the failure when it
  loads. This is the default.
- `"silent"`: the build continues, and nothing shows the failure.
"""
const PRECOMPILE_FAILURE_VALUES = ("error", "warning", "silent")

"""
    get_precompile_calls(package::Module) -> String

The preference `precompile_calls` of `package`, one of
[`PRECOMPILE_CALLS_VALUES`](@ref). Read while the package precompiles, it makes
the image depend on the preference, so a change of it builds the image again.
"""
get_precompile_calls(package::Module) =
    _get_preference_value(package, "precompile_calls", "recorded", PRECOMPILE_CALLS_VALUES)

"""
    get_precompile_failure(package::Module) -> String

The preference `precompile_failure` of `package`, one of
[`PRECOMPILE_FAILURE_VALUES`](@ref). Read while the package precompiles, it makes
the image depend on the preference.
"""
get_precompile_failure(package::Module) =
    _get_preference_value(package, "precompile_failure", "warning", PRECOMPILE_FAILURE_VALUES)

function _get_preference_value(package::Module, key::String, default::String, values)
    value = load_preference(package, key, default)
    value isa String && value in values && return value
    error("The preference `", key, "` of ", nameof(package), " is ", repr(value),
          ", and it must be one of ", join(repr.(values), ", "), ".")
end
