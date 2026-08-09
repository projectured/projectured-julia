"""
    ProjecturedSequenceChartExample

The SequenceChart tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedSequenceChartExample

import ProjecturedBase
import ProjecturedKernel
import ProjecturedSequenceChart
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedSequenceChart, ProjecturedVisual)

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

include("document/SequenceChart.jl")
include("projection/SequenceChart.jl")

export make_sequencechart_document_example, make_sequencechart_vertical_document_example, make_sequencechart_linear_document_example
export make_sequencechart_large_document_example, make_sequencechart_inspector_document_example, make_sequence_chart_plot_document_example
export make_sequencechart_pair_document_example, make_sequencechart_pipeline_example, make_sequencechart_projection_example
export make_sequencechart_vertical_projection_example, make_sequencechart_linear_projection_example, make_sequencechart_large_projection_example
export make_sequencechart_composite_projection_example, make_sequencechart_pair_projection_example, make_sequencechart_inspector_projection_example

end # module ProjecturedSequenceChartExample
