"""
    ProjecturedResearch

The research domain.

The record of a study: the work on one problem by the scientific approach, from
the question to the answer. Questions, sources, hypotheses, experiments,
analyses, results, evidence, decisions and answers, each with who made it and
when.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedResearch

using ProjecturedFormula
using ProjecturedGraph
using ProjecturedKernel
using ProjecturedMarkdown
using ProjecturedMath
using ProjecturedPlatform

for _src in (ProjecturedFormula, ProjecturedGraph, ProjecturedKernel, ProjecturedMarkdown, ProjecturedMath, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/domain/research/ResearchModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedResearch`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .ResearchModule
for _n in names(ResearchModule)
    _n === :ResearchModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

# The workload of this package: the natural rows of this domain, which every
# first window of the display builds, and the open of a file of this domain in
# the application window, a click, a key, a save, an undo and the name buffer.
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    run_natural_rows_workload(ResearchModule)
    run_file_workload(ResearchModule.ResearchQuestion)
end

end # module ProjecturedResearch
