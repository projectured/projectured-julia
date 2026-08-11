"""
    ProjecturedYaml

The YAML source domain.

The document types, the text parser, and the syntax projection that renders
and edits them.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedYaml

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Yaml.jl")
include("YamlParser.jl")
include("YamlToSyntax.jl")

end # module ProjecturedYaml
