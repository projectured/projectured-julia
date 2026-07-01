"""
    XmlModule

The XML document domain provides reactive representations of XML data structures.
Every XML node is a Document with reactive Cell fields. Attributes are first-class
documents so the selection mechanism can descend into attribute values as well as
into element children and text content.

The domain includes:
- **Node types**: `XmlText`, `XmlElement`, `XmlInsertion`
- **Attribute type**: `XmlAttribute` (first-class document for attribute values)
- **Base type**: `XmlDocument` abstract type for all XML documents

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Elements: `.children[i]` for the i-th child node, `.attrs[i].value{k}` for a
  cursor in the i-th attribute's value
- Text: `.content{k}` — cursor at boundary k of the text content
- Attributes: `.value{k}` — cursor at boundary k of the attribute value
"""
module XmlModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement, xmlattr, setattr!, deleteattr!, setfn!,
       IXmlInsertion, IXmlText, IXmlAttribute, IXmlElement

"""
    XmlDocument

Abstract base type for all XML document types. Every concrete XML type
subtypes `XmlDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type XmlDocument <: Document end

# ── Insertion cursor ────────────────────────────────────────────────

"""
    XmlInsertion

Represents an insertion cursor position in an XML document. Used by the
editor to indicate where new content should be inserted.

# Fields

- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)
"""
@document struct XmlInsertion <: XmlDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Attribute ─────────────────────────────────────────────────────────────

"""
    XmlAttribute

Represents an XML attribute as a first-class document. This allows the
selection mechanism to descend into attribute values. Supports indexing
and assignment via `[]` and `[]=`.

# Fields

- `name::String` — the attribute name
- `value::String` — the attribute value (stored in a Cell)
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

The macro's Rule Y generates the `XmlAttribute(name, value)` constructor; its
auto-wrapping inner constructor turns a plain string into a primitive cell and a
`Function` into a computed thunk, so it covers both the value and reactive forms.
"""
@document struct XmlAttribute <: XmlDocument
    name::String
    value::String
    selection::Reference = nothing
end

"""
    xmlattr(name::AbstractString, value::AbstractString)

Convenience constructor for creating an `XmlAttribute`. Creates an attribute
with a primitive cell holding the given string value.
"""
xmlattr(name::AbstractString, value::AbstractString) = XmlAttribute(name, value)

Base.getindex(a::XmlAttribute) = a.value::String
Base.setindex!(a::XmlAttribute, v::AbstractString) = (a.value = String(v))
setfn!(a::XmlAttribute, f::Function) = (setfn!(getfield(a, :value), f); a)
setval!(a::XmlAttribute, v::AbstractString) = (setval!(getfield(a, :value), String(v)); a)

# ── Text node ─────────────────────────────────────────────────────────────

"""
    XmlText

Represents a text node in an XML document. Selection semantics: `.content{k}`
is the cursor at boundary k of the text content (0-based). Supports indexing and
assignment via `[]` and `[]=`.

# Fields

- `content::String` — the text content (stored in a Cell)
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

The macro's Rule Y generates the `XmlText(content)` constructor; its auto-wrapping
inner constructor turns a plain string into a primitive cell and a `Function` into
a computed thunk, so it covers both the value and reactive forms.
"""
@document struct XmlText <: XmlDocument
    content::String
    selection::Reference = nothing
end

Base.getindex(t::XmlText) = t.content::String
Base.setindex!(t::XmlText, v::AbstractString) = (t.content = String(v))
setfn!(t::XmlText, f::Function) = (setfn!(getfield(t, :content), f); t)
setval!(t::XmlText, v::AbstractString) = (setval!(getfield(t, :content), String(v)); t)

# ── Element ───────────────────────────────────────────────────────────────

"""
    XmlElement

Represents an XML element with a tag, attributes, and child nodes. Selection
semantics: `.children[i]` for the i-th child node, `.attrs[i].value{k}` for a
cursor in the i-th attribute's value. Supports array-like operations on children
and dictionary-like operations on attributes.

# Fields

- `tag::String` — the element tag name
- `attrs::CellVector` — holds `XmlAttribute` objects
- `children::CellVector` — holds child `XmlDocument` nodes
- `collapsed::Bool` — whether the element is collapsed in the UI (stored in a Cell)
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructors

The macro's Rule Y generates the empty `XmlElement(tag)` form. The remaining
constructors disambiguate an attribute vector from a child vector by element type
— something the macro cannot do, since `attrs` and `children` are both
`CellVector` fields:

- `XmlElement(tag, attrs::Vector{XmlAttribute})` — element with attributes
- `XmlElement(tag, children::Vector{<:XmlDocument})` — element with children
- `XmlElement(tag, attrs, children)` — element with both attributes and children
"""
@document struct XmlElement <: XmlDocument
    tag::String
    attrs::CellVector = CellVector()
    children::CellVector = CellVector()  # holds XmlDocument children
    collapsed::Bool = false
    selection::Reference = nothing
end

XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute}) =
    XmlElement(tag, attrs, XmlDocument[])

XmlElement(tag::AbstractString, children::Vector{<:XmlDocument}) =
    XmlElement(tag, XmlAttribute[], children)

# The 3-arg CellVector call lands on the macro's generated positional ctor, which
# fills the `collapsed`/`selection` defaults.
XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute}, children::Vector{<:XmlDocument}) =
    XmlElement(tag, CellVector(attrs), CellVector(children))

# ── Attribute access ────────────────────────────────────────────────────────────

function Base.getindex(e::XmlElement, name::AbstractString)
    for a in e.attrs
        a.name == name && return a
    end
    error("XmlElement <$(e.tag)> has no attribute \"$name\"")
end

Base.haskey(e::XmlElement, name::AbstractString) = any(a -> a.name == name, e.attrs)

"""
    setattr!(e::XmlElement, name::AbstractString, value::AbstractString)

Set or update an attribute on an XML element. If the attribute already exists,
its value is updated. If it doesn't exist, a new attribute is added.

Returns the modified element for chaining.
"""
function setattr!(e::XmlElement, name::AbstractString, value::AbstractString)
    for a in e.attrs
        if a.name == name
            a.value = String(value)
            return e
        end
    end
    push!(e.attrs, Cell(XmlAttribute(name, value)))
    return e
end

"""
    deleteattr!(e::XmlElement, name::AbstractString)

Delete an attribute from an XML element. If the attribute doesn't exist,
the element is unchanged.

Returns the modified element for chaining.
"""
function deleteattr!(e::XmlElement, name::AbstractString)
    for i in length(e.attrs):-1:1
        e.attrs[i].name == name && deleteat!(e.attrs, i)
    end
    return e
end

# ── String-replace operation ────────────────────────────────────────────
#
# Text-replace edits for the XML domain are handled generically by `splice_value!`
# (see OperationApiModule): the type-in target fields — `XmlText.content`,
# `XmlAttribute.value`/`name`, and `XmlElement.tag` — are all plain strings, so
# the string representation covers them. (The opening and closing tags both
# render from the single `tag` field, so editing it updates both reactively.)
# No per-type method is needed.

end # module
