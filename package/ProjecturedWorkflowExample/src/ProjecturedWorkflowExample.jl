"""
    ProjecturedWorkflowExample

The Workflow tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The loop below binds the namespace of this package's sources, as the other
example packages do.
"""
module ProjecturedWorkflowExample

import ProjecturedWorkflow
import ProjecturedKernel
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample

const _SOURCES = (ProjecturedWorkflow, ProjecturedPlatform, ProjecturedKernel)

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

include("../../../example/domain/workflow/WorkflowDocumentExample.jl")

export make_workflow_step_document_example, make_workflow_decision_document_example,
       make_workflow_entry_document_example, make_workflow_card_document_example,
       make_workflow_document_example, make_workflow_projection_example

end # module ProjecturedWorkflowExample
