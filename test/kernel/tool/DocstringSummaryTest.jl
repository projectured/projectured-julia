# The description of a type that a Help list and a card of a tab show: the first
# paragraph of its docstring. Each fixture below is a type with a docstring of one
# shape.

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

"""
    _SummaryModule

The text of the module.

The second paragraph of the module.
"""
module _SummaryModule end

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
    # A document: the macro keeps the docstring of the type.
    @test compute_docstring_summary(FieldReferenceStep) == "References a named field of an object/record."
    # A type with parameters is found by its name.
    @test compute_docstring_summary(ImmutableCell) == "A box that holds one value and can never be written."
    # A module: its own docstring, in the module that holds it.
    @test compute_docstring_summary(_SummaryModule) == "The text of the module."
    @test compute_docstring_summary(ProjecturedKernel.ToolModule) != ""
    # The whole text keeps every paragraph and the signature, and a type with no
    # docstring has none.
    @test find_docstring_text(_SummaryTwoParagraphs) ==
          "    _SummaryTwoParagraphs(x)\n\nThe first paragraph\nruns over two lines.\n\nThe second paragraph."
    @test find_docstring_text(_SummaryNoDocstring) === nothing
    @test find_docstring_text(_SummaryTypeAndConstructor) == "The text of the type."
    @test endswith(find_docstring_text(_SummaryConstructorOnly), "The text of the constructor alone.")
    @test endswith(find_docstring_text(_SummaryModule), "The second paragraph of the module.")
    # A view for a person drops the code marks.
    @test strip_code_marks("The keywords: `on`, `when` and `<:`.") == "The keywords: on, when and <:."
end
end
