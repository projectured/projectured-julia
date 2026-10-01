include("PdfWriterTest.jl")

"""
    test_pdf_layering()

Static layered-architecture guard for `ProjecturedPDF`.
"""
function test_pdf_layering()
    main = get_package_source_root(ProjecturedPDF)
    check_layering(main, pathof(ProjecturedPDF);
                   name = "pdf",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPDF; all = true)
                         if isdefined(ProjecturedPDF, n) &&
                            getfield(ProjecturedPDF, n) isa Module &&
                            getfield(ProjecturedPDF, n) !== ProjecturedPDF &&
                            parentmodule(getfield(ProjecturedPDF, n)) !== ProjecturedPDF))
end

"""
    test_pdf()

Run the whole suite of `ProjecturedPDF`: the layering guard and every test of the package.
"""
function test_pdf()
    @testset "ProjecturedPDF" begin
        test_pdf_layering()
        test_write_pdf()
    end
end

export test_pdf, test_pdf_layering, test_write_pdf
