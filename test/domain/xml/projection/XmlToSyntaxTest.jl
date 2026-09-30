function test_xml_to_syntax()
@testset "XmlToSyntax" begin

x2s = RecursiveProjection(XmlToSyntax())
@test render(print_document(x2s, XmlText("hi")).output) == "hi"
@test render(print_document(x2s, XmlElement("br")).output) == "<br></br>"

# element with an attribute and a text child
el = XmlElement("a", [XmlAttribute("href", "x")], XmlDocument[XmlText("hi")])
@test render(print_document(x2s, el).output) == "<a href=\"x\">hi</a>"

# attribute values are XML-escaped
@test render(print_document(x2s, XmlElement("x", [XmlAttribute("k", "a\"b")])).output) ==
      "<x k=\"a&quot;b\"></x>"

# incremental: a tag rename propagates to both the open and close tags
edoc = XmlElement("old")
etree = print_document(x2s, edoc).output
eout = Cell(@computation render(etree))
@test eout[] == "<old></old>"
edoc.tag = "new"
@test !is_cell_up_to_date(eout)
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
whole = EmptyReference()
selof(x) = getfield(x, :selection)[]

read_key(doc, sel, evt) = begin
    set_selection!(doc, sel)
    iomap = print_document(x2s, doc)
    read_intent(x2s, iomap, evt)
end

# A type-to-replace gesture returns the folded `replace_document` compound;
# `_written` is the document its first member (the ReplaceReferencedValueOperation) writes.
_written(op) = op.operations[1].value

@testset "insertion replace builds the right node" begin
    op = read_key(XmlInsertion(), whole, KeyPress('"'; time = 0.0))
    @test op isa CompoundOperation
    @test _written(op) isa XmlText
    op = read_key(XmlInsertion(), whole, KeyPress('<'; time = 0.0))
    @test op isa CompoundOperation
    @test _written(op) isa XmlElement
    # An unrelated key declines.
    @test read_key(XmlInsertion(), whole, KeyPress('q'; time = 0.0)) === nothing
end

@testset "replacing the whole root swaps editor.document" begin
    doc = XmlInsertion()
    op = read_key(doc, whole, KeyPress('<'; time = 0.0))
    ed = _XmlReaderEditor(doc, nothing)
    evaluate_operation(ed, op)
    @test ed.document isa XmlElement
    @test ed.iomap === nothing                  # forced reprint on a root swap
    @test selof(ed.document) isa ConcreteReference   # cursor in the new tag
end

@testset "replacing a selected child insertion writes the slot in place" begin
    e = XmlElement("a", XmlDocument[XmlInsertion()])
    op = read_key(e, @reference(e, children[1]), KeyPress('<'; time = 0.0))
    @test op isa CompoundOperation
    @test _written(op) isa XmlElement
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test ed.document === e                     # root untouched: incremental write
    @test e.children[1] isa XmlElement
end

@testset "element insert appends a child element and selects its tag" begin
    e = XmlElement("a", XmlDocument[XmlText("hi")])
    op = read_key(e, whole, KeyPress('<'; time = 0.0))
    @test op isa CompoundOperation                        # splice + select-new
    @test op.operations[1] isa ReplaceReferencedValueOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e.children) == 2
    @test e.children[2] isa XmlElement
    @test selof(e.children[2]) isa ConcreteReference  # cursor in the new tag
end

@testset "element insert appends a child text and selects its value" begin
    e = XmlElement("a")
    op = read_key(e, whole, KeyPress('"'; time = 0.0))
    @test op isa CompoundOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e.children) == 1
    @test e.children[1] isa XmlText
    @test selof(e.children[1]) isa ConcreteReference  # cursor in the new text
end

@testset "Space inserts an attribute and selects its name" begin
    e = XmlElement("a")
    # Cursor in the start tag → fires.
    op = read_key(e, @reference(e, tag{0}), KeyDown(:space, ModifierKeys(); time = 0.0))
    @test op isa CompoundOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e.attrs) == 1
    @test e.attrs[1] isa XmlAttribute
    @test selof(e.attrs[1]) isa ConcreteReference  # cursor in the name
    # Gating: Space while editing a child node declines.
    e2 = XmlElement("a", XmlDocument[XmlText("hi")])
    @test read_key(e2, @reference(e2, children[1].content{0}), KeyDown(:space, ModifierKeys(); time = 0.0)) === nothing
end

@testset "Insert key inserts a generic insertion child" begin
    e = XmlElement("a")
    op = read_key(e, whole, KeyDown(:insert, ModifierKeys(); time = 0.0))
    @test op isa CompoundOperation
    ed = _XmlReaderEditor(e, nothing)
    evaluate_operation(ed, op)
    @test length(e.children) == 1
    @test e.children[1] isa XmlInsertion
end

@testset "= moves from an attribute name to its value" begin
    e = XmlElement("a", [XmlAttribute("k", "v")])
    op = read_key(e, @reference(e, attrs[1].name{0}), KeyPress('='; time = 0.0))
    @test op isa ReplaceSelectionOperation
    # op.path is annotated against `e`, so compare against the same typed form.
    @test is_reference_equal(op.path, @reference(e, attrs[1].value{0}))
    # = outside an attribute name does nothing.
    @test read_key(e, whole, KeyPress('='; time = 0.0)) === nothing
end

end # @testset "XmlToSyntax reader commands"
end # test_xml_to_syntax_reader

# The reader runs last-to-first, so a printable key the *output* layers turn into a
# character edit never reaches the domain. `<` and `"` inside a tag name, and `=`
# inside an attribute name, are the exception: a name cannot contain them, so the
# XML gestures claim those keys even though the text layer would happily absorb
# them — an `override` binding. The single-stage tests above cannot see this (with
# one stage there is no text layer to override), so drive the whole chain.
function test_xml_override_gestures()
@testset "XmlToSyntax override gestures (full chain)" begin

chain = ChainingProjection(RecursiveProjection(XmlToSyntax()),
                           RecursiveProjection(SyntaxToText()),
                           TextToGraphics(measure = FontFileMeasure()))

read_key(doc, sel, evt) = begin
    set_selection!(doc, sel)
    read_intent(chain, print_document(chain, doc), evt)
end

@testset "an ordinary key inside a tag name is a character edit" begin
    e = XmlElement("div", XmlDocument[XmlText("hi")])
    @test read_key(e, @reference(e, tag{1}), KeyPress('x'; time = 0.0)) isa ReplaceStringRangeOperation
end

@testset "`<` / `\"` inside a tag name still insert a child (override)" begin
    e = XmlElement("div", XmlDocument[XmlText("hi")])
    @test read_key(e, @reference(e, tag{1}), KeyPress('<'; time = 0.0)) isa CompoundOperation
    @test read_key(e, @reference(e, tag{1}), KeyPress('"'; time = 0.0)) isa CompoundOperation
end

@testset "`<` / `\"` on a whole element insert a child" begin
    e = XmlElement("div", XmlDocument[XmlText("hi")])
    @test read_key(e, EmptyReference(), KeyPress('<'; time = 0.0)) isa CompoundOperation
    @test read_key(e, EmptyReference(), KeyPress('"'; time = 0.0)) isa CompoundOperation
end

# An attribute name can not hold `=`, so in the name the key moves the caret to the
# value, although the text stage would make it a character.
@testset "`=` in an attribute name moves to the value (override)" begin
    e = XmlElement("div", [XmlAttribute("key", "v")])
    op = read_key(e, @reference(e, attrs[1].name{1}), KeyPress('='; time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test is_reference_equal(op.path, @reference(e, attrs[1].value{0}))
end

@testset "`=` in an attribute value or a text is a character edit" begin
    e = XmlElement("div", [XmlAttribute("key", "v")], XmlDocument[XmlText("hi")])
    @test read_key(e, @reference(e, attrs[1].value{1}), KeyPress('='; time = 0.0)) isa ReplaceStringRangeOperation
    @test read_key(e, @reference(e, children[1].content{1}), KeyPress('='; time = 0.0)) isa ReplaceStringRangeOperation
    @test read_key(e, @reference(e, tag{1}), KeyPress('='; time = 0.0)) isa ReplaceStringRangeOperation
end

end # @testset "XmlToSyntax override gestures (full chain)"
end # test_xml_override_gestures
