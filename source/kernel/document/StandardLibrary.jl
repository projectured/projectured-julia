# Fragment of `DocumentModule` — the standard libraries of Julia that the editor
# loads by name: their list, and the load of one by its package id.

"""
    LOADABLE_STANDARD_LIBRARIES

The standard libraries of Julia that the editor loads when it is asked for one by
name, each name with its package id: `Dates`, `Statistics`, `Printf` and `Random`.
The code of an assistant loads one with `using`, and a file loads one when it
names a value of it, such as `Dates.Date("2026-11-24")`. No other package loads
in either way.

See also [`load_standard_library!`](@ref).
"""
const LOADABLE_STANDARD_LIBRARIES = (
    Dates = Base.PkgId(Base.UUID("ade2ca70-3891-5945-98fb-dc099432e06a"), "Dates"),
    Statistics = Base.PkgId(Base.UUID("10745b16-79ce-11e8-11f9-7d13ad32a3b2"), "Statistics"),
    Printf = Base.PkgId(Base.UUID("de0858da-6303-5e67-8744-51eddeeeb8d7"), "Printf"),
    Random = Base.PkgId(Base.UUID("9a3f8284-a2c9-5f02-9a11-845980a1fd5c"), "Random"),
)

"""
    load_standard_library!(name) -> Union{Module, Nothing}

The module of the standard library `name`, a `Symbol` or a string, which the call
loads when the process holds it not yet. `nothing` when `name` is not on
[`LOADABLE_STANDARD_LIBRARIES`](@ref). The load goes by the package id, so it
does not depend on the load path of the process: a process whose load path has no
`@stdlib` loads the library too.
"""
function load_standard_library!(name::Union{Symbol,AbstractString})
    key = Symbol(name)
    haskey(LOADABLE_STANDARD_LIBRARIES, key) || return nothing
    Base.require(LOADABLE_STANDARD_LIBRARIES[key])
end
