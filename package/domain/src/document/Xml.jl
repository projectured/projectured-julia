"""
    XmlModule

The XML document domain. Attributes are first-class documents, so the selection
mechanism can descend into attribute values as well as element children and text.

The domain includes:
- **Node types**: `XmlText`, `XmlElement`, `XmlInsertion`
- **Attribute type**: `XmlAttribute`
- **Base type**: `XmlDocument`
"""
module XmlModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document, @forward_map
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement,
       IXmlInsertion, IXmlText, IXmlAttribute, IXmlElement

abstract type XmlDocument <: Document end

# ── Insertion cursor ────────────────────────────────────────────────

"""
A placeholder for an XML node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct XmlInsertion <: XmlDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Attribute ─────────────────────────────────────────────────────────────

"""
An XML attribute, a first-class document so the selection can descend into its value.
"""
@document struct XmlAttribute <: XmlDocument
    name::String
    value::String
    selection::Reference = nothing
end

# ── Text node ─────────────────────────────────────────────────────────────

"""
A text node in an XML element.
"""
@document struct XmlText <: XmlDocument
    content::String
    selection::Reference = nothing
end

# ── Element ───────────────────────────────────────────────────────────────

"""
An XML element with a tag, attributes (`attrs`) and child nodes (`children`).
`collapsed` hides its children behind a marker in the projection. The empty
`XmlElement(tag)` form comes from the macro.
"""
@document struct XmlElement <: XmlDocument
    tag::String
    attrs::CellVector = CellVector()
    children::CellVector = CellVector()  # holds XmlDocument children
    collapsed::Bool = false
    selection::Reference = nothing
end

# `attrs` and `children` are both `CellVector` fields, so the macro can't tell an
# attribute vector from a child vector; these ctors disambiguate by element type.
XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute}) =
    XmlElement(tag, attrs, XmlDocument[])

XmlElement(tag::AbstractString, children::Vector{<:XmlDocument}) =
    XmlElement(tag, XmlAttribute[], children)

# The 3-arg CellVector call lands on the macro's generated ctor, filling the
# `collapsed`/`selection` defaults.
XmlElement(tag::AbstractString, attrs::Vector{XmlAttribute}, children::Vector{<:XmlDocument}) =
    XmlElement(tag, CellVector(attrs), CellVector(children))

# Dictionary-like attribute access, keyed by attribute name. As with `JsonObject`,
# `@forward_map` generates `getindex`/`setindex!`/`haskey`/`keys`/`values`/`get`/
# `delete!` and a pair-`iterate` over the `attrs` map (so `e[name]` reads a value,
# `e[name] = v` sets one, `delete!(e, name)` removes it).
@forward_map XmlElement attrs name value XmlAttribute

# Text-replace edits need no per-type method: the type-in target fields —
# `XmlText.content`, `XmlAttribute.name`/`value`, and `XmlElement.tag` — are all
# plain strings. (Both the open and close tags render from the single `tag`
# field, so editing it updates them together.)

end # module
