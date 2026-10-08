# Fragment of `PrimitiveModule` — a plain value copied into a document of a
# schema, and a document copied back into a plain value, field by field.
#
# A form edits a plain value through such a copy when the author wants a
# commit and a cancel: the author declares a `@document` schema whose fields have
# the names of the fields of the value, the form edits a document of that schema,
# and a commit copies the document back. A field is matched by its name.
#
# The declared type of a field of the schema comes from its native layout, the
# plain struct that `@document` emits beside the cell layout. A schema with no
# native layout declares no type that can be read, so its values are copied as
# they are.
#
# A value that is not converted is copied when it can change, so the document and
# the value share no object that an edit of one would change in the other.

"""
    convert_object_to_document(T, object) -> document

A document of the `@document` schema `T`. Each field of `T` takes the value of the
field of `object` that has the same name.

- A field of `T` that `object` does not have is an error, so a wrong name in a
  schema shows at once.
- A field of `object` that `T` does not have is not copied, so a schema can show
  a part of a value.
- A value whose declared type in `T` is a schema, and which is no document, is
  converted to that schema. A vector converts each element whose declared type
  is a schema.

# Example

    struct Server
        name::String
        capacity::Int
    end
    @document struct ServerForm
        name::String
        capacity::Int
    end
    form = convert_object_to_document(ServerForm, Server("gateway", 4))

See also [`convert_document_to_object`](@ref), the way back.
"""
function convert_object_to_document(T::Type, object)
    values = Any[]
    for name in _get_schema_field_names(T)
        hasfield(typeof(object), name) ||
            throw(ArgumentError("convert_object_to_document: $(typeof(object)) has no " *
                                "field $(name), which the schema $(T) declares"))
        push!(values, _convert_value_to_document(_get_declared_field_type(T, name),
                                                 getfield(object, name)))
    end
    T(values..., nothing)
end

"""
    convert_document_to_object(T, document; base = nothing) -> object

A plain value of the type `T`. Each field of `T` takes the value of the field of
`document` that has the same name, and the constructor of `T` that takes every
field makes the value.

- A field of `T` that `document` does not have takes its value from `base`, the
  value that the document was made from. With no `base`, that is an error.
- A document whose declared type in `T` is a plain struct is converted to it. A
  collection of elements becomes a vector, and each element converts by the
  element type that `T` declares.

# Example

    server = convert_document_to_object(Server, form)            # at a commit
    server = convert_document_to_object(Server, form; base = server)

See also [`convert_object_to_document`](@ref), the way there.
"""
function convert_document_to_object(T::Type, document; base = nothing)
    names = _get_schema_field_names(typeof(document))
    values = Any[]
    for name in fieldnames(T)
        if name in names
            push!(values, _convert_value_to_object(fieldtype(T, name),
                                                   getproperty(document, name),
                                                   base === nothing ? nothing : getfield(base, name)))
        else
            base === nothing &&
                throw(ArgumentError("convert_document_to_object: the document has no " *
                                    "field $(name) of $(T), and no base gives it"))
            push!(values, _copy_plain_value(getfield(base, name)))
        end
    end
    T(values...)
end

# The fields of a schema that hold its content, without the selection and the
# mouse target.
_get_schema_field_names(T) = [name for name in fieldnames(T) if !is_view_state_field(name)]

# The type that the schema declares for a field, read from its native layout.
function _get_declared_field_type(T, name::Symbol)
    native = get_document_native_type(T)
    native === nothing ? Any : fieldtype(native, name)
end

_is_document_schema(T) =
    T isa Type && T <: Document && !isabstracttype(Base.unwrap_unionall(T))

_is_plain_struct_type(T) =
    T isa DataType && isconcretetype(T) && isstructtype(T) && !(T <: Document) &&
    !(T <: AbstractString) && !(T <: Number)

_copy_plain_value(value) = ismutable(value) ? deepcopy(value) : value

_get_elements(collection::AbstractVector) = collect(collection)
_get_elements(collection) = Any[collection[index] for index in 1:length(collection)]

function _convert_value_to_document(declared, value)
    value isa Document && return value
    if value isa AbstractVector && declared isa Type && declared <: AbstractVector
        element = eltype(declared)
        _is_document_schema(element) || return _copy_plain_value(value)
        return map(item -> _convert_value_to_document(element, item), value)
    end
    _is_document_schema(declared) && return convert_object_to_document(declared, value)
    _copy_plain_value(value)
end

function _convert_value_to_object(declared, value, base)
    if value isa AbstractVector || (value isa Document && is_element_collection(value))
        element = declared isa Type && declared <: AbstractVector ? eltype(declared) : Any
        return map(item -> _convert_value_to_object(element, item, nothing),
                   _get_elements(value))
    end
    value isa Document || return _copy_plain_value(value)
    _is_plain_struct_type(declared) &&
        return convert_document_to_object(declared, value; base)
    if base !== nothing && _is_plain_struct_type(typeof(base))
        return convert_document_to_object(typeof(base), value; base)
    end
    value
end
