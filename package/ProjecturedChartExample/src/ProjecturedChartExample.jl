"""
    ProjecturedChartExample

The Chart tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedChartExample

import ProjecturedChart
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedChart, ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPdf)

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

include("../../../example/domain/chart/ChartDocumentExample.jl")
include("../../../example/domain/chart/ChartProjectionExample.jl")

export make_chart_line_document_example, make_chart_bar_document_example, make_chart_histogram_document_example
export make_chart_scatter_document_example, make_chart_strip_document_example, make_chart_document_example
export make_chart_inspector_document_example, make_chart_plot_document_example, make_chart_pipeline_example
export make_chart_line_projection_example, make_chart_bar_projection_example, make_chart_histogram_projection_example
export make_chart_scatter_projection_example, make_chart_strip_projection_example, make_chart_projection_example
export make_chart_inspector_projection_example

end # module ProjecturedChartExample
