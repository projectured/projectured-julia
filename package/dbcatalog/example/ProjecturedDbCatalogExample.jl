"""
    ProjecturedDbCatalogExample

The DbCatalog tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedDbCatalogExample

import ProjecturedBase
import ProjecturedDbCatalog
import ProjecturedKernel
import ProjecturedVisual
import ProjecturedSql
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedBase, ProjecturedDbCatalog, ProjecturedKernel, ProjecturedSql, ProjecturedVisual)

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

include("document/DbCatalog.jl")

export make_db_catalog_column_document_example, make_db_catalog_table_document_example, make_db_catalog_schema_document_example
export make_db_catalog_database_document_example, make_db_catalog_rdbms_document_example

end # module ProjecturedDbCatalogExample
