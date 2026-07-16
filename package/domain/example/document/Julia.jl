# ── Atomic Julia leaves — one meaningful instance each, for the catalog. ──
make_julia_bool_document_example()       = JuliaBool(true)
make_julia_break_document_example()      = JuliaBreak()
make_julia_char_document_example()       = JuliaChar('x')
make_julia_continue_document_example()   = JuliaContinue()
make_julia_float_document_example()      = JuliaFloat(3.14)
make_julia_identifier_document_example() = JuliaIdentifier("factorial")
make_julia_integer_document_example()    = JuliaInteger(42)
make_julia_string_document_example()     = JuliaString("hello")
make_julia_symbol_document_example()     = JuliaSymbol("foo")
make_julia_nothing_document_example()    = JuliaNothing()
make_julia_insertion_document_example()  = JuliaInsertion()

# Minimal non-empty compound (node) documents — one child each, for the catalog.
make_julia_binary_op_document_example()  = JuliaBinaryOp(:+, JuliaIdentifier("a"), JuliaIdentifier("b"))
make_julia_call_document_example()       = JuliaCall(JuliaIdentifier("f"), [JuliaIdentifier("x")])
make_julia_assignment_document_example() = JuliaAssignment(JuliaIdentifier("x"), JuliaInteger(1))
make_julia_block_document_example()      = JuliaBlock([JuliaInteger(1)])
make_julia_function_document_example()   = JuliaFunction(JuliaIdentifier("f"), [JuliaIdentifier("x")], JuliaBlock([JuliaIdentifier("x")]))
make_julia_array_document_example()      = JuliaArray([JuliaInteger(1)])
make_julia_begin_document_example()      = JuliaBegin(JuliaBlock([JuliaInteger(1)]))
make_julia_field_access_document_example() = JuliaFieldAccess(JuliaIdentifier("obj"), JuliaIdentifier("field"))
make_julia_for_iterator_document_example() = JuliaForIterator(JuliaIdentifier("i"), JuliaRange(JuliaInteger(1), JuliaInteger(10)))
make_julia_for_document_example()        = JuliaFor([make_julia_for_iterator_document_example()], JuliaBlock([JuliaIdentifier("i")]))
make_julia_if_document_example()         = JuliaIf(JuliaBool(true), JuliaBlock([JuliaInteger(1)]), JuliaBlock([JuliaInteger(2)]))
make_julia_index_document_example()      = JuliaIndex(JuliaIdentifier("a"), [JuliaInteger(1)])
make_julia_lambda_document_example()     = JuliaLambda([JuliaIdentifier("x")], JuliaIdentifier("x"))
make_julia_range_document_example()      = JuliaRange(JuliaInteger(1), JuliaInteger(10))
make_julia_return_document_example()     = JuliaReturn(JuliaInteger(1))
make_julia_ternary_document_example()    = JuliaTernary(JuliaBool(true), JuliaInteger(1), JuliaInteger(2))
make_julia_try_document_example()        = JuliaTry(JuliaBlock([JuliaInteger(1)]), nothing, JuliaBlock([JuliaInteger(2)]), nothing)
make_julia_tuple_document_example()      = JuliaTuple([JuliaInteger(1)])
make_julia_type_annotation_document_example() = JuliaTypeAnnotation(JuliaIdentifier("x"), JuliaIdentifier("Int"))
make_julia_unary_op_document_example()   = JuliaUnaryOp(:-, JuliaIdentifier("x"))
make_julia_using_document_example()      = JuliaUsing(:using, "Base")
make_julia_while_document_example()      = JuliaWhile(JuliaBool(true), JuliaBlock([JuliaInteger(1)]))

function make_julia_document_example()
    # function factorial(n)
    #     if n == 0
    #         1
    #     else
    #         n * factorial(n - 1)
    #     end
    # end
    JuliaFunction(
        JuliaIdentifier("factorial"),
        [JuliaIdentifier("n")],
        JuliaBlock([
            JuliaIf(
                JuliaBinaryOp(:(==), JuliaIdentifier("n"), JuliaInteger(0)),
                JuliaBlock([JuliaInteger(1)]),
                JuliaBlock([
                    JuliaBinaryOp(:*, JuliaIdentifier("n"),
                        JuliaCall(JuliaIdentifier("factorial"), [
                            JuliaBinaryOp(:-, JuliaIdentifier("n"), JuliaInteger(1))]))]))]))
end
