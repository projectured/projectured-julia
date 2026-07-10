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

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document, @forward_map
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ConcreteReferencePath, FieldReference, EmptyReferencePath, evaluate_reference
import ..ProjectionReferenceModule: ProjectionReference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: replace_document, insert_elements, ReplaceSelectionOperation
import ..ReferenceApiModule: with_selection
import ..KeyboardModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
import ..DomainSupportModule: var"@domain", make_insertion_document
export XmlDocument

# The domain kit: `XmlDocument` (abstract root), `XmlNothing` (empty
# placeholder, Insert turns it into the insertion), `XmlInsertion` (typed-name
# buffer completing over the XML candidates), the Insert gesture and the
# insertion traits — all generated from the domain name.
@domain Xml

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

# `attrs` and `children` are both `CellVector`, so the macro can't tell an
# attribute vector from a child vector; these disambiguate by element type.
# The `<:` covariance matters — after the `@document` refactor, callers pass
# `[XmlAttribute(...)]` which is `Vector{RXmlAttribute}`, and `Vector{XmlAttribute}`
# (invariant) would silently miss it and fall through to the `<:XmlDocument`
# overload, routing attrs into the children slot.
XmlElement(tag::AbstractString, attrs::Vector{<:XmlAttribute}) =
    XmlElement(tag, attrs, XmlDocument[])

XmlElement(tag::AbstractString, children::Vector{<:XmlDocument}) =
    XmlElement(tag, XmlAttribute[], children)

XmlElement(tag::AbstractString, attrs::Vector{<:XmlAttribute}, children::Vector{<:XmlDocument}) =
    XmlElement(tag, CellVector(attrs), CellVector(children))

# attributes as a name-keyed map
@forward_map XmlElement attrs name value XmlAttribute

# Text-replace edits need no per-type method: every type-in target — `XmlText.content`,
# `XmlAttribute.name`/`value`, `XmlElement.tag` — is a plain string (editing `tag`
# reactively updates both the open and close tags).

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# A raw key on a whole XML node edits the tree; a character cursor inside text is
# consumed upstream, so these never fire mid-edit. Each gesture reads `doc`'s own
# selection and emits a `doc`-relative operation.

# The node the cursor is on, or nothing.
function _xml_selected(doc)
    sel = getfield(doc, :selection)[]
    sel === nothing && return nothing
    try evaluate_reference(doc, sel) catch; nothing end
end

# Only an insertion placeholder is replaceable: `"` becomes an empty text node,
# `<` an empty element, each with its cursor pre-placed.
_xml_replaceable(doc, sel) = _xml_selected(doc) isa XmlInsertion
_xml_replace(doc, newdoc) = replace_document(getfield(doc, :selection)[], newdoc)

# ── Insertion factories ─────────────────────────────────────────────────────
#
# One construction per committable XML node, with its cursor pre-placed —
# shared by the char type-to-replace gestures below and by the typed-name
# commit of an `XmlInsertion` / `DocumentInsertion`. `XmlAttribute` stays out
# of the candidates automatically: it has required fields and no method here
# (it cannot stand alone as a child).
make_insertion_document(::Type{<:XmlText}) =
    with_selection(XmlText(""), @reference content{0})
make_insertion_document(::Type{<:XmlElement}) =
    with_selection(XmlElement(""), @reference tag{0})

@gestures XmlDocument begin
    when(_xml_replaceable(doc, sel))
    KeyPress('"') => "Replace with text"      => _xml_replace(doc, make_insertion_document(XmlText))
    KeyPress('<') => "Replace with an element" => _xml_replace(doc, make_insertion_document(XmlElement))
end

# Append a child at the end and drop the cursor into it. `<`/`"` decline when an
# insertion is selected, letting the replace gestures above win.
function _xml_insert_element(e)
    _xml_replaceable(e, nothing) && return nothing
    n = length(e.children)
    insert_elements(@reference(children), n, Any[XmlElement("")], @reference children[n + 1].tag{0})
end
function _xml_insert_text(e)
    _xml_replaceable(e, nothing) && return nothing
    n = length(e.children)
    insert_elements(@reference(children), n, Any[XmlText("")], @reference children[n + 1].content{0})
end
function _xml_insert_node(e)
    n = length(e.children)
    insert_elements(@reference(children), n, Any[XmlInsertion()], @reference children[n + 1])
end

# A new attribute may be added only from the element itself, its tag, or an
# existing attribute — never while editing a child.
_xml_in_attr_context(sel) =
    sel isa EmptyReferencePath ||
    (sel isa ConcreteReferencePath &&
     (sel.head isa ProjectionReference ||
      (sel.head isa FieldReference && (sel.head.name == "tag" || sel.head.name == "attrs"))))

function _xml_insert_attr(e)
    _xml_in_attr_context(getfield(e, :selection)[]) || return nothing
    n = length(e.attrs)
    insert_elements(@reference(attrs), n, Any[XmlAttribute("", "")], @reference attrs[n + 1].name{0})
end

# `=` moves the cursor from an attribute name to its value.
function _xml_attr_value(e)
    sel = getfield(e, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        attrs{s:_}.name.rest... => ReplaceSelectionOperation(@reference attrs[s + 1].value{0})
    end
end

@gestures XmlElement begin
    KeyPress('<')    => "Insert an element"       => _xml_insert_element(doc)
    KeyPress('"')    => "Insert text"             => _xml_insert_text(doc)
    KeyDown(:insert) => "Insert a node"           => _xml_insert_node(doc)
    KeyDown(:space)  => "Insert an attribute"     => _xml_insert_attr(doc)
    KeyPress('=')    => "Move to attribute value" => _xml_attr_value(doc)
end

end # module
