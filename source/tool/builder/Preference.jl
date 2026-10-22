# Fragment of `BuilderModule` — what a build writes into the image, and
# what it leaves to the command line.
#
# A preference read at module scope is recorded as a dependency of the
# precompile cache, so a build at another value rebuilds. A generated source
# file that a module includes only when it exists is not noticed when it
# appears, and the stale image is reused with the old value silently inside it.
# That is why every build-time value travels this way and not as emitted code.
#
# A preference belongs to the package that READS it: `@load_preference` keys by
# the enclosing package's uuid. So a `Preference` names its reader, and a build
# function writing one has to know which package asks for it.

"""
    Preference(package, key, value)

One value the build compiles into the image, for `package` to read back with
`@load_preference(key)`.

Julia reads a preference only for a package that the project lists, so a build
makes `package` a dependency of the package that it writes when the build does
not name it.
"""
struct Preference
    package::String
    key::String
    value::Any
end

"""
    make_baked_preference(package, key, value) -> Preference

A value the binary carries and no flag can change. Use it when a wrong value at
run time would be a defect rather than a choice — which backend a
single-backend binary draws on, how much was compiled ahead of time.
"""
make_baked_preference(package::AbstractString, key::AbstractString, value) =
    Preference(String(package), String(key), value)

"""
    make_exposed_preferences(package, key, value; flag_key) -> Vector{Preference}

A value the binary carries as a **default**, over which a flag may be given.

Two preferences and not one: the value, and the companion key the program reads
to decide whether the flag exists at all. The companion key is the program's
own, which is why a caller names it — the builder knows what a preference is and
not what a program does with it.
"""
make_exposed_preferences(package::AbstractString, key::AbstractString, value;
                          flag_key::AbstractString) =
    [make_baked_preference(package, key, value), make_baked_preference(package, flag_key, true)]

"""
    is_performance_counters_requested() -> Bool

Whether the environment variable `PROJECTURED_PERFORMANCE_COUNTERS` asks a build
for the performance counters of the editor: `true` or `false`, and `false` when it
is not set or empty. Another value throws an `ArgumentError`, so a misspelt value
does not build a binary with no counters in silence.

Use it as the default of a keyword that a build passes on to
[`build_executable`](@ref), so a script that builds, or that runs from source,
takes the switch from its environment.

# Example

    withenv("PROJECTURED_PERFORMANCE_COUNTERS" => "true") do
        is_performance_counters_requested()     # true
    end
"""
function is_performance_counters_requested()
    value = get(ENV, "PROJECTURED_PERFORMANCE_COUNTERS", "")
    value in ("true", "false", "") ||
        throw(ArgumentError("PROJECTURED_PERFORMANCE_COUNTERS is true or false, not $(repr(value))"))
    value == "true"
end

# A caller may hand over a single preference or a vector of them; both flatten.
_preferences(x::Preference) = [x]
_preferences(x::AbstractVector) = reduce(vcat, (_preferences(e) for e in x); init = Preference[])

# The packages that read `preferences` and that `named` does not hold, once each,
# in the order of the preferences. The written package `app_module` reads its own
# preferences, so it is never one of them.
function _collect_preference_readers(preferences, named, app_module::AbstractString)
    readers = String[]
    for preference in _preferences(preferences)
        package = preference.package
        (package in named || package == app_module || package in readers) && continue
        push!(readers, package)
    end
    readers
end

"""
    write_preferences(preferences, project) -> String

Write every preference into `project`'s `LocalPreferences.toml`, and answer the
path.

Preferences are read from the **active** project, so this writes into the one
that gets compiled — the package the build wrote, not the package that holds the
code. Every build writes the whole file, with every key it names and no other: a
key or a package that only the last build named would be that build's answer,
and that answer would be compiled into this binary.
"""
function write_preferences(preferences, project::AbstractString)
    toml = joinpath(project, "LocalPreferences.toml")
    rm(toml; force = true)
    by_package = Dict{String,Vector{Pair{String,Any}}}()
    for preference in _preferences(preferences)
        push!(get!(by_package, preference.package, Pair{String,Any}[]),
              preference.key => preference.value)
    end
    for (package, pairs) in by_package
        set_preferences!(toml, package, pairs...; force = true)
    end
    toml
end
