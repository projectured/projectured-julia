"""
    XmlModule

XML documents: elements with attributes and text, read from a file and written back
as text. Attributes are first-class documents, so the selection mechanism can
descend into attribute values as well as element children and text.

The domain includes:
- **Node types**: `XmlText`, `XmlElement`, `XmlInsertion`
- **Attribute type**: `XmlAttribute`
- **Base type**: `XmlDocument`
"""
module XmlModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content,
                              get_file_format_extensions, get_file_format_domain,
                              parse_document_string, get_file_type, get_file_format
import ..NaturalModule: make_syntax_projection, find_natural_file_format
import ..DisplayModule: make_workload_file

export parse_xml, parse_xml_file
export XmlTheme, ScaledXmlTheme
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlAttributeToSyntaxNode,
       XmlElementToSyntaxNode,
       XmlToSyntax
export XmlFile, PRED_REF_ELEMENT_TAG, XmlFileFormat
export XmlDocument, XmlElement, XmlAttribute, XmlText, XmlNothing, XmlInsertion


include("XmlDocument.jl")
include("XmlParser.jl")
include("XmlTheme.jl")
include("XmlToSyntax.jl")
include("XmlFile.jl")


# What this slice registers when it loads: the file extension it owns.
function __init__()
    register_file_document_type!(".xml", XmlFile)
end

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{XmlFile}) =
    (; name = "a.xml", text = "<person><name>Alice</name></person>\n", shown = r"Alice")

end # module
