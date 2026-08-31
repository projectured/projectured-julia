"""
What a top-level definition is called, which is how `definition(file(f), name)`
finds one.

A marker addresses a definition by the name it already carries, so that the
embed survives editing and reordering the file around it. The name therefore
has to be found for everything people declare with, including the macros that
declare a type rather than decorate one.
"""

using Test
using ProjecturedJulia.JuliaParserModule: juliaparse
using ProjecturedJulia.JuliaFileModule: julia_definition
using ProjecturedFileFormat.NaturalFormatModule: document_to_text

# What the marker gets back when it asks a source file for one definition.
_definition_text(source::AbstractString, name::AbstractString) =
    strip(document_to_text(julia_definition(juliaparse(source), name)))

# Whether the file offers a definition by that name at all.
_offers(source::AbstractString, name::AbstractString) =
    try
        julia_definition(juliaparse(source), name)
        true
    catch
        false
    end

function test_julia_definition()
@testset "Julia: a definition is found by its own name" begin

    @testset "the ordinary definitions" begin
        @test _offers("f(x) = x", "f")
        @test _offers("function f(x)\n    x\nend", "f")
        @test _offers("struct Foo\n    a::Int\nend", "Foo")
        @test _offers("abstract type Foo end", "Foo")
        @test _offers("const FOO = 1", "FOO")
        # A statement that introduces no name offers none.
        @test !_offers("using Foo", "Foo")
    end

    @testset "a macro that decorates is named by what it wraps" begin
        @test _offers("@document struct Foo\n    a::Int\nend", "Foo")
    end

    @testset "a macro that declares is named by what it introduces" begin
        # `@header Ipv4Header begin … end` states the name itself: there is no
        # inner definition to ask, and the first argument is the name.
        @test _offers("@header Ipv4Header begin\n    version::U4\nend", "Ipv4Header")
        # A member of a family names the family it joins, and the definition is
        # the left side of the `<:` — the same rule a struct header follows.
        @test _offers("@header Member <: Family begin\n    a::U8\nend", "Member")
        @test !_offers("@header Member <: Family begin\n    a::U8\nend", "Family")
        # A parametric declaration is named by the base.
        @test _offers("@header Foo{T} begin\n    a::T\nend", "Foo")
    end

    @testset "a docstring is named by what it documents" begin
        # And the docstring comes back with it: a documented definition without
        # its documentation is half of what the page asked for.
        text = _definition_text("\"what it is\"\n@header Foo begin\n    a::U8\nend", "Foo")
        @test occursin("what it is", text)
        @test occursin("@header Foo", text)
    end

    @testset "the marker picks one definition out of a file" begin
        source = """
                 const A = 1

                 @header Foo begin
                     version::U4
                 end

                 f(x) = x
                 """
        text = _definition_text(source, "Foo")
        @test occursin("@header Foo", text)
        @test !occursin("const A", text)
        @test !occursin("f(x) = x", text)
    end

end
end
