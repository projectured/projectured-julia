# An arranged document in the natural renderer: the filter and the sort of a
# collection show in what the renderer draws, whether it draws the collection as
# a stack of blocks or as reflected syntax, and the place is arranged once.

using ProjecturedKernel.CellModule: Cell
using ProjecturedPlatform.CollectionModule: CellVector

function test_arrangement_natural()
@testset "an arranged document in the natural renderer" begin
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    # Every text that the graphics draw, in the order of the drawing.
    function texts(node, found = String[])
        if node isa GraphicsCanvas
            foreach(element -> texts(element, found), node.elements)
        elseif node isa GraphicsViewport
            texts(node.content, found)
        elseif node isa GraphicsText
            push!(found, string(node.text))
        end
        found
    end
    keep_with(text) = ArrangementFilter(Any[ArrangementCondition(EmptyReference(), :contains, text)])
    descending() = ArrangementSort(Any[ArrangementSortKey(EmptyReference(), :descending)])

    @testset "a collection drawn as a stack of blocks" begin
        fruits = CellVector(Cell[Cell(PrimitiveString(name)) for name in ["pear", "apple", "fig", "grape"]])
        arranged = ArrangementDocument(fruits, ArrangementEntry[])
        io = print_document(natural, nothing, arranged, PrinterContext())
        @test texts(io.output) == ["pear", "apple", "fig", "grape"]
        push!(arranged.entries, ArrangementEntry(EmptyReference(), Any[keep_with("p"), descending()]))
        @test texts(io.output)[end - 2:end] == ["pear", "grape", "apple"]
    end

    @testset "the bar of chips, and a press on a chip" begin
        fruits = CellVector(Cell[Cell(PrimitiveString(name)) for name in ["pear", "apple", "fig", "grape"]])
        arranged = ArrangementDocument(fruits, ArrangementEntry[])
        io = print_document(natural, nothing, arranged, PrinterContext())
        push!(arranged.entries, ArrangementEntry(EmptyReference(), Any[keep_with("p"), descending()]))
        drawn = texts(io.output)
        @test drawn[1:4] == ["3 of 4", "value contains \"p\" ×", "↓ value ×", "Show all"]
        @test drawn[5:end] == ["pear", "grape", "apple"]
        # The × of the filter takes the filter away: one edit that names its
        # document, which a history records.
        function place_of(text)
            found = Ref{Any}(nothing)
            function walk(node, x, y)
                if node isa GraphicsCanvas
                    foreach(e -> walk(e, x + Int(node.x), y + Int(node.y)), node.elements)
                elseif node isa GraphicsViewport
                    walk(node.content, x + Int(node.x), y + Int(node.y))
                elseif node isa GraphicsText && string(node.text) == text
                    found[] = (x + Int(node.x), y + Int(node.y))
                end
            end
            walk(io.output, 0, 0)
            found[]
        end
        (x, y) = place_of("value contains \"p\" ×")
        change = read_intent(natural, nothing, Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0), nothing), io)
        operation = change isa Intent ? change.operation : change
        @test operation isa ReplaceReferencedValueOperation
        evaluate_operation(nothing, operation)
        @test length(arranged.entries[1].projections) == 1
        drawn = texts(io.output)
        @test drawn[1:3] == ["4 of 4", "↓ value ×", "Show all"]
        @test drawn[4:end] == ["pear", "grape", "fig", "apple"]
        # Show all of the last entry takes the arrangement away: the edit puts the
        # document in the place of the arrangement, which the place carries out.
        (x, y) = place_of("Show all")
        change = read_intent(natural, nothing, Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0), nothing), io)
        away = change isa Intent ? change.operation : change
        @test away isa ReplaceReferencedValueOperation && away.document === nothing && away.value === fruits
    end

    @testset "a collection drawn as reflected syntax" begin
        arranged = ArrangementDocument([3, 1, 4, 1, 5], ArrangementEntry[])
        shown() = join(texts(print_document(natural, nothing, arranged, PrinterContext()).output))
        @test occursin("3", shown()) && occursin("4", shown())
        push!(arranged.entries, ArrangementEntry(EmptyReference(), Any[descending()]))
        # Arranged once: the vector shows in descending order, every value once.
        # The bar says "5 of 5" before the values.
        digits = filter(isdigit, shown())
        @test digits == "55" * "54311"
    end
end
end
