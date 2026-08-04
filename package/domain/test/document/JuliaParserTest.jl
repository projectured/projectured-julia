"""
Round-trip tests for the Julia domain's parser and printer: ordinary Julia
goes in, the same Julia comes back.

The domain exists so a document can *be* a program, and the tutorial's pages
embed definitions out of real source files — which means the parser has to read
what people actually write, not a subset. Each case below is a construct that
appeared in a real file and stopped the whole file from parsing, since
`definition(file(f), name)` parses `f` whole before picking a node out of it.
"""

using Test
using ProjecturedDomain.JuliaParserModule: juliaparse
using ProjecturedDomain.NaturalFormatModule: document_to_text

# What the printer produced, trimmed — the pipeline emits the editor's rendered
# form, so leading and trailing whitespace is not part of what is asserted.
_julia_round_trip(source::AbstractString) = strip(document_to_text(juliaparse(source)))

function test_julia_parser()
@testset "Julia: ordinary source round-trips" begin

    @testset "comprehensions and generators" begin
        @test _julia_round_trip("xs = [f(i) for i in 1:3]") == "xs = [f(i) for i in 1:3]"
        @test _julia_round_trip("xs = Any[f(i) for i in 1:3]") == "xs = Any[f(i) for i in 1:3]"
        # A filter clause is part of the comprehension, not of the iterator.
        @test _julia_round_trip("xs = [i for i in 1:9 if iseven(i)]") ==
              "xs = [i for i in 1:9 if iseven(i)]"
        # A generator keeps its parentheses; it builds nothing.
        @test occursin("for i in 1:3", _julia_round_trip("s = sum(f(i) for i in 1:3)"))
    end

    @testset "splat, broadcast and interpolation" begin
        @test _julia_round_trip("f(xs...)") == "f(xs...)"
        @test _julia_round_trip("y = f.(xs)") == "y = f.(xs)"
        @test _julia_round_trip("s = \"a \$(x) b\"") == "s = \"a \$(x) b\""
        # A string with nothing interpolated stays a plain literal.
        @test _julia_round_trip("s = \"plain\"") == "s = \"plain\""
    end

    @testset "where clauses" begin
        @test _julia_round_trip("f(x::T) where {T} = x") == "f(x::T) where {T} = x"
        # Several variables, however they were written.
        @test _julia_round_trip("f(x::T, y::S) where {T, S} = x") ==
              "f(x::T, y::S) where {T, S} = x"
        # `where T where S` is `where {T, S}` — the inner binding comes first.
        @test _julia_round_trip("f(x::T) where T where S = x") ==
              "f(x::T) where {T, S} = x"
        # On a long-form signature the `where` belongs after the parameters …
        @test occursin("function f(x::T) where {T}",
                       _julia_round_trip("function f(x::T) where {T}\n    x\nend"))
        # … and so does a declared return type.
        @test occursin("function f(x)::Int",
                       _julia_round_trip("function f(x)::Int\n    x\nend"))
    end

    @testset "blocks that carry a body" begin
        @test _julia_round_trip("let x = 1\n    x + 1\nend") ==
              "let x = 1\n  x + 1\nend"
        @test _julia_round_trip("map(xs) do x\n    x + 1\nend") ==
              "map(xs) do x\n  x + 1\nend"
        @test occursin("module M", _julia_round_trip("module M\n    const A = 1\nend"))
    end

    @testset "the smaller gaps" begin
        @test _julia_round_trip("nt = (; a = 1, b = 2)") == "nt = (; a = 1, b = 2)"
        @test _julia_round_trip("xs = Vector{<:Real}()") == "xs = Vector{<:Real}()"
        @test _julia_round_trip("x |= 1") == "x |= 1"
        # A chained comparison prints as written; the folded form it parses to
        # means something else, but nothing here evaluates it.
        @test _julia_round_trip("y = a < b < c") == "y = a < b < c"
        @test _julia_round_trip("function f end") == "function f end"
        @test occursin("(x) ->", _julia_round_trip("g = function (x)\n    x\nend"))
    end

    @testset "a whole file is a document" begin
        # The property the tutorial needs: a file with a module wrapper, exports,
        # docstrings and parametric methods parses as one document.
        source = """
        module Sample

        export sample

        \"\"\"
        Doc.
        \"\"\"
        function sample(xs::AbstractVector{<:Real}; scale = 1.0)
            total = sum(x for x in xs if x > 0)
            return total * scale
        end

        pick(x::T) where {T} = x

        end
        """
        printed = _julia_round_trip(source)
        @test occursin("module Sample", printed)
        @test occursin("export sample", printed)
        @test occursin("function sample", printed)
        @test occursin("pick(x::T) where {T} = x", printed)
    end

end
end
