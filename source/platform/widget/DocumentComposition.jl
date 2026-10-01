# Fragment of `WidgetModule` — the seams by which a package that owns a type of
# document joins the packages that show documents, with no dependency on them.
#
# A package adds a method of a seam for its own type. The natural renderer and
# the display of a value read the seams when they are loaded, and a package
# that adds a method depends on neither of them.

"""
    make_value_document(value) -> Document

The document that shows `value`, such as a `DataFrameView` for a data frame.
A package that owns a type of document adds the method for the type of the
values that it shows. A caller asks `hasmethod` first; a value with no method
is shown in another way, such as its reflected tree.
"""
function make_value_document end

"""
    make_graphics_projection(::Type{T}; measure::TextMeasure, appearance::Appearance) -> Projection

The projection that draws a document of type `T` as graphics, measures its text
with `measure`, and takes its scaled themes from `appearance`, the `Appearance`
of the editor. A package that owns a type of document adds the method for
that type. The natural renderer adds a row for each type that has a method, so
a document of that type draws inside any document that the renderer draws.
"""
function make_graphics_projection end

"""
    collect_graphics_projection_types() -> Vector{Type}

The types that have a method of [`make_graphics_projection`](@ref), read from
its method table. For a method of a set of types, `Type{<:T}`, the type is `T`.
A type comes before each of its supertypes, so a table that takes the first
type that matches takes the most specific one.
"""
function collect_graphics_projection_types()
    types = Type[]
    for method in methods(make_graphics_projection)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        # A method for `Type{<:T}` keeps its own `where` inside the tuple.
        argument = Base.unwrap_unionall(signature.parameters[2])
        (argument isa DataType && argument.name === Type.body.name) || continue
        type = argument.parameters[1]
        type isa TypeVar && (type = type.ub)
        type isa Type && type !== Any && push!(types, type)
    end
    sort!(unique!(types); by = type -> (-_count_supertypes(type), string(type)))
end

# How far `type` is below `Any`.
function _count_supertypes(type::Type)
    count = 0
    while type isa DataType && type !== Any
        type = supertype(type)
        count += 1
    end
    count
end

"""
    refresh_document!(document) -> nothing

Read again the value that `document` shows, after the value changed in place
outside the editor. A package that owns a type of document that shows a value,
such as a data frame, adds the method. It runs on the task of the editor.
"""
function refresh_document! end
