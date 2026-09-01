"""
    ProjecturedFileSystemTest

The FileSystem tier of the test-package DAG: the suites whose fixtures are filesystem
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_filesystem()`.
"""
module ProjecturedFileSystemTest

using Test
import ProjecturedFileSystem
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNatural
import ProjecturedFileFormat
import ProjecturedGestureLog
import ProjecturedGestureHelp
import ProjecturedInspector
import ProjecturedTooltip
import ProjecturedClipboard
import ProjecturedPane
import ProjecturedSyntax
import ProjecturedWidget
import ProjecturedText
import ProjecturedLayout
import ProjecturedScreen
import ProjecturedGraphics
import ProjecturedPlot
import ProjecturedVersioning
import ProjecturedFocus
import ProjecturedDragging
import ProjecturedReflection
import ProjecturedProjection
import ProjecturedComponent
import ProjecturedStyle
import ProjecturedSerialization
import ProjecturedDomain
import ProjecturedPrimitive
import ProjecturedCollection
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedFileSystemExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFileSystem, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/filesystem/projection/FileSystemToSyntaxTest.jl")

include("../../../test/filesystem/FilesystemSuite.jl")

end # module ProjecturedFileSystemTest
