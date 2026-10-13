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
using ProjecturedJulia.JuliaModule: parse_julia, JuliaBlock, JuliaToplevel, JuliaDocstring,
                                    JuliaComment, JuliaMultilineComment, JuliaEndOfLineComment
using ProjecturedPlatform.NaturalModule: print_natural_text

# What the printer produced, trimmed — the pipeline emits the editor's rendered
# form, so leading and trailing whitespace is not part of what is asserted.
_julia_round_trip(source::AbstractString) = strip(print_natural_text(parse_julia(source)))

# Whether the print of `source` is Julia that parses, and that prints the same
# text again.
function _julia_prints_back(source::AbstractString)
    printed = print_natural_text(parse_julia(source))
    !any(a -> Meta.isexpr(a, (:error, :incomplete)), Meta.parseall(printed).args) &&
        print_natural_text(parse_julia(printed)) == printed
end

# Whether the statements of `block`, or of the block that `source` parses to, are
# of `types`, in order.
function _has_julia_statements(block::JuliaBlock, types...)
    statements = [s for s in block.statements]
    length(statements) == length(types) && all(map(isa, statements, collect(types)))
end
_has_julia_statements(source::AbstractString, types...) =
    (document = parse_julia(source); document isa JuliaBlock && _has_julia_statements(document, types...))

# The statements of the body of the one struct in `text`, as Julia parses them,
# with no line numbers. A docstring loses the break at its end, which a single
# quote does not write and a triple quote does.
function _julia_struct_body(text::AbstractString)
    definition = only(a for a in Meta.parseall(text).args if !(a isa LineNumberNode))
    Any[a isa AbstractString ? rstrip(a, '\n') : a for a in definition.args[3].args
        if !(a isa LineNumberNode)]
end

function test_julia_parser()
@testset "Julia: ordinary source round-trips" begin

    @testset "a docstring keeps any text through a print and a parse" begin
        for text in ("Costs \$5.\n", "A \\ backslash.\n", "Three \"\"\" quotes.\n",
                     "Four \"\"\"\" quotes, and \"two\".\n", "Ends in a quote\"")
            document = JuliaDocstring(text, parse_julia("f() = 1"))
            again = parse_julia(print_natural_text(document))
            @test again isa JuliaDocstring && rstrip(again.text, '\n') == rstrip(text, '\n')
        end
    end

    @testset "a string before a field of a struct is the docstring of the field" begin
        source = "struct Point\n    \"\"\"\n    The x of the point.\n    \"\"\"\n    x::Float64\n" *
                 "    \"The y.\"\n    y::Float64\n    \"Not a docstring.\"\nend"
        point = parse_julia(source)
        statements = [s for s in point.body.statements]
        @test length(statements) == 3
        @test statements[1] isa JuliaDocstring && statements[1].text == "The x of the point.\n"
        @test statements[2] isa JuliaDocstring && statements[2].text == "The y."
        @test !(statements[3] isa JuliaDocstring)
        printed = print_natural_text(point)
        @test print_natural_text(parse_julia(printed)) == printed
        @test _julia_struct_body(printed) == _julia_struct_body(source)
    end

    @testset "comprehensions and generators" begin
        @test _julia_round_trip("xs = [f(i) for i in 1:3]") == "xs = [f(i) for i in 1:3]"
        @test _julia_round_trip("xs = Any[f(i) for i in 1:3]") == "xs = Any[f(i) for i in 1:3]"
        # A filter clause is part of the comprehension, not of the iterator.
        @test _julia_round_trip("xs = [i for i in 1:9 if iseven(i)]") ==
              "xs = [i for i in 1:9 if iseven(i)]"
        # A generator keeps its parentheses; it builds nothing.
        @test occursin("for i in 1:3", _julia_round_trip("s = sum(f(i) for i in 1:3)"))
    end

    @testset "a power is an infix operator, and it binds to the right" begin
        @test _julia_round_trip("p = (1 - rho) * rho^n / (1 - rho^(n + 1))") ==
              "p = (1 - rho) * rho ^ n / (1 - rho ^ (n + 1))"
        @test _julia_round_trip("2^3^2") == "2 ^ 3 ^ 2"
        @test _julia_round_trip("(2^3)^2") == "(2 ^ 3) ^ 2"
        @test _julia_round_trip("-x^2") == "-(x ^ 2)"
    end

    @testset "every infix operator prints between its operands" begin
        @test _julia_round_trip("JsonObject(\"name\" => JsonString(\"Frank\"))") ==
              "JsonObject(\"name\" => JsonString(\"Frank\"))"
        @test _julia_round_trip("ok = x in xs") == "ok = x in xs"
        @test _julia_round_trip("ok = x isa Int") == "ok = x isa Int"
        @test _julia_round_trip("r = a % b") == "r = a % b"
        @test _julia_round_trip("y = x |> f |> g") == "y = x |> f |> g"
        @test _julia_round_trip("y = a .+ b") == "y = a .+ b"
        # `a + b + c` is one call of `+` with three operands.
        @test _julia_round_trip("s = a + b + c") == "s = a + b + c"
        @test _julia_round_trip("s = a * b * c * d") == "s = a * b * c * d"
        @test _julia_round_trip("s = a + (b + c)") == "s = a + (b + c)"
        # A pair binds to the right, and more loosely than a comparison.
        @test _julia_round_trip("p = a => b => c") == "p = a => b => c"
        @test _julia_round_trip("p = (a => b) => c") == "p = (a => b) => c"
        @test _julia_round_trip("p = a == b => c") == "p = a == b => c"
        # `&&`, `||` and `-` keep the parentheses that their grouping needs.
        @test _julia_round_trip("y = !(a || b)") == "y = !(a || b)"
        @test _julia_round_trip("y = (a || b) && c") == "y = (a || b) && c"
        @test _julia_round_trip("y = a - (b - c)") == "y = a - (b - c)"
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

    @testset "an infix operator prints between its operands" begin
        for code in ("d isa Workspace", "x in xs", "x ∈ xs", "x ∉ xs", "a => b", "x |> f",
                     "a % b", "a ÷ b", "a .+ b", "a .== b",
                     "first(search_documents(editor.document, d -> d isa JsonFile))")
            @test _julia_round_trip(code) == code
        end
        # The parentheses follow the precedence and the associativity of Julia.
        for code in ("a => b => c", "(a => b) => c", "x |> f |> g", "x |> (f |> g)",
                     "a + b in xs", "a in (xs == ys)", "a .+ b .* c", "(a .+ b) .* c",
                     "k => a || b", "(k => a) || b")
            @test _julia_round_trip(code) == code
        end
    end

    @testset "a comment after a statement on its line is the end-of-line comment of that statement" begin
        for (source, subject) in (("x = 1  # c", JuliaAssignment), ("f() = 1  # c", JuliaAssignment),
                                  ("x = 1;  # c", JuliaToplevel), ("a = 1; b = 2  # c", JuliaToplevel),
                                  ("function f()\n    1\nend  # c", JuliaFunction))
            document = parse_julia(source)
            @test document isa JuliaEndOfLineComment && document.subject isa subject && document.text == " c"
            @test _julia_prints_back(source)
        end
        @test parse_julia("x = 1;  # c").subject.trailing_semicolon
        @test _julia_round_trip("x = 1  # c") == "x = 1  # c"
        @test _julia_round_trip("x = 1;  # c") == "x = 1;  # c"
        # The two spaces before the `#` are the printer's: the document keeps no column.
        @test _julia_round_trip("x = 1 # c") == "x = 1  # c"
        module_ = parse_julia("module M\nf() = 1\nend # module M")
        @test module_ isa JuliaEndOfLineComment && module_.subject isa JuliaModuleDefinition
        @test endswith(_julia_round_trip("module M\nf() = 1\nend # module M"), "end  # module M")
        @test endswith(_julia_round_trip("module M\nf() = 1\nend"), "\nend")
    end

    @testset "a comment on a line of its own is a statement between the statements" begin
        @test _has_julia_statements("# c\nx = 1", JuliaComment, JuliaAssignment)
        @test _has_julia_statements("x = 1\n# c", JuliaAssignment, JuliaComment)
        @test _has_julia_statements(parse_julia("function f()\n    # TODO\nend").body, JuliaComment)
        @test _has_julia_statements(parse_julia("function f()\n    x\n    # last\nend").body, JuliaIdentifier, JuliaComment)
        struct_ = parse_julia("struct S\n    # the x\n    x::Int  # meters\nend")
        @test _has_julia_statements(struct_.body, JuliaComment, JuliaEndOfLineComment)
        @test parse_julia("# c").text == " c"
        @test _julia_round_trip("#!/usr/bin/env julia\nx = 1")[1:20] == "#!/usr/bin/env julia"
        # A `#` in a string is no comment.
        @test parse_julia("s = \"a # b\"") isa JuliaAssignment
        # Julia does not attach a docstring across a comment, so the three are statements.
        @test _has_julia_statements("\"doc\"\n# between\nf(x) = x", JuliaString, JuliaComment, JuliaAssignment)
        for source in ("# c\nx = 1", "function f()\n    # TODO\nend", "struct S\n    # the x\n    x::Int  # meters\nend",
                       "\"doc\"\n# between\nf(x) = x", "#!/usr/bin/env julia\nx = 1")
            @test _julia_prints_back(source)
        end
    end

    @testset "a comment on the header line of a block is the first statement of the body" begin
        @test _has_julia_statements(parse_julia("function f(x)  # c\n    x\nend").body, JuliaComment, JuliaIdentifier)
        branch = parse_julia("if a  # why\n    1\nelse  # other\n    2\nend")
        @test _has_julia_statements(branch.then_branch, JuliaComment, JuliaInteger)
        @test _has_julia_statements(branch.else_branch, JuliaComment, JuliaInteger)
        @test branch.then_branch.statements[1].text == " why"
        @test _julia_prints_back("if a  # why\n    1\nelse  # other\n    2\nend")
    end

    @testset "a comment that no statement list holds moves before its statement" begin
        @test _has_julia_statements("g(a,  # c\n  b)", JuliaComment, JuliaCall)
        @test _has_julia_statements("v = [1,  # one\n     2]", JuliaComment, JuliaAssignment)
        @test _has_julia_statements("let a = 1,  # c\n    b = 2\n    a + b\nend", JuliaComment, JuliaLet)
        moved = parse_julia("g(a,  # one\n  b,  # two\n  c)")
        @test _has_julia_statements(moved, JuliaComment, JuliaComment, JuliaCall)
        @test [moved.statements[1].text, moved.statements[2].text] == [" one", " two"]
        @test length(moved.statements[3].arguments) == 3
        for source in ("g(a,  # c\n  b)", "v = [1,  # one\n     2]", "g(a,  # one\n  b,  # two\n  c)")
            @test _julia_prints_back(source)
        end
    end

    @testset "a real file keeps every comment, in order" begin
        # Files of this repository that the printer prints back exactly, with
        # many comments, and with a `#` inside a string.
        root = joinpath(@__DIR__, "..", "..", "..", "..")
        for path in ("source/domain/julia/JuliaCodePieces.jl", "source/domain/julia/JuliaExpression.jl",
                     "source/domain/julia/JuliaFile.jl", "source/platform/syntax/FaultToSyntax.jl")
            text = read(joinpath(root, path), String)
            printed = print_natural_text(parse_julia(text))
            missing_comments = String[]
            position = 1
            for token in Base.JuliaSyntax.tokenize(text)
                Base.JuliaSyntax.kind(token) == Base.JuliaSyntax.K"Comment" || continue
                comment = String(view(codeunits(text), Int(first(token.range)):Int(last(token.range))))
                found = findnext(comment, printed, position)
                found === nothing ? push!(missing_comments, comment) :
                                    (position = nextind(printed, last(found)))
            end
            @test missing_comments == String[]
            @test print_natural_text(parse_julia(printed)) == printed
        end
    end

    @testset "a multiline comment keeps its lines, and its indentation is the code's" begin
        @test _has_julia_statements("x = 1 #= c =#", JuliaAssignment, JuliaMultilineComment)
        body = parse_julia("function f()\n    #= a\n       b =#\nend").body
        @test _has_julia_statements(body, JuliaMultilineComment)
        @test body.statements[1].text == " a\n   b "
        @test parse_julia("#= nested #= inner =# outer =#").text == " nested #= inner =# outer "
        for source in ("x = 1 #= c =#", "function f()\n    #= a\n       b =#\nend")
            @test _julia_prints_back(source)
        end
    end

    @testset "statements on one line keep their semicolons" begin
        @test _julia_round_trip("a; b") == "a; b"
        @test _julia_round_trip("x = 1;") == "x = 1;"
        @test _julia_round_trip("a; b;") == "a; b;"
        @test _julia_round_trip("push!(xs, 1);  # the list") == "push!(xs, 1);  # the list"
        @test parse_julia("x = 1;") isa JuliaToplevel
        @test parse_julia("x = 1;").trailing_semicolon
        @test !parse_julia("a; b").trailing_semicolon
        # A line of its own in a block of lines keeps its `;` too.
        @test _julia_round_trip("x = 1\ny = 2;") == "x = 1\n  y = 2;"
        # A `;` inside a `begin` block separates statements of that block.
        @test parse_julia("begin a; b end") isa JuliaBlock
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
