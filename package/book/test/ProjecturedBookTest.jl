"""
    ProjecturedBookTest

The Book tier of the test-package DAG: the suites whose fixtures are book
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_book()`.
"""
module ProjecturedBookTest

using Test
import ProjecturedBase
import ProjecturedBook
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedBookExample

const _SOURCES = (ProjecturedBase, ProjecturedBook, ProjecturedKernel, ProjecturedVisual)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end


"""
    test_book_layering()

Static layered-architecture guard for `ProjecturedBook`.
"""
function test_book_layering()
    main = normpath(dirname(pathof(ProjecturedBook)))
    check_layering(main, joinpath(main, "ProjecturedBook.jl");
                   name = "book",
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
    end
end

export test_book, test_book_layering

end # module ProjecturedBookTest
