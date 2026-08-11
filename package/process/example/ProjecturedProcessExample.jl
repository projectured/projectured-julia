"""
    ProjecturedProcessExample

The Process tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedProcessExample

import ProjecturedGraph
import ProjecturedKernel
import ProjecturedProcess
import ProjecturedJulia
using ProjecturedKernelExample
using ProjecturedSubstrateExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedGraph, ProjecturedJulia, ProjecturedKernel, ProjecturedProcess)

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

include("document/Process.jl")
include("projection/Process.jl")

export make_process_step_document_example, make_process_sequence_document_example, make_process_decision_document_example
export make_process_while_document_example, make_process_foreach_document_example, make_process_return_document_example
export make_process_insertion_document_example, make_process_transmit_document_example, make_process_drain_document_example
export make_process_document_example, make_process_model_document_example, make_process_diagram_document_example
export make_process_projection_example, make_process_diagram_projection_example

end # module ProjecturedProcessExample
