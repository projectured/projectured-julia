"""
    ProjecturedYAML

The YAML source domain.

The document types, the text parser, the syntax projection that renders and
edits them, and the `YamlFile` wrapper that reads and writes `.yaml`/`.yml`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedYAML

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

include("../../../source/domain/yaml/YamlModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedYAML`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .YamlModule
for _n in names(YamlModule)
    _n === :YamlModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedYAML
