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

Selection semantics:
- Elements: `.attrs[i].value[k]` for attribute values, `.cell[i]` for child nodes
- Text: `.cell[k]` — character offset in text content
- Attributes: `.cell[k]` — character offset in attribute value
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

- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct XmlInsertion <: XmlDocument
    value::Any
    selection::Reference
end

XmlInsertion() = XmlInsertion(Cell(nothing), Cell(nothing))

# ── Attribute ─────────────────────────────────────────────────────────────

"""
    XmlAttribute

Represents an XML attribute as a first-class document. This allows the
selection mechanism to descend into attribute values. Supports indexing
and assignment via `[]` and `[]=`.

# Fields

- `name::String` — the attribute name
- `cell::Cell` — holds the attribute value as `String`
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `XmlAttribute(name::AbstractString, value::AbstractString)` — primitive cell with value
- `XmlAttribute(name::AbstractString, f::Function)` — computed cell with thunk
"""
@document struct XmlAttribute <: XmlDocument
    name::String
    cell::String
    selection::Reference
end

XmlAttribute(name::AbstractString, value::AbstractString) =
    XmlAttribute(String(name), Cell(String(value)), Cell(nothing))
XmlAttribute(name::AbstractString, f::Function) =
    XmlAttribute(String(name), Cell(f), Cell(nothing))

"""
    xmlattr(name::AbstractString, value::AbstractString)

Convenience constructor for creating an `XmlAttribute`. Creates an attribute
with a primitive cell holding the given string value.
"""
xmlattr(name::AbstractString, value::AbstractString) = XmlAttribute(String(name), Cell(String(value)), Cell(nothing))

Base.getindex(a::XmlAttribute) = a.cell::String
Base.setindex!(a::XmlAttribute, v::AbstractString) = (a.cell = String(v))
setfn!(a::XmlAttribute, f::Function) = (setfn!(getfield(a, :cell), f); a)
setval!(a::XmlAttribute, v::AbstractString) = (setval!(getfield(a, :cell), String(v)); a)

# ── Text node ─────────────────────────────────────────────────────────────

"""
    XmlText

Represents a text node in an XML document. Selection semantics: `.cell[k]`
refers to character offset in the text content. Supports indexing and
assignment via `[]` and `[]=`.

# Fields

- `cell::Cell` — holds the text content as `String`
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `XmlText(v::AbstractString)` — primitive cell with value
- `XmlText(f::Function)` — computed cell with thunk
"""
@document struct XmlText <: XmlDocument
    cell::String
    selection::Reference
end

XmlText(v::AbstractString) = XmlText(Cell(String(v)), Cell(nothing))
XmlText(f::Function) = XmlText(Cell(f), Cell(nothing))

Base.getindex(t::XmlText) = t.cell::String
Base.setindex!(t::XmlText, v::AbstractString) = (t.cell = String(v))
setfn!(t::XmlText, f::Function) = (setfn!(getfield(t, :cell), f); t)
setval!(t::XmlText, v::AbstractString) = (setval!(getfield(t, :cell), String(v)); t)

# ── Element ───────────────────────────────────────────────────────────────

"""
    XmlElement

Represents an XML element with a tag, attributes, and child nodes. Selection
semantics: `.attrs[i].value[k]` for attribute values, `.cell[i]` for child nodes.
Supports array-like operations on children and dictionary-like operations on attributes.

# Fields

- `tag::String` — the element tag name
- `attrs::CellVector` — holds `XmlAttribute` objects
- `cell::CellVector` — holds child `XmlDocument` nodes
- `collapsed::Cell` — holds `Bool` indicating if element is collapsed in UI
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `XmlElement(tag::AbstractString)` — empty element
- `XmlElement(tag, attrs::Vector{XmlAttribute})` — element with attributes
- `XmlElement(tag, children::Vector{<:XmlDocument})` — element with children
- `XmlElement(tag, attrs, children)` — element with both attributes and children
"""
@document struct XmlElement <: XmlDocument
    tag::String
    attrs::CellVector
    cell::CellVector  # holds XmlDocument children
    collapsed::Bool
    selection::Reference
end

XmlElement(tag::AbstractString) =
    XmlElement(String(tag), CellVector(), CellVector(), Cell(false), Cell(nothing))

function XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute})
    XmlElement(String(tag), CellVector(Cell[Cell(a) for a in attrs]), CellVector(), Cell(false), Cell(nothing))
end

function XmlElement(tag::AbstractString, children::Vector{<:XmlDocument})
    XmlElement(String(tag), CellVector(), CellVector(Cell[Cell(c) for c in children]), Cell(false), Cell(nothing))
end

function XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute}, children::Vector{<:XmlDocument})
    XmlElement(String(tag), CellVector(Cell[Cell(a) for a in attrs]),
               CellVector(Cell[Cell(c) for c in children]), Cell(false), Cell(nothing))
end

# ── Children access ───────────────────────────────────────────────────────────

Base.length(e::XmlElement)                = length(e.cell)
Base.isempty(e::XmlElement)               = isempty(e.cell)
Base.getindex(e::XmlElement, i::Integer)  = e.cell[i]
Base.firstindex(::XmlElement)             = 1
Base.lastindex(e::XmlElement)             = length(e)
Base.iterate(e::XmlElement, state...)     = iterate(e.cell, state...)
Base.eachindex(e::XmlElement)             = eachindex(e.cell)

function Base.push!(e::XmlElement, children::XmlDocument...)
    for c in children
        push!(e.cell, Cell(c))
    end
    return e
end

function Base.setindex!(e::XmlElement, child::XmlDocument, i::Integer)
    e.cell[i] = child
    return child
end

function Base.deleteat!(e::XmlElement, i)
    deleteat!(e.cell, i)
    return e
end

function Base.insert!(e::XmlElement, i::Integer, child::XmlDocument)
    insert!(e.cell, i, Cell(child))
    return e
end

function Base.pop!(e::XmlElement)
    pop!(e.cell)
end

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
            a.cell = String(value)
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

# ── Display ───────────────────────────────────────────────────────────────

Base.show(io::IO, a::XmlAttribute) = print(io, a.name, "=\"", a.cell, "\"")

Base.show(io::IO, t::XmlText) = print(io, t.cell)

function Base.show(io::IO, e::XmlElement)
    attr_str = isempty(e.attrs) ? "" : " " * join(string.(collect(e.attrs)), " ")
    if isempty(e.cell)
        print(io, "<", e.tag, attr_str, "/>")
    else
        print(io, "<", e.tag, attr_str, ">")
        for c in e.cell
            show(io, c)
        end
        print(io, "</", e.tag, ">")
    end
end

end # module
