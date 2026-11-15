"""
    ProjecturedGit

The git domain: the commits of a range, a commit, the change of one file and a
file at a revision as documents that the `git` program reads, their pages, and
the values of the output of git with the functions that read that output.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedGit

using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/domain/git/GitModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedGit`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .GitModule
for _n in names(GitModule)
    _n === :GitModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

# The workload of this package: the natural rows of this domain, which every
# first window of the display builds.
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    run_natural_rows_workload(GitModule)
end

end # module ProjecturedGit
