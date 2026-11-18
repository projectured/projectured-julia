# Fragment of `ProjectionAlgebraModule`.
#
# The declaration of a view type. A view type of a content type has the field
# `viewed`, one child field for each list of the content and for each field of the
# content that takes any document, a constructor that takes the content, and the
# methods that make it the view of its content type. The macro writes them, so a
# person writes only the state that is specific to the view type.

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
    is_child_view_field(content::Type, field::Symbol) -> Bool

Whether a view of the content type `content` gets a child field for the field
`field` of the content. The default is `true`. A content type declares `false` for
a field that no view of it shows, such as a list of the steps of an undo buffer.
`@content_view` reads it when it expands, so the method stands before the
declaration of the view type.
"""
function is_child_view_field end
is_child_view_field(::Type, ::Symbol) = true

# A field of a content type that takes any document: it is declared as `Document`,
# or as the union of `Document` and `Nothing`.
_is_document_slot_type(declared::Type) = declared === Document || declared === Union{Document, Nothing}

"""
    make_slot_view_computation(read) -> Function

The computation of a child field of a view that follows a place that takes any
document: `read()` gives what the place holds now. The computation gives the view
of that document, or `nothing` when the place holds no document or a document that
has no view type. It gives the same view while the place holds the same document.

`@content_view` uses it for each field of the content that takes any document. A
view that is written by hand uses it for a place that it reads through a function.

# Example

    content = Cell(Computation(make_slot_view_computation(() -> get_file_content(file))))
"""
function make_slot_view_computation(read)
    shown = nothing
    view = nothing
    function ()
        document = read()
        if document !== shown
            view = make_content_view(document)
            shown = document
        end
        view
    end
end

# The computation of the child field of a view for the field `field` of `content`,
# a field that takes any document.
_make_slot_view_computation(content, field::Symbol) =
    make_slot_view_computation(() -> getproperty(content, field))

"""
    @content_view Content struct Name <: Supertype
        state::Type = default
    end

Declare `Name`, the view type of the content type `Content`. The declaration holds
only the state that is specific to the view type. The macro writes the rest:

- the field `viewed::Content`, which holds the content;
- one child field for each list of `Content`, with the name of the field of that
  list, which holds the view of the list ([`CellVectorView`](@ref)). A field that
  `Content` declares as no field of a view gets none
  ([`is_child_view_field`](@ref));
- one child field for each field of `Content` that is declared as `Document`, or as
  the union of `Document` and `Nothing`, with the name of that field. It holds the
  view of the document that the field holds now, or `nothing` when that document
  has no view type. While the field holds the same document, the child field gives
  the same view;
- the constructor `Name(content)`;
- the method of [`make_content_view`](@ref) for `Content`, and the method that
  takes the views that a viewing step gives, when `Content` has one list. That
  method puts each given view at the index of its content in the list.

`Content` is a type that `@document` declared before this declaration.

# Example

    @content_view JsonArray struct JsonArrayView <: JsonView
        collapsed::Bool = false
    end

    view = JsonArrayView(array)
    view.viewed === array            # true
    view.elements                    # the view of the list `array.elements`
    make_content_view(array)         # a new JsonArrayView

    @content_view JsonObjectEntry struct JsonObjectEntryView <: JsonView end

    entry_view = JsonObjectEntryView(entry)
    entry_view.value                 # the view of the document `entry.value`
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
    for field in _find_declared_field_names(state_lines)
        (field === :viewed || any(child -> child.name === field, child_fields)) && throw(ArgumentError(
            "@content_view: $name declares the field `$field`, which the declaration writes for $content"))
    end

    fields = Any[:(viewed::$content)]
    for child in child_fields
        push!(fields, child.list_view === nothing ? :($(child.name)::Union{ContentView, Nothing}) :
                                                    :($(child.name)::$(child.list_view)))
    end
    append!(fields, state_lines)
    struct_expr = Expr(:struct, declaration.args[1], header, Expr(:block, fields...))
    result = Expr(:block, Expr(:macrocall, GlobalRef(DocumentModule, Symbol("@document")), source, struct_expr))

    make = Expr(:., ProjectionAlgebraModule, QuoteNode(:make_content_view))
    # The view of a list follows the field of the content, so it shows the list
    # that the content holds now.
    make_list_view(child, given...) =
        :($(child.list_view)($(Cell)($(Computation)(() -> $(getproperty)(viewed, $(QuoteNode(child.name))))),
                             $(given...)))
    # The view in the child field of a slot follows the document that the slot holds.
    make_slot_view(child) =
        :($(Cell)($(Computation)($(_make_slot_view_computation)(viewed, $(QuoteNode(child.name))))))
    make_child(child) = child.list_view === nothing ? make_slot_view(child) : make_list_view(child)
    if !isempty(child_fields)
        push!(result.args, source, :($name(viewed::$content) = $name(viewed, $(map(make_child, child_fields)...))))
    end
    push!(result.args, source, :($make(viewed::$content) = $name(viewed)))
    lists = filter(child -> child.list_view !== nothing, child_fields)
    if length(lists) == 1
        list = only(lists)
        given = :($(_make_given_views)(() -> $(getproperty)(viewed, $(QuoteNode(list.name))), children))
        children = [child === list ? make_list_view(child, given) : make_child(child) for child in child_fields]
        push!(result.args, source, :($make(viewed::$content, children) = $name(viewed, $(children...))))
    end
    push!(result.args, nothing)
    result
end

# The views that a viewing step gave for the children of a printed node, as a list
# with one place for each element of the list that `read_list` answers. The place of
# an element holds the view of that element, or `nothing` when the step gave none.
# A print can make a child with no step of its own, such as the leaf of the key of
# an entry, so each view is found by its content, and not by its place in `views`.
function _make_given_views(read_list, views)
    CellVector(Computation(function ()
        by_content = IdDict{Any,Any}()
        for view in views
            view === nothing || (by_content[getproperty(view, :viewed)] = view)
        end
        Any[get(by_content, element, nothing) for element in read_list()]
    end))
end

# The fields of the content type `content` that get a child field in a view, in the
# order of the fields of the content. `list_view` is the name of the view type of a
# list, or `nothing` for a field that takes any document.
function _find_child_view_fields(content::Type)
    found = @NamedTuple{name::Symbol, list_view::Union{Symbol, Nothing}}[]
    for field in fieldnames(content)
        (is_view_state_field(field) || !is_child_view_field(content, field)) && continue
        declared = find_declared_field_type(content, field)
        declared === nothing && continue
        view_type = find_child_view_type(declared)
        if view_type !== nothing
            push!(found, (name = field, list_view = nameof(view_type)))
        elseif _is_document_slot_type(declared)
            push!(found, (name = field, list_view = nothing))
        end
    end
    found
end

# The names of the fields that the lines of a declaration declare.
function _find_declared_field_names(lines)
    found = Symbol[]
    for line in lines
        if line isa Expr && line.head === :(=)
            push!(found, _get_declared_field_name(line.args[1]))
        elseif line isa Symbol || (line isa Expr && line.head === :(::))
            push!(found, _get_declared_field_name(line))
        end
    end
    found
end

_get_declared_field_name(field::Symbol) = field
_get_declared_field_name(field::Expr) = _get_declared_field_name(field.args[1])
