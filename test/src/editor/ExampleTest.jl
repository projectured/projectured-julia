function test_example(example::Example)
@testset "Examples" begin
    test_printer(example.name, example.document, example.projection)
    test_reader(example.name, example.document, example.projection)
    test_selection(example.name, example.document, example.projection)
end
end

function test_examples()
    @testset "Examples" begin
        for example in examples
            @testset "$(example.name)" begin
                test_example(example)
            end
        end
    end
end
