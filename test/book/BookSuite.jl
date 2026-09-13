"""
    test_book_layering()

Static layered-architecture guard for `ProjecturedBook`.
"""
function test_book_layering()
    main = get_package_source_root(ProjecturedBook)
    check_layering(main, pathof(ProjecturedBook);
                   name = "book",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["BookDocument.jl"]),
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedBook; all = true)
                         if isdefined(ProjecturedBook, n) &&
                            getfield(ProjecturedBook, n) isa Module &&
                            getfield(ProjecturedBook, n) !== ProjecturedBook &&
                            parentmodule(getfield(ProjecturedBook, n)) !== ProjecturedBook))
end

"""
    test_book()

Run this package's whole suite: the layering guard and every book test.
"""
function test_book()
    @testset "ProjecturedBook" begin
        test_book_layering()
        test_book_to_syntax()
    end
end

export test_book, test_book_layering, test_book_to_syntax
