# The XML text parser: tags, attributes, text, character references and the
# malformed-input cases.

using Test

function test_xml_parser()
    @testset "parse_xml" begin
        e = parse_xml("<a/>")
        @test e isa XmlElement
        @test e.tag == "a"
        @test isempty(e.children)

        attr = parse_xml("""<a id="1" name='x'/>""")
        @test length(attr.attrs) == 2

        # Prolog + comment skipped; nested elements + text.
        doc = parse_xml("""<?xml version="1.0"?><!-- c --><note id="1"><to>Tove</to><from>Jani</from></note>""")
        @test doc.tag == "note"
        @test length(doc.children) == 2
        to = doc.children[1]
        @test to isa XmlElement && to.tag == "to"
        @test to.children[1] isa XmlText

        # Entity unescaping in text.
        ent = parse_xml("<p>a &amp; b &lt; c</p>")
        @test ent.children[1].content == "a & b < c"

        # A numeric character reference reads as its character, in decimal or in
        # hexadecimal, in text and in an attribute value.
        @test parse_xml("<p>&#65;&#x42;&#x263a;</p>").children[1].content == "AB☺"
        @test parse_xml("<p a=\"&#65;\"/>").attrs[1].value == "A"
        # One pass reads the named and the numeric references, so the `&` that
        # `&amp;` gives does not start a second reference.
        @test parse_xml("<p>&amp;#65;</p>").children[1].content == "&#65;"
        # A code point that is not a character stays as it is written.
        @test parse_xml("<p>&#xD800;</p>").children[1].content == "&#xD800;"
        @test parse_xml("<p>&#99999999999;</p>").children[1].content == "&#99999999999;"
        # A save writes the character, not the escaped reference.
        x2s = RecursiveProjection(XmlToSyntax())
        @test render(print_document(x2s, parse_xml("<p>&#65;</p>")).output) == "<p>A</p>"

        # Mismatched close tag errors.
        @test_throws Exception parse_xml("<a></b>")
        @test_throws Exception parse_xml("not xml")
    end
end
