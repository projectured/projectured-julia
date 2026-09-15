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

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventPatternModule
using ..GestureBindingModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..ProjectionModule: read_intent, map_reference_forward
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content

export parse_xml, parse_xml_file
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlAttributeToSyntaxNode,
       XmlElementToSyntaxNode,
       XmlToSyntax
export XmlFile, PRED_REF_ELEMENT_TAG
export XmlDocument, XmlElement, XmlAttribute, XmlText, XmlNothing, XmlInsertion


include("XmlDocument.jl")
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
