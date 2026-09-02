"""
S7 tests — `XmlFile` round-trip via the existing `xmlparse` +
`XmlToSyntax → print_natural_text` pipeline. Marker syntax is a
`<pred:ref>&lt;&lt;file(\"path\")&gt;&gt;</pred:ref>` element:
XML's entity escaping preserves the `<<` / `>>` inside a text node,
so the marker round-trips cleanly.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedCollection.CollectionModule
using ProjecturedSerialization.FileProjectModule
using ProjecturedXml.XmlFileModule
using ProjecturedXml.XmlModule

function test_xml_file()
@testset "S7: XmlFile round-trip" begin

    @testset "single-file round-trip" begin
        d = mktempdir()
        try
            root = XmlFile("root.xml",
                           XmlElement("root",
                                      XmlDocument[XmlElement("part", XmlDocument[XmlText("hi")])]))
            save_project!(root, d)
            text = read(joinpath(d, "root.xml"), String)
            @test occursin("<root>", text)
            @test occursin("<part>", text)
            @test occursin("hi", text)
            reloaded = load_project(XmlFile, "root.xml", d)
            @test reloaded isa XmlFile
            @test content(reloaded) isa XmlElement
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "embedded child renders as pred:ref element" begin
        d = mktempdir()
        try
            child = XmlFile("child.xml", XmlElement("child", XmlDocument[XmlText("data")]))
            root_el = XmlElement("root", XmlAttribute[],
                                 CellVector(Any[XmlElement("part", XmlDocument[XmlText("hi")]),
                                                 child]))
            root = XmlFile("root.xml", root_el)
            save_project!(root, d)
            @test isfile(joinpath(d, "child.xml"))
            root_text = read(joinpath(d, "root.xml"), String)
            @test occursin("<pred:ref>", root_text)
            @test occursin("&lt;&lt;file(&quot;child.xml&quot;)&gt;&gt;", root_text) ||
                  occursin("&lt;&lt;file(\"child.xml\")&gt;&gt;", root_text)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "load lifts pred:ref element into a ReferenceStub" begin
        d = mktempdir()
        try
            child = XmlFile("child.xml", XmlElement("child", XmlDocument[XmlText("data")]))
            root_el = XmlElement("root", XmlAttribute[],
                                 CellVector(Any[child]))
            root = XmlFile("root.xml", root_el)
            save_project!(root, d)
            reloaded = load_project(XmlFile, "root.xml", d)
            kids = getfield(content(reloaded)::XmlElement, :children)[]
            u = kids[1] isa AbstractCell ? kids[1][] : kids[1]
            @test u isa ReferenceStub
            resolved = resolve!(u)
            @test resolved isa XmlFile
            @test filename(resolved) == "child.xml"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "shared child yields === after resolve" begin
        d = mktempdir()
        try
            child = XmlFile("child.xml", XmlElement("c", XmlDocument[XmlText("x")]))
            root_el = XmlElement("root", XmlAttribute[],
                                 CellVector(Any[child, child]))
            root = XmlFile("root.xml", root_el)
            save_project!(root, d)
            reloaded = load_project(XmlFile, "root.xml", d)
            kids = getfield(content(reloaded)::XmlElement, :children)[]
            s1 = kids[1] isa AbstractCell ? kids[1][] : kids[1]
            s2 = kids[2] isa AbstractCell ? kids[2][] : kids[2]
            @test s1 isa ReferenceStub
            @test s2 isa ReferenceStub
            @test resolve!(s1) === resolve!(s2)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "ordinary element with same-shaped children passes through" begin
        d = mktempdir()
        try
            # A `<pred:ref>` with something other than a single text child
            # is not a marker; treat it as an ordinary element.
            root = XmlFile("root.xml",
                           XmlElement("root", XmlDocument[
                               XmlElement("pred:ref", XmlDocument[
                                   XmlElement("inner", XmlDocument[XmlText("stuff")])])]))
            save_project!(root, d)
            reloaded = load_project(XmlFile, "root.xml", d)
            kids = getfield(content(reloaded)::XmlElement, :children)[]
            u = kids[1] isa AbstractCell ? kids[1][] : kids[1]
            @test u isa XmlElement
            @test u.tag == "pred:ref"
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
