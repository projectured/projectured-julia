# Fragment of `EditorModule` — the seams by which a backend type says what it is,
# and the choice of a backend when the caller names none.
#
# A backend package adds a method of each seam for its own type. So the loaded
# packages are the list of the backends, and no table names them. A backend
# with no method of `get_backend_output` is never chosen: a recorder that needs
# settings and a test double are always named by the caller.

"""
    get_backend_name(::Type{<:Backend}) -> Symbol

The short name of a backend type, as a command line names it: `:sdl`, `:web`,
`:console`. A backend package adds the method for its own type.
"""
function get_backend_name end

"""
    get_backend_output(::Type{<:Backend}) -> Symbol

What a backend type draws: `:windows` for a screen of windows, `:text` for a
block of text. A backend package adds the method for its own type.
[`make_default_backend`](@ref) chooses only among the types that have a method.
"""
function get_backend_output end

"""
    collect_backend_types() -> Vector{Type}

The loaded backend types that have a method of [`get_backend_output`](@ref),
read from its method table, in the order of the names of the types.
"""
function collect_backend_types()
    types = Type[]
    for method in methods(get_backend_output)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        argument = signature.parameters[2]
        # A method for `Type{T}` of one concrete `T`; a method for a set of
        # types names no backend that can be made.
        (argument isa DataType && argument.name === Type.body.name) || continue
        type = argument.parameters[1]
        (type isa DataType && isconcretetype(type) && type <: Backend) || continue
        push!(types, type)
    end
    sort!(types; by = string)
end

"""
    DEFAULT_BACKEND

The backend that a caller who names none gets in the scope of
`with(DEFAULT_BACKEND => backend) do … end`, or `nothing` outside such a scope.
A workload sets it, so that it runs the call of a user, who names no backend,
where no backend that draws windows is loaded.
"""
const DEFAULT_BACKEND = ScopedValue{Union{Nothing,Backend}}(nothing)

"""
    make_default_backend(output::Symbol = :windows) -> Backend

The backend of a caller that names none: the backend of [`DEFAULT_BACKEND`](@ref)
in its scope, else the one loaded backend type that draws `output`, made with no
arguments. With no such type, or with more than one, it raises an error that
names the loaded backends, because an order of preference would change the
backend of a program when one more package is loaded.
"""
function make_default_backend(output::Symbol = :windows)
    scoped = DEFAULT_BACKEND[]
    scoped === nothing || return scoped
    loaded = collect_backend_types()
    type = _choose_backend_type(loaded, output)
    type()
end

# The one type of `loaded` that draws `output`, or an error that names them.
function _choose_backend_type(loaded::Vector, output::Symbol)
    # Through `invokelatest`: each backend package adds a method, and a call that
    # inference resolves would be invalidated when such a package loads.
    candidates = Type[]
    for type in loaded
        Base.invokelatest(get_backend_output, type) === output && push!(candidates, type)
    end
    length(candidates) == 1 && return only(candidates)
    names = isempty(loaded) ? "none" :
        join(("$(nameof(type)) ($(Base.invokelatest(get_backend_output, type)))" for type in loaded), ", ")
    if isempty(candidates)
        error("No loaded backend draws $(output). Load a backend package that draws ",
              "$(output), or pass `backend`. The loaded backends: $(names).")
    end
    error("More than one loaded backend draws $(output): ",
          join((nameof(type) for type in candidates), " and "),
          ". Pass `backend` to choose one.")
end
