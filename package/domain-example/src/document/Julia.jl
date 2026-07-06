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
