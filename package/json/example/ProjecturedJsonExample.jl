"""
    ProjecturedJsonExample

The Json tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedJsonExample

import ProjecturedJson
import ProjecturedKernel
using ProjecturedKernelExample
using ProjecturedSubstrateExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedJson, ProjecturedKernel)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/Json.jl")
include("projection/Json.jl")

export make_json_document_example, make_json_null_document_example, make_json_bool_document_example
export make_json_number_document_example, make_json_insertion_document_example, make_json_string_document_example
export make_json_array_document_example, make_json_object_document_example, make_json_object_entry_document_example
export make_json_projection_example, make_json_console_projection_example, make_json_sorted_projection_example
export make_json_null_projection_example, make_json_string_projection_example

end # module ProjecturedJsonExample
