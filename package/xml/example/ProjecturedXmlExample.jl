"""
    ProjecturedXmlExample

The Xml tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedXmlExample

import ProjecturedBase
import ProjecturedKernel
import ProjecturedVisual
import ProjecturedXml
import ProjecturedJson
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedBase, ProjecturedJson, ProjecturedKernel, ProjecturedVisual, ProjecturedXml)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/Xml.jl")
include("projection/Xml.jl")

include("document/Mixed.jl")

include("projection/Mixed.jl")

export make_mixed_document_example, make_mixed_projection_example, JsonXmlToSyntax
export make_xml_text_document_example, make_xml_element_document_example, make_xml_attribute_document_example
export make_xml_document_example, make_xml_projection_example

end # module ProjecturedXmlExample
