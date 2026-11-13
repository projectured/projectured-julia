"""
    ProjecturedGitExample

The Git tier of the example-package DAG: the repository that the examples and the
tests of the git domain read.

The registry that names the examples (`examples`, `atomic_documents`) and the
gallery that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The loop below rebuilds the flat `Projectured` namespace over this package's
sources.
"""
module ProjecturedGitExample

import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
import ProjecturedPlatform
import ProjecturedGit
using ProjecturedKernelExample
using ProjecturedPlatformExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF, ProjecturedGit)

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

include("../../../example/domain/git/GitRepositoryExample.jl")

export make_git_example_repository, make_git_commit_document_example, make_git_projection_example

end # module ProjecturedGitExample
