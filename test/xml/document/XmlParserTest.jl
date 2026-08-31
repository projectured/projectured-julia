# The XML text parser: tags, attributes, text and the malformed-input cases.
# Split out of JsonParserTest when the domains became separate packages.

using Test

function test_xml_parser()
    @testset "xmlparse" begin
        e = xmlparse("<a/>")
        @test e isa XmlElement
        @test e.tag == "a"
        @test isempty(e.children)

        attr = xmlparse("""<a id="1" name='x'/>""")
        @test length(attr.attrs) == 2

        # Prolog + comment skipped; nested elements + text.
        doc = xmlparse("""<?xml version="1.0"?><!-- c --><note id="1"><to>Tove</to><from>Jani</from></note>""")
        @test doc.tag == "note"
        @test length(doc.children) == 2
        to = doc.children[1]
        @test to isa XmlElement && to.tag == "to"
        @test to.children[1] isa XmlText

        # Entity unescaping in text.
        ent = xmlparse("<p>a &amp; b &lt; c</p>")
        @test ent.children[1].content == "a & b < c"

        # Mismatched close tag errors.
        @test_throws Exception xmlparse("<a></b>")
        @test_throws Exception xmlparse("not xml")
    end
end
