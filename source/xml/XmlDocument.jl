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

export parse_xml, parse_xml_file
using ..CellModule
import ..ProjectionModule: read_intent, map_reference_forward
using ..ProjectionModule
using ..SyntaxModule
using ..TextModule
using ..StyleModule
using ..ProjectionAlgebraModule
using ..SerializationModule
import ..SerializationModule: emit_text, populate_file!
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlAttributeToSyntaxNode,
       XmlElementToSyntaxNode,
       ReferenceStubToXmlSyntaxLeaf, EmbeddedFileDocumentToXmlSyntaxLeaf,
       XmlToSyntax
import ..FileFormatModule: make_document_seed
using ..NaturalModule
export XmlFile, PRED_REF_ELEMENT_TAG
export XmlDocument, XmlElement, XmlAttribute, XmlText, XmlNothing, XmlInsertion


using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

@domain Xml

# ── Attribute ─────────────────────────────────────────────────────────────

"""
An XML attribute, a first-class document so the selection can descend into its value.
"""
@document struct XmlAttribute <: XmlDocument
    name::String
    value::String
end

# ── Text node ─────────────────────────────────────────────────────────────

"""
A text node in an XML element.
"""
@document struct XmlText <: XmlDocument
    content::String
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
end

# `attrs` and `children` are both `CellVector`, so the macro can't tell an
# attribute vector from a child vector; these disambiguate by element type.
# The `<:` covariance matters — after the `@document` refactor, callers pass
# `[XmlAttribute(...)]` which is `Vector{RCXmlAttribute}`, and `Vector{XmlAttribute}`
# (invariant) would silently miss it and fall through to the `<:XmlDocument`
# overload, routing attrs into the children slot.
XmlElement(tag::AbstractString, attrs::Vector{<:XmlAttribute}) =
    XmlElement(tag, attrs, XmlDocument[])

XmlElement(tag::AbstractString, children::Vector{<:XmlDocument}) =
    XmlElement(tag, XmlAttribute[], children)

XmlElement(tag::AbstractString, attrs::Vector{<:XmlAttribute}, children::Vector{<:XmlDocument}) =
    XmlElement(tag, CellVector(attrs), CellVector(children))

# attributes as a name-keyed map
@adapt_map_protocol on XmlElement to attrs with XmlAttribute(name, value)

# Text-replace edits need no per-type method: every type-in target — `XmlText.content`,
# `XmlAttribute.name`/`value`, `XmlElement.tag` — is a plain string (editing `tag`
# reactively updates both the open and close tags).

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# The reader runs last-to-first, so a key the text layer absorbed never reaches these
# gestures — a character typed into a tag name stays a character. `<` and `"` are the
# exception: neither can occur *in* a tag name, so they mean "insert a child" even
# while the caret is in one, and are declared `override` to claim the key back.

_xml_selected(doc) = try_evaluate_reference(doc, getfield(doc, :selection)[])

# A placeholder is replaceable — the empty `XmlNothing` as well as a typed-name
# `XmlInsertion` buffer — so `<`/`"`/`@` build the node directly (as JSON's `[`/`{`/`"`
# do), and a structure can be authored from nothing without going through the buffer. The
# keys are non-alphanumeric so that, while a buffer *is* selected, a letter still goes
# into the buffer (its name) rather than replacing it.
_xml_replaceable(doc, sel) = _xml_selected(doc) isa Union{XmlNothing, XmlInsertion}

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion XmlText      = @with_selection XmlText("") content{0}
@insertion XmlAttribute = @with_selection XmlAttribute("", "") name{0}
@insertion XmlElement   = @with_selection XmlElement("") tag{0}

@gestures XmlDocument begin
    when(_xml_replaceable(doc, sel))
    KeyPress('"') => "Replace with text"        => replace_selected_document(doc, make_insertion_document(XmlText))
    KeyPress('<') => "Replace with an element"  => replace_selected_document(doc, make_insertion_document(XmlElement))
    KeyPress('@') => "Replace with an attribute" => replace_selected_document(doc, make_insertion_document(XmlAttribute))
end

# `<`/`"` decline when an insertion is selected, letting the replace gestures win.
_xml_insert_element(e) = _xml_replaceable(e, nothing) ? nothing :
    append_insertion_operation(e, :children, XmlElement)
_xml_insert_text(e) = _xml_replaceable(e, nothing) ? nothing :
    append_insertion_operation(e, :children, XmlText)
_xml_insert_node(e) = append_insertion_operation(e, :children, XmlInsertion)

# A new attribute may be added only from the element itself, its tag, or an
# existing attribute — never while editing a child.
_xml_in_attr_context(sel) =
    sel isa EmptyReference ||
    is_introduced_reference(sel) ||
    (sel isa ConcreteReference && sel.head isa FieldReferenceStep &&
     (sel.head.name == "tag" || sel.head.name == "attrs"))

_xml_insert_attr(e) = _xml_in_attr_context(getfield(e, :selection)[]) ?
    append_insertion_operation(e, :attrs, XmlAttribute) : nothing

@gestures XmlElement begin
    override(KeyPress('<')) => "Insert an element"       => _xml_insert_element(doc)
    override(KeyPress('"')) => "Insert text"             => _xml_insert_text(doc)
    KeyDown(:insert)        => "Insert a node"           => _xml_insert_node(doc)
    KeyDown(:space)         => "Insert an attribute"     => _xml_insert_attr(doc)
    KeyPress('=')           => "Move to attribute value" => move_to_field(doc, :name, :value)
    # The way back has no key of its own. A rule with no gesture reaches the user by
    # name instead, through the command palette.
    nothing                 => "Move to attribute name"  => move_to_field(doc, :value, :name)
end


include("XmlParser.jl")
include("XmlToSyntax.jl")
include("XmlFile.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_natural_domain!(XmlDocument;
                             rung      = :syntax,
                             make      = () -> XmlToSyntax(),
                             format    = :xml,
                             extension = ".xml",
                             parse     = parse_xml)

    register_file_document_type!(".xml", XmlFile)
end

end # module
