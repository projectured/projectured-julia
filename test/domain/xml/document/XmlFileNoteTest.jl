# An XML file says what the pointer is on: the path of the element that holds the
# part, its namespace, and how many attributes and child elements it has. The part
# under the pointer is the end of the mouse target of the file; with no pointer, the
# end of its selection.

# The note that the file answers to a dwell, or `nothing`.
function _xfn_read_note(file)
    operation = read_gesture(file, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The path from `file` to its part that `found` names.
_xfn_path(file, found) = only(search_references(file, node -> found(node)))

function test_xml_file_note()
@testset "an XML file says the path of the element under the pointer" begin
    file = XmlFile("a.xml", parse_xml("<root xmlns=\"urn:r\" xmlns:x=\"urn:x\"><a id=\"1\"><b>hi</b></a><a/><x:c/></root>"))
    @test _xfn_read_note(file) === nothing
    # The pointer rests in the text of an element: the note is about the element that holds it.
    text = _xfn_path(file, node -> node isa XmlText && node.content == "hi")
    replace_mouse_target!(file, extend_reference(text, FieldReferenceStep("content")))
    note = _xfn_read_note(file)
    @test note.title == "a.xml"
    @test note.facts == ["Path" => "/root/a[1]/b", "Namespace" => "urn:r", "Attributes" => "0", "Children" => "0"]
    # An attribute is about its element, and an index stands only among elements of the same tag.
    attribute = _xfn_path(file, node -> node isa XmlAttribute && node.name == "id")
    replace_mouse_target!(file, attribute)
    @test _xfn_read_note(file).facts ==
          ["Path" => "/root/a[1]", "Namespace" => "urn:r", "Attributes" => "1", "Children" => "1"]
    # A prefix names its own namespace.
    prefixed = _xfn_path(file, node -> node isa XmlElement && node.tag == "x:c")
    replace_mouse_target!(file, prefixed)
    @test _xfn_read_note(file).facts ==
          ["Path" => "/root/x:c", "Namespace" => "urn:x", "Attributes" => "0", "Children" => "0"]
    # With no pointer on the file, the note is about the selected part; no namespace declared, no fact.
    selected = XmlFile("b.xml", parse_xml("<doc><p/></doc>"))
    replace_selection!(selected, _xfn_path(selected, node -> node isa XmlElement && node.tag == "p"))
    @test _xfn_read_note(selected).facts == ["Path" => "/doc/p", "Attributes" => "0", "Children" => "0"]
end
end
