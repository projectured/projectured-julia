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

# The file says what the pointer is on: the element that holds the part, with its
# path from the root, its namespace, and how many attributes and child elements it
# has. With no pointer on the file, it says the selected part.
function _make_xml_part_note(file::XmlFile)
    found = find_pointed_part(file)
    found === nothing && return nothing
    part = found.part
    part isa XmlDocument || return nothing
    elements = XmlElement[document for document in found.documents if document isa XmlElement]
    isempty(elements) && return nothing
    element = elements[end]
    facts = Pair{String,Any}["Path" => _format_xml_path(elements)]
    namespace = _find_xml_namespace(elements)
    namespace === nothing || push!(facts, "Namespace" => namespace)
    push!(facts, "Attributes" => string(length(element.attrs)),
                 "Children" => string(count(child -> child isa XmlElement, collect(element.children))))
    TooltipNote(; title = basename(file.filename), facts)
end

# The path of the last of `elements` from the root: the tag of each element after
# a slash, with its place among the children of the same tag in brackets, counted
# from 1, when its parent has more than one.
function _format_xml_path(elements)
    text = string("/", elements[1].tag)
    for index in 2:length(elements)
        element = elements[index]
        same_tag = [child for child in collect(elements[index - 1].children)
                    if child isa XmlElement && child.tag == element.tag]
        place = findfirst(child -> child === element, same_tag)
        text = length(same_tag) > 1 && place !== nothing ?
            string(text, "/", element.tag, "[", place, "]") : string(text, "/", element.tag)
    end
    text
end

# The namespace of the last of `elements`: the value of the `xmlns:prefix`
# attribute for its prefix, or of `xmlns` when it has none, declared on the nearest
# element of the path that declares it. `nothing` when none is declared.
function _find_xml_namespace(elements)
    tag = elements[end].tag
    prefix = occursin(':', tag) ? first(split(tag, ':')) : nothing
    declaration = prefix === nothing ? "xmlns" : string("xmlns:", prefix)
    for element in Iterators.reverse(elements)
        for attribute in collect(element.attrs)
            attribute isa XmlAttribute && attribute.name == declaration && return attribute.value
        end
    end
    nothing
end

# The table of the file: a dwell answers the note of the part under the pointer.
const _XML_FILE_BINDINGS = GestureBinding[
    make_tooltip_binding(_make_xml_part_note; description = "Show the path of the part")]

@gestures XmlFile begin
    splice(_XML_FILE_BINDINGS)
end
