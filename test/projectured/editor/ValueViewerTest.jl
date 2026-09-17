# Tests for the window on any Julia value: what it draws for a struct, a
# dictionary, a vector and a value that refers to itself. Nothing opens a
# window; each test prints the view and checks what came out.

using Test

struct _ViewerPoint
    x::Int
    y::Int
end

mutable struct _ViewerLoop
    name::String
    self::Any
end

function test_value_viewer()
    @testset "value viewer" begin
        loop = _ViewerLoop("root", nothing)
        loop.self = loop
        values = ["a struct" => _ViewerPoint(1, 2),
                  "a dictionary" => Dict("a" => 1, "b" => [1, 2, 3]),
                  "a vector" => [_ViewerPoint(1, 1), _ViewerPoint(2, 2)],
                  "a value that refers to itself" => loop]

        @testset "the tree of $label draws" for (label, value) in values
            document, projection = make_value_viewer(value)
            @test print_document(projection, document).output isa GraphicsCanvas
        end

        @testset "the flat view of $label draws" for (label, value) in values
            document, projection = make_value_viewer(value; tree = false)
            @test document === value
            if value isa AbstractDict
                # `NaturalToGraphics` reflects a dictionary as the fields of its
                # implementation, and an open slot of the memory behind it holds
                # no value. The tree view above is what shows a dictionary.
                # @broken: the flat view of a dictionary raises.
                @test_broken print_document(projection, document).output isa GraphicsCanvas
            else
                @test print_document(projection, document).output isa GraphicsCanvas
            end
        end

        @testset "how much of the value the first frame holds" begin
            deep = _ViewerPoint(1, 2)
            wide = collect(1:100)
            # One level and twenty elements by default; a deeper or wider ask
            # holds more.
            one, projection = make_value_viewer(Dict("deep" => deep, "wide" => wide))
            two, _ = make_value_viewer(Dict("deep" => deep, "wide" => wide); depth = 3,
                                       elements = 50)
            text(document) = sprint(show, print_document(projection, document).output)
            @test length(text(two)) > length(text(one))
        end
    end
end
