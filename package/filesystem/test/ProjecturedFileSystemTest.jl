"""
    ProjecturedFileSystemTest

The FileSystem tier of the test-package DAG: the suites whose fixtures are filesystem
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_filesystem()`.
"""
module ProjecturedFileSystemTest

using Test
import ProjecturedBase
import ProjecturedFileSystem
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedFileSystemExample

const _SOURCES = (ProjecturedBase, ProjecturedFileSystem, ProjecturedKernel, ProjecturedVisual)

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

include("projection/FileSystemToSyntaxTest.jl")

"""
    test_filesystem_layering()

Static layered-architecture guard for `ProjecturedFileSystem`.
"""
function test_filesystem_layering()
    main = normpath(dirname(pathof(ProjecturedFileSystem)))
    check_layering(main, joinpath(main, "ProjecturedFileSystem.jl");
                   name = "filesystem",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFileSystem; all = true)
                         if isdefined(ProjecturedFileSystem, n) &&
                            getfield(ProjecturedFileSystem, n) isa Module &&
                            getfield(ProjecturedFileSystem, n) !== ProjecturedFileSystem &&
                            parentmodule(getfield(ProjecturedFileSystem, n)) !== ProjecturedFileSystem))
end

"""
    test_filesystem()

Run this package's whole suite: the layering guard and every filesystem test.
"""
function test_filesystem()
    @testset "ProjecturedFileSystem" begin
        test_filesystem_layering()
        test_filesystem_to_syntax()
    end
end

export test_filesystem, test_filesystem_layering, test_filesystem_to_syntax

end # module ProjecturedFileSystemTest
