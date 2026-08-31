function test_example(example::Example)
@testset "Examples" begin
    test_printer(example)
    test_reader(example)
    test_repl(example)
    test_position_navigation(example)
    test_typein(example)
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
