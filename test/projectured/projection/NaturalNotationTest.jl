# A family of three documents: a notation on the root answers for every document
# under it, and a notation on a subtype answers for that subtype.
abstract type NaturalNotationTestRoot <: Document end
struct NaturalNotationTestLeaf <: NaturalNotationTestRoot end
struct NaturalNotationTestOther <: NaturalNotationTestRoot end
struct NaturalNotationTestRootProjection <: Projection end
struct NaturalNotationTestLeafProjection <: Projection end
# Two formats with no extension, so no search over the formats of the session
# finds them.
struct NaturalNotationTestRootFileFormat <: FileFormat end
struct NaturalNotationTestLeafFileFormat <: FileFormat end

# The methods that `test_natural_notation` adds: of the two seams, and of the
# keyword call of the first.
_find_natural_notation_test_methods() =
    [method for method in vcat(collect(methods(make_syntax_projection)),
                               collect(methods(Core.kwcall, Tuple{Any, typeof(make_syntax_projection), Vararg{Any}})),
                               collect(methods(find_natural_file_format)))
     if method.module === @__MODULE__]

"""
    test_natural_notation()

The notation and the natural format of a document come from the most specific
method of `make_syntax_projection` and of `find_natural_file_format`, whatever
the order in which the methods are defined, and each type with a notation is a
row of the renderer before its supertype. The test adds its methods while it
runs and removes them after, so no test type stays in a method table.
"""
function test_natural_notation()
    # The root comes first: a lookup that takes the first match fails.
    @eval begin
        NaturalModule.make_syntax_projection(::Type{<:NaturalNotationTestRoot}; appearance) =
            NaturalNotationTestRootProjection()
        NaturalModule.make_syntax_projection(::Type{NaturalNotationTestLeaf}; appearance) =
            NaturalNotationTestLeafProjection()
        NaturalModule.find_natural_file_format(::NaturalNotationTestRoot) = NaturalNotationTestRootFileFormat()
        NaturalModule.find_natural_file_format(::NaturalNotationTestLeaf) = NaturalNotationTestLeafFileFormat()
    end
    try
        # The one stage of a chain that stops at the rung of the notation: the
        # default of the dispatch that puts what a person arranged at a place.
        get_stage(chain) = only(chain.projections).child.default
        make_stage(document) = get_stage(Base.invokelatest(make_natural_projection, document, :syntax))

        @testset "the most specific method gives the notation" begin
            @test make_stage(NaturalNotationTestLeaf()) isa NaturalNotationTestLeafProjection
            @test make_stage(NaturalNotationTestOther()) isa NaturalNotationTestRootProjection
        end

        @testset "the most specific method gives the format" begin
            @test Base.invokelatest(find_natural_file_format, NaturalNotationTestLeaf()) ===
                  NaturalNotationTestLeafFileFormat()
            @test Base.invokelatest(find_natural_file_format, NaturalNotationTestOther()) ===
                  NaturalNotationTestRootFileFormat()
        end

        @testset "a type with a notation is a row of the renderer, before its supertype" begin
            types = first.(Base.invokelatest(get_natural_entries; appearance = Appearance()))
            leaf = findfirst(==(NaturalNotationTestLeaf), types)
            root = findfirst(==(NaturalNotationTestRoot), types)
            @test leaf !== nothing && root !== nothing && leaf < root
        end
    finally
        foreach(Base.delete_method, _find_natural_notation_test_methods())
    end

    @testset "the test leaves the method tables as it found them" begin
        @test isempty(_find_natural_notation_test_methods())
        @test Base.invokelatest(find_natural_file_format, NaturalNotationTestLeaf()) === nothing
        @test Base.invokelatest(make_natural_projection, NaturalNotationTestLeaf(), :syntax) === nothing
    end

    @testset "a format that is code turns a document into the Expr that runs it" begin
        call = parse_natural_text(:jl, "f(1, 2)")
        @test make_document_expression(call) == make_julia_expression(call)
        # Any other document runs as its own value.
        price = parse_natural_text(:json, "12")
        @test make_document_expression(price) == Expr(:toplevel, QuoteNode(price))
    end

    @testset "the natural text of a document is the string of its format" begin
        for (name, text) in ((:json, "{\"a\": [1, 2]}"), (:yml, "a: 1"), (:md, "# T\n\nA line."),
                             (:jl, "f(x) = x + 1"), (:math, "1 + 2"))
            document = parse_natural_text(name, text)
            format = find_natural_file_format(document)
            @test format === find_file_format(name)
            @test make_document_string(format, document) == print_natural_text(document)
        end
        @test !has_natural_parser(:txt) && !has_natural_parser(:pred) && !has_natural_parser(:png)
        @test has_natural_parser(:yml) && has_natural_parser(:markdown)
        @test_throws ErrorException parse_natural_text(:txt, "plain")
    end
end
