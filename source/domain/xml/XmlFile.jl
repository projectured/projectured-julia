# Fragment of `XmlModule` — `XmlFile`, the `.xml` file on disk.
#
# A cross-file reference is written in XML as a `pred:ref` element whose one
# text child is the marker. The file writes one where the save cuts, and the
# load splices the node it names into its place. What this file contributes is
# the four lines every format owes: its domain, its parser, how it spells a
# reference leaf, and how it recognises one.

"""
The XML tag identifying a cross-file marker element:

    <pred:ref>&lt;&lt;file("path")&gt;&gt;</pred:ref>
"""
const PRED_REF_ELEMENT_TAG = "pred:ref"

# The content is the root element.
@document struct XmlFile <: FileDocument
    filename::String
    content::Document = XmlNothing()
end

# A cell may still be a cell mid-walk: a CellVector holds cells.
_unwrap(x) = x isa AbstractCell ? x[] : x

# What the file writes itself, and how it spells a reference to what it does
# not: a `pred:ref` element with the marker as its one text child.
get_file_domain(::Type{<:XmlFile}) = XmlDocument
make_reference_leaf(::XmlFile, marker::AbstractString) =
    XmlElement(PRED_REF_ELEMENT_TAG, XmlAttribute[], [XmlText(make_marker_text(marker))])
find_reference_marker(node::XmlElement) =
    _is_marker_element(node) ?
        parse_marker_text(strip(_unwrap(getfield(_unwrap(_unwrap(getfield(node, :children))[1]), :content)))) :
        nothing
parse_file_content(::Type{<:XmlFile}, text::AbstractString) = parse_xml(text)

emit_text(f::XmlFile) = print_natural_text(get_file_content(f))

# A `pred:ref` element with a single text child is a marker.
function _is_marker_element(node::XmlElement)
    _unwrap(getfield(node, :tag)) == PRED_REF_ELEMENT_TAG || return false
    children = _unwrap(getfield(node, :children))
    length(children) == 1 || return false
    _unwrap(children[1]) isa XmlText
end
