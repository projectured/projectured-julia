"""
    ProjecturedRST

The reStructuredText source domain.

The section and directive documents, the text parser, the syntax projection,
the file wrapper, and the layout projection that renders a page as a stack of
blocks. An RST section owns its blocks, so the layout takes two rules where
markdown takes one.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedRST

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

include("../../../source/domain/rst/RstModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedRST`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .RstModule
for _n in names(RstModule)
    _n === :RstModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedRST
