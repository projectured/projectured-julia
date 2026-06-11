function test_xml_to_syntax()
@testset "XmlToSyntax" begin

x2s = RecursiveProjection(XmlToSyntax())
@test render(projection_print(x2s, XmlText("hi")).output) == "hi"
@test render(projection_print(x2s, XmlElement("br")).output) == "<br></br>"

# element with an attribute and a text child
el = XmlElement("a", [XmlAttribute("href", "x")], XmlDocument[XmlText("hi")])
@test render(projection_print(x2s, el).output) == "<a href=\"x\">hi</a>"

# attribute values are XML-escaped
@test render(projection_print(x2s, XmlElement("x", [XmlAttribute("k", "a\"b")])).output) ==
      "<x k=\"a&quot;b\"></x>"

# incremental: a tag rename propagates to both the open and close tags
edoc = XmlElement("old")
etree = projection_print(x2s, edoc).output
eout = Cell(() -> render(etree))
@test eout[] == "<old></old>"
edoc.tag = "new"
@test !isuptodate(eout)
@test eout[] == "<new></new>"

end # @testset "XmlToSyntax"
end # test_xml_to_syntax

# A minimal stand-in for the Editor that the operation evaluators mutate.
mutable struct _XmlReaderEditor
    document::Any
    iomap::Any
end

# Drive the XML reader command set (the Lisp xml/insertion, xml/element and
# xml/attribute readers). Each XML projection must work as the whole document on
# its own, so the cursor is placed with a selection and a raw key gesture is fed
# straight to the root XML reader.
function test_xml_to_syntax_reader()
@testset "XmlToSyntax reader commands" begin

x2s = RecursiveProjection(XmlToSyntax())
whole = EmptyReferencePath()
selof(x) = getfield(x, :selection)[]

read_key(doc, sel, evt) = begin
    set_selection!(doc, sel)
    iomap = projection_print(x2s, doc)
    projection_read(x2s, iomap, evt)
end

@testset "insertion replace builds the right node" begin
    op = read_key(XmlInsertion(), whole, KeyPress('"'))
    @test op isa ReplaceDocumentOperation
    @test op.document isa XmlText
    op = read_key(XmlInsertion(), whole, KeyPress('<'))
    @test op isa ReplaceDocumentOperation
    @test op.document isa XmlElement
    # An unrelated key declines.
    @test read_key(XmlInsertion(), whole, KeyPress('q')) === nothing
end

@testset "replacing the whole root swaps editor.document" begin
    doc = XmlInsertion()
    op = read_key(doc, whole, KeyPress('<'))
    ed = _XmlReaderEditor(doc, nothing)
    evaluate_operation(ed, op)
    @test ed.document isa XmlElement
    @test ed.iomap === nothing                  # forced reprint on a root swap
    @test selof(ed.document) isa ConcreteReferencePath   # cursor in the new tag
end

@testset "replacing a selected child insertion writes the slot in place" begin
    e = XmlElement("a", XmlDocument[XmlInsertion()])
    op = read_key(e, (@reference cell[1]), KeyPress('<'))
    @test op isa ReplaceDocumentOperation
    @test op.document isa XmlElement
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test ed.document === e                     # root untouched: incremental write
    @test e[1] isa XmlElement
end

@testset "element insert appends a child element and selects its tag" begin
    e = XmlElement("a", XmlDocument[XmlText("hi")])
    op = read_key(e, whole, KeyPress('<'))
    @test op isa CollectionInsertOperation
    @test op.index == 1
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e) == 2
    @test e[2] isa XmlElement
    @test selof(e[2]) isa ConcreteReferencePath  # cursor in the new tag
end

@testset "element insert appends a child text and selects its value" begin
    e = XmlElement("a")
    op = read_key(e, whole, KeyPress('"'))
    @test op isa CollectionInsertOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e) == 1
    @test e[1] isa XmlText
    @test selof(e[1]) isa ConcreteReferencePath  # cursor in the new text
end

@testset "Space inserts an attribute and selects its name" begin
    e = XmlElement("a")
    # Cursor in the start tag → fires.
    op = read_key(e, (@reference tag{0}), KeyDown(:space, Modifiers()))
    @test op isa CollectionInsertOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e.attrs) == 1
    @test e.attrs[1] isa XmlAttribute
    @test selof(e.attrs[1]) isa ConcreteReferencePath  # cursor in the name
    # Gating: Space while editing a child node declines.
    e2 = XmlElement("a", XmlDocument[XmlText("hi")])
    @test read_key(e2, (@reference cell[1].cell{0}), KeyDown(:space, Modifiers())) === nothing
end

@testset "Insert key inserts a generic insertion child" begin
    e = XmlElement("a")
    op = read_key(e, whole, KeyDown(:insert, Modifiers()))
    @test op isa CollectionInsertOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e) == 1
    @test e[1] isa XmlInsertion
end

@testset "= moves from an attribute name to its value" begin
    e = XmlElement("a", [XmlAttribute("k", "v")])
    op = read_key(e, (@reference attrs[1].name{0}), KeyPress('='))
    @test op isa ReplaceSelectionOperation
    @test reference_equal(op.path, @reference attrs[1].cell{0})
    # = outside an attribute name does nothing.
    @test read_key(e, whole, KeyPress('=')) === nothing
end

end # @testset "XmlToSyntax reader commands"
end # test_xml_to_syntax_reader
