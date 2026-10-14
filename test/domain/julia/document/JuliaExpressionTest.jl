# A Julia document becomes the `Expr` that Julia runs: the code it prints, with
# an object that a person pasted into it standing as that very object.

using Test

# An expression without its line numbers, which name where the text was parsed.
_strip_julia_lines(value) = value
_strip_julia_lines(expression::Expr) =
    Expr(expression.head, Any[_strip_julia_lines(argument) for argument in expression.args
                              if !(argument isa LineNumberNode)]...)

_julia_expression_of(document) = _strip_julia_lines(make_julia_expression(document))
_julia_expression_of(text::AbstractString) = _strip_julia_lines(Meta.parseall(text))

function test_julia_expression()
@testset "a Julia document becomes the Expr Julia runs" begin

    @testset "every Julia example becomes the Expr of its own text" begin
        examples = [getfield(ProjecturedJuliaExample, name) for name in names(ProjecturedJuliaExample)
                    if startswith(String(name), "make_julia_") &&
                       endswith(String(name), "_document_example") &&
                       !occursin("insertion", String(name))]
        # A fragment, such as the parameters of a `where`, is no code of its own.
        is_code(text) = !any(argument -> argument isa Expr && argument.head in (:error, :incomplete),
                             Meta.parseall(text).args)
        compared = 0
        for make in examples
            document = make()
            # An example that shows Julia code in a widget, such as a scroll pane, is
            # no Julia document of its own.
            document isa JuliaDocument || continue
            text = print_natural_text(document)
            is_code(text) || continue
            @test _julia_expression_of(document) == _julia_expression_of(text)
            compared += 1
        end
        @test compared >= 40
    end

    @testset "source keeps its meaning through the document" begin
        for source in ("x = 1 + 2", "f(a, b)", "map(x -> x^2, [1, 2, 3])",
                       "for i in 1:3\n    println(i)\nend", "if a\n    b\nelse\n    c\nend",
                       "s = \"a\\tb\"", "using Printf", "function f(x)\n    x + 1\nend",
                       "[i for i in 1:9 if iseven(i)]", "a.b[2]")
            @test _julia_expression_of(parse_julia(source)) == _julia_expression_of(source)
        end
    end

    @testset "a pasted object stands as that very object" begin
        object = PrimitiveString("the object")
        call = parse_julia("f(x, y)")
        call.arguments[2] = JuliaObject(object)
        expression = make_julia_expression(call)
        # The object is in the expression itself, in a QuoteNode, and not a copy.
        quoted = only(argument for argument in _strip_julia_lines(expression).args[1].args
                      if argument isa QuoteNode)
        @test quoted.value === object
        scratch = Module()
        Core.eval(scratch, :(f(a, b) = b))
        Core.eval(scratch, :(x = 1))
        @test Core.eval(scratch, expression) === object
        # A document that is not Julia at all is that object alone.
        @test Core.eval(scratch, make_julia_expression(object)) === object
    end

    @testset "a write of a document of another domain into Julia code makes a JuliaObject" begin
        object = PrimitiveString("the object")
        call = parse_julia("f(x, y)")
        # The write of an operation, as a paste makes it, wraps the document.
        written = convert_to_declared_type(call, JuliaDocument, object)
        @test written isa JuliaObject && written.value === object
        @test is_admitted_by_declared_type(call, JuliaDocument, object)
        write = ReplaceReferencedValueOperation(nothing, @reference(call, arguments[2]), object)
        evaluate_operation((document = call,), write)
        @test call.arguments[2] isa JuliaObject && call.arguments[2].value === object
        # A Julia node, and a place that takes any document, keep the value as it is.
        @test convert_to_declared_type(call, JuliaDocument, call.callee) === call.callee
        @test convert_to_declared_type(call, Document, object) === object
        # Program code writes what it means, so a bare object is refused there.
        @test_throws DeclaredTypeMismatchException (call.arguments[1] = object)
        # A hole offers no JuliaObject, because a JuliaObject needs its value.
        @test !insertable(JuliaObject)
    end

    @testset "a hole stands for the code typed into it" begin
        call = parse_julia("g(1)")
        hole = make_insertion_document(JuliaInsertion)
        hole.value = "2 + 3"
        call.arguments[1] = hole
        @test _julia_expression_of(call) == _julia_expression_of("g(2 + 3)")
        hole.value = "2 +"
        @test_throws ErrorException make_julia_expression(call)
    end
end
end
