# ── ODBC opt-in example registry ─────────────────────────────────────────────
#
# Document builders in document/{Database,DbCatalog}.jl; projection builders in
# projection/{DbCatalog,Sql}.jl. Engine-free builders
# (make_sql_document_example, make_database_instance_document_example) are
# imported from ProjecturedExample.

# Live-database catalog examples.
const dbcatalog_example         = Example("dbcatalog",         make_dbcatalog_document_example,         make_dbcatalog_projection_example)
const dvdrental_catalog_example = Example("dvdrental_catalog", make_dvdrental_catalog_document_example, make_dbcatalog_projection_example)

# Fully-walked catalog view — kept OUT of the sweep (forces a column query for
# every table, hammering the live database). Run directly.
const dvdrental_object_example  = Example("dvdrental_object",  make_dvdrental_catalog_document_example, make_dvdrental_object_projection_example)

# Live-query SQL → table.
const sql_table_example         = Example("sql_table",         make_sql_document_example,               make_sql_table_projection_example)

# The ODBC tier's example slice (sweep-safe subset — the fully-walked
# dvdrental_object view is excluded, as above).
const odbc_examples = Example[
    dbcatalog_example,
    dvdrental_catalog_example,
    sql_table_example,
]
