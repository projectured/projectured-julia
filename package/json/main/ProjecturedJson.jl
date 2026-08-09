"""
    ProjecturedJson

The JSON source domain: the document types (`JsonObject`, `JsonArray`,
`JsonString`, …), the text parser, the syntax projection that renders and edits
them, and the `JsonFile` wrapper that reads and writes `.json`.

Depends only on the three engine packages, and on no other domain.

The loop below binds every submodule of the packages below this one as a `const`,
so a source file here names a module exactly as the module names itself — inside
a submodule of `ProjecturedJson`, `..SyntaxModule` resolves through the
`const SyntaxModule = ProjecturedVisual.SyntaxModule` the loop wrote. The
`parentmodule` guard skips a package's re-exported aliases of a lower package, so
each module is bound once, under its own name.
"""
module ProjecturedJson

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Json.jl")
include("JsonParser.jl")
include("JsonToSyntax.jl")
include("JsonFile.jl")   # FileDocument wrapping a JsonDocument

end # module ProjecturedJson
