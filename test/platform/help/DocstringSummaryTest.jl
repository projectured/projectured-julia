# The description a Help list shows for a type: the first paragraph of its
# docstring. Each fixture below is a type with a docstring of one shape.

"""
    _SummaryTwoParagraphs(x)

The first paragraph
runs over two lines.

The second paragraph.
"""
struct _SummaryTwoParagraphs end

struct _SummaryNoDocstring end

"""
```julia
_SummaryFenced()
```
The text after a fence.
"""
struct _SummaryFenced end

"""
    _SummarySignatureOnly()
"""
struct _SummarySignatureOnly end

"""
# A heading

The text after a heading.
"""
struct _SummaryHeading end

"""
The text of the type.
"""
struct _SummaryTypeAndConstructor
    x::Int
end

"""
    _SummaryTypeAndConstructor()

The text of the constructor.
"""
_SummaryTypeAndConstructor() = _SummaryTypeAndConstructor(0)

struct _SummaryConstructorOnly
    x::Int
end

"""
    _SummaryConstructorOnly()

The text of the constructor alone.
"""
_SummaryConstructorOnly() = _SummaryConstructorOnly(0)

function test_docstring_summary()
@testset "the description of a type is the first paragraph of its docstring" begin
    @test compute_docstring_summary(_SummaryTwoParagraphs) ==
          "The first paragraph runs over two lines."
    @test compute_docstring_summary(_SummaryNoDocstring) == ""
    @test compute_docstring_summary(_SummaryFenced) == "The text after a fence."
    @test compute_docstring_summary(_SummarySignatureOnly) == ""
    @test compute_docstring_summary(_SummaryHeading) == "The text after a heading."
    # The docstring of the type comes before the one of a constructor, and a
    # constructor speaks for a type that has none of its own.
    @test compute_docstring_summary(_SummaryTypeAndConstructor) == "The text of the type."
    @test compute_docstring_summary(_SummaryConstructorOnly) ==
          "The text of the constructor alone."
    # A document of a package: the macro keeps the docstring of the type.
    @test startswith(compute_docstring_summary(AboutPage), "What a program says about itself")
    # A type with parameters is found by its name.
    @test startswith(compute_docstring_summary(ChainingProjection), "A compound higher-order projection")
end
end
