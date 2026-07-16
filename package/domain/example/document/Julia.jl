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
