"""
    ProjecturedPivotExample

The Pivot tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedPivotExample

import ProjecturedPivot
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample

const _SOURCES = (ProjecturedPivot, ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

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

include("../../../example/domain/pivot/PivotDocumentExample.jl")

export make_pivot_sales_rows, make_pivot_document_example

end # module ProjecturedPivotExample
