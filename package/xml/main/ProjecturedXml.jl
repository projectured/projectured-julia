"""
    ProjecturedXml

The XML source domain.

The element and attribute documents, the text parser, the syntax projection,
and the `XmlFile` wrapper that reads and writes `.xml`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedXml

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

include("Xml.jl")
include("XmlParser.jl")
include("XmlToSyntax.jl")
include("XmlFile.jl")

end # module ProjecturedXml
