"""
    ProjecturedOdbcExample

The ODBC opt-in example package (part of the example DAG's opt-in tier; see
plan/done/extras-example-split.md). It hosts the live-database examples —
`dbcatalog`, `dvdrental_catalog`, `dvdrental_object`, `sql_table` — plus the
`dvdrental_relationship` **document** builder (DB-catalog-derived; its
Adaptagrams-laid-out projection lives in `ProjecturedAdaptagramsExample`, which
imports the builder from here).

Reuses `ProjecturedExample`'s `Example` struct, runners, and engine-free
builders. Resolves through the root env; precompiles only where the ODBC
driver is installed.
"""
module ProjecturedOdbcExample

using Projectured
using ProjecturedOdbc          # OdbcConnectionPool, OdbcDatabaseAdapter, DatabaseInstanceToDbCatalog, SqlToCellTable, execute_db_raw, insert_into_db!, RawDatabaseResult
import ProjecturedExample: Example, run_example, run_console_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_database_instance_document_example, make_sql_document_example

# The bodies live in `example/adapter/odbc`, not beside this file:
# a package is a name and an include list.
const _PKG_DIR = normpath(joinpath(@__DIR__, "../../../example/adapter/odbc"))

include(joinpath(_PKG_DIR, "DatabaseDocumentExample.jl"))
include(joinpath(_PKG_DIR, "DbCatalogDocumentExample.jl"))
include(joinpath(_PKG_DIR, "DbCatalogProjectionExample.jl"))
include(joinpath(_PKG_DIR, "SqlProjectionExample.jl"))
include(joinpath(_PKG_DIR, "OdbcExamples.jl"))

export make_dbcatalog_document_example, make_dvdrental_catalog_document_example,
       make_dvdrental_dbcatalog_document_example, explore_dbcatalog!,
       make_dvdrental_relationship_graph_document_example,
       make_database_adapter_example, setup_persons_table, teardown_persons_table
export make_dbcatalog_projection_example,
       make_dvdrental_dbcatalog_projection_example,
       make_dvdrental_object_projection_example,
       make_sql_table_projection_example
export dbcatalog_example, dvdrental_catalog_example, dvdrental_object_example,
       sql_table_example, odbc_examples
# Re-export the core runners/renderers so `using ProjecturedOdbcExample` is enough.
export Example, run_example, run_console_example,
       print_example, write_example_image, write_example_pdf, record_example_video

end # module ProjecturedOdbcExample
