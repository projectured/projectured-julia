# Fragment of `ProjectionAlgebraModule`.
#
# The declaration of a view type. A view type of a content type has the field
# `viewed`, one child field for each list of the content, a constructor that takes
# the content, and the methods that make it the view of its content type. The
# macro writes them, so a person writes only the state that is specific to the view
# type.

"""
    find_child_view_type(declared::Type) -> Type or nothing

The view type that a view keeps in a child field, for a field of its content that
is declared as `declared`; `nothing` when a field of that type gets no child
field. A kind of list that has a view type declares a method.
"""
function find_child_view_type end
find_child_view_type(::Type) = nothing
find_child_view_type(::Type{<:CellVector}) = CellVectorView

"""
    has_default_view_state(view) -> Bool

`true` when each field of the state of `view` has its default value, so a new view
of the same content is equal to it. [`@content_view`](@ref) declares a method for
the view type, from the defaults of the declaration. A view type with no
declaration answers `false`.
"""
function has_default_view_state end
has_default_view_state(view) = false

"""
    @content_view Content struct Name <: Supertype
        state::Type = default
    end

Declare `Name`, the view type of the content type `Content`. The declaration holds
only the state that is specific to the view type. The macro writes the rest:

- the field `viewed::Content`, which holds the content;
- one child field for each list of `Content`, with the name of the field of that
  list, which holds the view of the list ([`CellVectorView`](@ref));
- the constructor `Name(content)`;
- the method of [`make_content_view`](@ref) for `Content`, and the method that
  takes the views that a viewing step gives, when `Content` has one list;
- the method of [`has_default_view_state`](@ref), which compares each field of the
  state with its default.

`Content` is a type that `@document` declared before this declaration.

# Example

    @content_view JsonArray struct JsonArrayView <: JsonView
        collapsed::Bool = false
    end

    view = JsonArrayView(array)
    view.viewed === array            # true
    view.elements                    # the view of the list `array.elements`
    make_content_view(array)         # a new JsonArrayView
"""
macro content_view(content, declaration)
    esc(_make_content_view_declaration(__module__, __source__, content, declaration))
end

function _make_content_view_declaration(mod::Module, source, content, declaration)
    (declaration isa Expr && declaration.head === :struct) ||
        throw(ArgumentError("@content_view: write a struct declaration after the content type"))
    content_type = Core.eval(mod, content)
    content_type isa Type || throw(ArgumentError("@content_view: $content is no type"))
    header = declaration.args[2]
    name = (header isa Expr && header.head === :<:) ? header.args[1] : header
    name isa Symbol || throw(ArgumentError("@content_view: a view type takes no type parameter"))
    state_lines = declaration.args[3].args
    child_fields = _find_child_view_fields(content_type)
    state_fields = _find_declared_state_fields(state_lines)
    for (field, _) in state_fields
        (field === :viewed || any(child -> child[1] === field, child_fields)) && throw(ArgumentError(
            "@content_view: $name declares the field `$field`, which the declaration writes for $content"))
    end

    fields = Any[:(viewed::$content)]
    for (field, view_type) in child_fields
        push!(fields, :($field::$view_type))
    end
    append!(fields, state_lines)
    struct_expr = Expr(:struct, declaration.args[1], header, Expr(:block, fields...))
    result = Expr(:block, Expr(:macrocall, GlobalRef(DocumentModule, Symbol("@document")), source, struct_expr))

    make = Expr(:., ProjectionAlgebraModule, QuoteNode(:make_content_view))
    is_default = Expr(:., ProjectionAlgebraModule, QuoteNode(:has_default_view_state))
    # The view of a list follows the field of the content, so it shows the list
    # that the content holds now.
    make_list_view(field, view_type, given...) =
        :($view_type($(Cell)($(Computation)(() -> $(getproperty)(viewed, $(QuoteNode(field))))), $(given...)))
    if !isempty(child_fields)
        children = [make_list_view(field, view_type) for (field, view_type) in child_fields]
        push!(result.args, source, :($name(viewed::$content) = $name(viewed, $(children...))))
    end
    push!(result.args, source, :($make(viewed::$content) = $name(viewed)))
    if length(child_fields) == 1
        (field, view_type) = only(child_fields)
        push!(result.args, source,
              :($make(viewed::$content, children) = $name(viewed, $(make_list_view(field, view_type, :children)))))
    end
    checks = Any[default === nothing ? false : :($(isequal)($(getproperty)(view, $(QuoteNode(field))), $(default.value)))
                 for (field, default) in state_fields]
    condition = isempty(checks) ? true : foldl((a, b) -> :($a && $b), checks)
    push!(result.args, source, :($is_default(view::$name) = $condition), nothing)
    result
end

# The fields of the content type `content` that get a child field in a view, each
# with the name of the view type that the child field holds.
function _find_child_view_fields(content::Type)
    found = Tuple{Symbol,Symbol}[]
    for field in fieldnames(content)
        is_view_state_field(field) && continue
        declared = find_declared_field_type(content, field)
        declared === nothing && continue
        view_type = find_child_view_type(declared)
        view_type === nothing || push!(found, (field, nameof(view_type)))
    end
    found
end

# The fields that the lines of a declaration name, each with its default as
# `Some(expression)`, or with `nothing` when the field has no default.
function _find_declared_state_fields(lines)
    found = Tuple{Symbol,Union{Some,Nothing}}[]
    for line in lines
        if line isa Expr && line.head === :(=)
            push!(found, (_get_declared_field_name(line.args[1]), Some(line.args[2])))
        elseif line isa Symbol || (line isa Expr && line.head === :(::))
            push!(found, (_get_declared_field_name(line), nothing))
        end
    end
    found
end

_get_declared_field_name(field::Symbol) = field
_get_declared_field_name(field::Expr) = _get_declared_field_name(field.args[1])
