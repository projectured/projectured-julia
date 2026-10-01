"""
    ProjecturedSqlExample

The Sql tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedSqlExample

import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedPlatform
import ProjecturedSql
using ProjecturedKernelExample
using ProjecturedPlatformExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPdf, ProjecturedSql)

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

include("../../../example/domain/sql/SqlDocumentExample.jl")
include("../../../example/domain/sql/SqlProjectionExample.jl")

export make_sql_document_example, make_sql_all_columns_document_example, make_sql_column_name_document_example
export make_sql_table_name_document_example, make_sql_scalar_value_document_example, make_sql_column_reference_document_example
export make_sql_table_expression_document_example, make_sql_comparison_document_example, make_sql_select_item_document_example
export make_sql_select_statement_document_example, make_sql_and_document_example, make_sql_or_document_example
export make_sql_not_document_example, make_sql_where_filter_condition_document_example, make_sql_where_clause_document_example
export make_sql_select_clause_document_example, make_sql_from_item_document_example, make_sql_from_clause_document_example
export make_sql_join_on_condition_document_example, make_sql_joined_from_item_document_example, make_sql_subquery_from_item_document_example
export make_sql_join_using_condition_document_example, make_sql_raw_expression_document_example
export make_sql_raw_condition_document_example
export make_sql_column_definition_document_example, make_sql_create_table_statement_document_example, make_sql_create_schema_statement_document_example
export make_sql_statement_list_document_example, make_sql_insert_statement_document_example, make_sql_update_assignment_document_example
export make_sql_update_statement_document_example, make_sql_insert_document_example, make_sql_update_document_example
export make_sql_nested_document_example, make_sql_syntax_projection_example, make_sql_insert_syntax_projection_example
export make_sql_update_syntax_projection_example, make_sql_nested_syntax_projection_example

end # module ProjecturedSqlExample
