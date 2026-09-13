# The XML text parser: tags, attributes, text and the malformed-input cases.
# Split out of JsonParserTest when the domains became separate packages.

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

        # Mismatched close tag errors.
        @test_throws Exception parse_xml("<a></b>")
        @test_throws Exception parse_xml("not xml")
    end
end
