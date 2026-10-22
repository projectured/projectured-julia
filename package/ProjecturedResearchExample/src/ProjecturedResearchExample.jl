"""
    ProjecturedResearchExample

The Research tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The loop below binds the namespace of this package's sources, as the other
example packages do.
"""
module ProjecturedResearchExample

import ProjecturedResearch
import ProjecturedKernel
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample

const _SOURCES = (ProjecturedResearch, ProjecturedPlatform, ProjecturedKernel)

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

include("../../../example/domain/research/ResearchDocumentExample.jl")

export make_research_question_document_example, make_research_source_document_example,
       make_research_expectation_document_example, make_research_hypothesis_document_example,
       make_research_experiment_document_example, make_research_analysis_document_example,
       make_research_result_document_example, make_research_evidence_document_example,
       make_research_decision_document_example, make_research_answer_document_example,
       make_research_study_document_example, make_research_projection_example,
       make_research_map_document_example

end # module ProjecturedResearchExample
