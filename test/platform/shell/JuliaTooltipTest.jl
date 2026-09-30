# The computed tooltips of Julia: a definition says what to pass, and a documented
# one says what it is for as well.

# The content of the one layer that the dwell binding of `document` answers, or
# `nothing` when the binding does not answer.
function _read_julia_tooltip(document)
    operation = read_gesture(document, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

function test_julia_tooltip()
@testset "a Julia definition says what it is" begin

_text(document) = join((document.elements[i].content for i in 1:length(document.elements)), "\n")
_function() = parse_julia("function add(a::Int, b)::Int\n    a + b\nend")

@testset "a function answers its signature" begin
    found = search_documents(_function(), node -> node isa JuliaFunction)
    @test !isempty(found)
    @test compute_julia_signature(first(found)) == "add(a::Int, b)::Int"
    @test _text(_read_julia_tooltip(first(found))) == "add(a::Int, b)::Int"
end

@testset "a documented function answers the prose as well" begin
    source = "\"\"\"\nAdd two numbers.\n\"\"\"\nfunction add(a, b)\n    a + b\nend"
    found = search_documents(parse_julia(source), node -> node isa JuliaDocstring)
    @test !isempty(found)
    answer = _text(_read_julia_tooltip(first(found)))
    # The signature first, because a caller reads what to pass before why.
    @test startswith(answer, "add(a, b)")
    @test occursin("Add two numbers.", answer)
end

@testset "each binding has the name that a command shows" begin
    names = [binding.name for binding in get_document_gesture_bindings(JuliaFunction)
             if binding.domain == "tooltip"]
    @test names == ["Show the signature"]
    names = [binding.name for binding in get_document_gesture_bindings(JuliaDocstring)
             if binding.domain == "tooltip"]
    @test names == ["Show the documentation"]
end

end # @testset
end # function
