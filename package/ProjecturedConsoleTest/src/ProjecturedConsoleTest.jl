"""
    ProjecturedConsoleTest

The test package of `ProjecturedConsole`: the console backend: a JSON document printed to the terminal, and the keys that drive it.
"""
module ProjecturedConsoleTest

using Test
import ProjecturedConsole
import ProjecturedJSON
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample
using ProjecturedJSONExample
using ProjecturedKernelTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedJSON, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/backend/console/ConsoleSuite.jl")

end # module ProjecturedConsoleTest
