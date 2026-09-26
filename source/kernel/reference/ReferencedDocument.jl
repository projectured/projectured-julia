# Fragment of `ReferenceModule` — a document together with the reference that
# reached it, and the address of a document: a start and a reference.

"""
    ReferencedDocument{T}

A document together with the reference that reached it: the node, of type `T`, as
it was when it was found, and the complete reference to it from the root it was
found from. `T` is the type of whatever the reference reaches: a document, a
collection, or any other value.

It acts like the document it references. Reading or writing a property, indexing,
iteration, `length`, `isempty`, `keys`, `haskey`, `get` and `values` go to the
document. A read that answers a document or a
collection answers it as a `ReferencedDocument` too, with the reference extended by
the field or the index; a read that answers any other value — a string, a number, a
`Bool`, `nothing` — answers that value. So a chain of reads looks like code on the
document itself, and every value in it but the last holds the reference to its place.

Read its two parts with [`get_document`](@ref) and [`get_reference`](@ref); every
property name goes to the document. A referenced document is not an instance of the
type of its document, so code that checks a type asks `get_document(x)`.

Use it to keep a document and where it is together: to read a part of it, to write
to it, or to hand it to a function that needs the place, such as one that moves or
replaces what the reference names.

# Example

    tree = ReferencedDocument(root, EmptyReference())
    first_child = tree.children[1]     # a referenced document at `.children[1]`
    first_child.name                   # the name, a plain string
"""
struct ReferencedDocument{T}
    document::T
    reference::Reference
end

"""
    get_document(x) -> T

The document that `x` references, as it was when it was found. Given any value
that is not a referenced document, it answers that value, so code that unwraps
works on a referenced document and on a plain one alike.

Use it where code needs the document itself: to check its type, or to hand it to a
function that has no method for a referenced document.
"""
get_document(x::ReferencedDocument) = getfield(x, :document)
get_document(x) = x

"""
    get_reference(x::ReferencedDocument) -> Reference

The complete reference to the document of `x`, from the root it was found from.

Use it where code needs the place and not the document, such as a reference to
extend, to compare, or to evaluate again.
"""
get_reference(x::ReferencedDocument) = getfield(x, :reference)

# A value that a read answers as a referenced document: a document or a collection.
# Any other value is a leaf and is answered as it is.
_is_referenced_value(value) =
    value isa Document || value isa AbstractVector || value isa AbstractDict || value isa Tuple

# What a write stores: the document of a referenced document, so the tree never
# holds a referenced document.
_get_stored_value(value) = value isa ReferencedDocument ? get_document(value) : value

# `value` as a referenced document one `step` below the document of `x`. The step
# records the type of the node it stands on, and the reference ends on the type of
# `value`, as `annotate_reference_types` records them, so a function that takes
# only a fully typed reference takes this one.
function _make_stepped_value(x::ReferencedDocument, step, value)
    _is_referenced_value(value) || return value
    typed = ConcreteReference(get_reference_node_type(get_document(x)), step,
                              EmptyReference(get_reference_node_type(value)))
    ReferencedDocument(value, concat_references(get_reference(x), typed))
end

# `value` as a referenced document when the document of `x` holds it at exactly one
# place, found by its identity. A value that the document does not hold, such as a
# new collection that a function computed from it, and a value that it holds at
# more than one place, such as a document with no fields, is answered as it is: no
# reference is better than a wrong one.
function _find_referenced_value(x::ReferencedDocument, value)
    _is_referenced_value(value) || return value
    document = get_document(x)
    found = search_references(document, node -> node === value)
    length(found) == 1 || return value
    ReferencedDocument(value, concat_references(get_reference(x),
                                                annotate_reference_types(document, only(found))))
end

function Base.getproperty(x::ReferencedDocument, name::Symbol)
    document = get_document(x)
    value = getproperty(document, name)
    # A property that is not a field has no step that a reference can record, and
    # a field of a dictionary is not one of its entries, so their values are
    # answered as they are.
    (!(document isa AbstractDict) && hasfield(typeof(document), name)) || return value
    _make_stepped_value(x, FieldReferenceStep(String(name)), value)
end

Base.setproperty!(x::ReferencedDocument, name::Symbol, value) =
    setproperty!(get_document(x), name, _get_stored_value(value))

Base.propertynames(x::ReferencedDocument, private::Bool = false) =
    propertynames(get_document(x), private)

Base.length(x::ReferencedDocument) = length(get_document(x))
Base.isempty(x::ReferencedDocument) = isempty(get_document(x))
Base.firstindex(x::ReferencedDocument) = firstindex(get_document(x))
Base.lastindex(x::ReferencedDocument) = lastindex(get_document(x))
Base.eachindex(x::ReferencedDocument) = eachindex(get_document(x))
Base.keys(x::ReferencedDocument) = keys(get_document(x))
Base.haskey(x::ReferencedDocument, key) = haskey(get_document(x), key)

Base.setindex!(x::ReferencedDocument, value, key) =
    setindex!(get_document(x), _get_stored_value(value), key)

Base.push!(x::ReferencedDocument, values...) =
    (push!(get_document(x), map(_get_stored_value, values)...); x)
Base.insert!(x::ReferencedDocument, index::Integer, value) =
    (insert!(get_document(x), index, _get_stored_value(value)); x)
Base.deleteat!(x::ReferencedDocument, index) = (deleteat!(get_document(x), index); x)

# The step from a collection to the value at `key`: the entry of a dictionary, for
# a key that a field step can name, and an element, for a position. Any other key
# answers `nothing`, and the value is then found in the document by its identity.
_make_key_step(document, key) =
    document isa AbstractDict ?
        (key isa Union{AbstractString, Symbol} ? FieldReferenceStep(String(key)) : nothing) :
        (key isa Integer ? ElementReferenceStep(Int(key)) : nothing)

function Base.getindex(x::ReferencedDocument, key)
    value = get_document(x)[key]
    step = _make_key_step(get_document(x), key)
    step === nothing ? _find_referenced_value(x, value) : _make_stepped_value(x, step, value)
end

# What the document's own `get` answers for a missing key, apart from every value it
# can hold.
struct _MissingKey end

Base.get(x::ReferencedDocument, key, default) =
    get(get_document(x), key, _MissingKey()) isa _MissingKey ? default : x[key]

function Base.values(x::ReferencedDocument)
    document = get_document(x)
    document isa AbstractDict && return [x[key] for key in keys(document)]
    document isa AbstractVector && return collect(x)
    [_find_referenced_value(x, value) for value in values(document)]
end

# The iteration state: the position of the next value, and the state of the
# document's own iteration.
struct _ReferencedIterationState{S}
    position::Int
    inner::S
end

function Base.iterate(x::ReferencedDocument)
    next = iterate(get_document(x))
    next === nothing && return nothing
    _make_referenced_step(x, next, 1)
end

function Base.iterate(x::ReferencedDocument, state::_ReferencedIterationState)
    next = iterate(get_document(x), state.inner)
    next === nothing && return nothing
    _make_referenced_step(x, next, state.position)
end

function _make_referenced_step(x::ReferencedDocument, (value, inner), position::Int)
    (_make_iterated_value(x, value, position), _ReferencedIterationState(position + 1, inner))
end

# The value that iteration answers at `position`. A member of a dictionary is its
# key and its value read by that key. An element of a sequence is at its position.
# A value of any other document, such as a `(key, value)` member of a map, is found
# in the document by its identity, and so is each part of such a member.
function _make_iterated_value(x::ReferencedDocument, value, position::Int)
    document = get_document(x)
    document isa AbstractDict && return value isa Pair ? first(value) => x[first(value)] : value
    _is_referenced_value(value) || return value
    applicable(getindex, document, position) && document[position] === value &&
        return _make_stepped_value(x, ElementReferenceStep(position), value)
    value isa Tuple && return map(part -> _find_referenced_value(x, part), value)
    _find_referenced_value(x, value)
end

# The name of the type without the cell parameters that a document type carries.
_get_short_type_name(T) = T isa DataType ? nameof(T) : T

function Base.show(io::IO, x::ReferencedDocument{T}) where {T}
    print(io, "ReferencedDocument{", _get_short_type_name(T), "} at ",
          strip_reference_types(get_reference(x)), ": ")
    show(io, get_document(x))
end

Base.convert(::Type{T}, x::ReferencedDocument) where {T <: Document} = convert(T, get_document(x))
Base.convert(::Type{T}, x::ReferencedDocument) where {T <: Reference} = convert(T, get_reference(x))

search_documents(x::ReferencedDocument, predicate; keywords...) =
    search_documents(get_document(x), predicate; keywords...)
search_documents(x::ReferencedDocument, query::Union{AbstractString, Regex}; keywords...) =
    search_documents(get_document(x), query; keywords...)
get_wrapped_document(x::ReferencedDocument) = get_wrapped_document(get_document(x))

"""
    DocumentLocator(start, reference)

The address of a document: where a reference is read from, and the reference. It
is not resolved: [`find_referenced_document`](@ref) reads it when the document is
needed, so it still finds the document after the tree around it changed, as long
as the reference reaches a node.

`start` is usually the editor, whose document is read when the locator is
resolved, so the locator stays right when the editor's document is replaced. It
can be any document a reference is read from, such as the root that an operation
carries.

Use it to keep where a document is, and to find the document there again later.

# Example

    locator = DocumentLocator(editor, get_reference(people_tab))
    people_tab = find_referenced_document(locator)
"""
struct DocumentLocator{S}
    start::S
    reference::Reference
end

# What `try_evaluate_reference` answers when the reference reaches no node, apart
# from every value a node can hold.
struct _NotReached end

"""
    find_referenced_document(locator::DocumentLocator) -> ReferencedDocument or nothing

The document at the address `locator` names, read from its start now, with the
reference that reached it; `nothing` when the reference no longer reaches a node.

Use it to find a document again after the tree changed, or to bring a
`ReferencedDocument`, which holds the document as it was, up to date:
`find_referenced_document(DocumentLocator(editor.document, get_reference(x)))`.
"""
function find_referenced_document(locator::DocumentLocator)
    document = try_evaluate_reference(locator.start, locator.reference, _NotReached())
    document isa _NotReached && return nothing
    ReferencedDocument(document, annotate_reference_types(locator.start, locator.reference))
end

# A node that a parent is looked past: a collection, which holds the elements of
# the document around it.
_is_collection(node) = is_element_collection(node) || node isa AbstractVector ||
                       node isa AbstractDict || node isa Tuple

"""
    get_parent(root, x) -> ReferencedDocument or nothing

The document that holds `x`, read from `root` now: one step up the reference of
`x`, and past each collection on the way, so the parent of a tab is its group and
not the vector of its tabs. `x` is a `ReferencedDocument` or a `Reference` from
`root`. `root` is the document the reference starts at, or the editor, whose
document is read at the call. `nothing` when `x` is the root, or when the reference
no longer reaches a node.

Use it to reach the group that holds a tab, the object that holds a field, or the
document around any part, for example to open a new tab in the group of a tab.

# Example

    people_group_1 = get_parent(editor, find_pane(editor, "people.json"))
"""
function get_parent(root, x::Union{Reference, ReferencedDocument})
    steps = get_reference_steps(strip_reference_types(convert(Reference, x)))
    while !isempty(steps)
        pop!(steps)
        reference = extend_reference(EmptyReference(), steps...)
        node = try_evaluate_reference(root, reference, _NotReached())
        node isa _NotReached && return nothing
        (isempty(steps) || !_is_collection(node)) &&
            return ReferencedDocument(node, annotate_reference_types(root, reference))
    end
    nothing
end

# The most layers `get_edited_document` passes through, so a cycle of layers ends.
const _MAX_EDITED_LAYERS = 16

"""
    get_edited_document(x) -> ReferencedDocument, or a document

The data that a tab or an open file shows: the document that a person edits in
`x`. It follows each layer that holds such a document, through the field
`get_edited_field` names, down to a document that is itself what a person edits:
from a tab to what it shows, from a file to the document read from it, from a
history to the document it keeps.

Given a `ReferencedDocument`, it answers a `ReferencedDocument` whose reference goes
through every layer it passed; given a document, it answers the document. A layer
whose field holds a leaf, such as a `String`, answers that value.

Use it to read or change the data that a tab or an open file shows, in one call,
without knowing which layers hold it.

# Example

    data = get_edited_document(tab)      # the document the tab shows, through its layers
"""
function get_edited_document(x::ReferencedDocument)
    for _ in 1:_MAX_EDITED_LAYERS
        field = get_edited_field(get_document(x))
        field === nothing && return x
        inner = getproperty(x, field)
        inner isa ReferencedDocument || return inner
        x = inner
    end
    x
end

function get_edited_document(document)
    for _ in 1:_MAX_EDITED_LAYERS
        field = get_edited_field(document)
        field === nothing && return document
        document = getproperty(document, field)
    end
    document
end
