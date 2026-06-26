# ── Example registry for the opt-in ODBC + adaptagrams examples ──────────────
#
# Document builders are defined in document/{Database,DbCatalog}.jl; projection
# builders in projection/{DbCatalog,Graph,Sql}.jl. The shared engine-free builders
# (make_graph_document_example, make_sql_document_example, …) are imported from
# ProjecturedExample.

# Live-database catalog examples (ODBC).
const dbcatalog_example                = Example("dbcatalog",                make_dbcatalog_document_example,         make_dbcatalog_projection_example)
const dvdrental_catalog_example        = Example("dvdrental_catalog",        make_dvdrental_catalog_document_example, make_dbcatalog_projection_example)
const dbcatalog_widget_example         = Example("dbcatalog_widget",         make_dbcatalog_document_example,         make_dbcatalog_widget_projection_example)
const dvdrental_catalog_widget_example = Example("dvdrental_catalog_widget",  make_dvdrental_catalog_document_example, make_dbcatalog_widget_projection_example)

# Fully-walked catalog views — kept OUT of the `examples` sweep below (each forces
# a column query for every table, hammering the live database). Run directly.
const dvdrental_object_example         = Example("dvdrental_object",         make_dvdrental_catalog_document_example, make_dvdrental_object_projection_example)
const dvdrental_object_json_example    = Example("dvdrental_object_json",    make_dvdrental_catalog_document_example, make_dvdrental_object_json_projection_example)
const dvdrental_catalog_json_example   = Example("dvdrental_catalog_json",   make_dvdrental_catalog_document_example, make_dvdrental_catalog_json_projection_example)

# Live-query SQL → table (ODBC).
const sql_table_example                = Example("sql_table",                make_sql_document_example,               make_sql_table_projection_example)

# Native AdaptagramsEngine graph layout.
const graph_adaptagrams_example        = Example("graph_adaptagrams",        make_graph_document_example,             make_graph_adaptagrams_projection_example)
# LP-solved ConstraintLayout (TulipConstraintSolver). Reuses the engine-free
# constraint_layout document from ProjecturedExample with the real solver.
const constraint_layout_tulip_example  = Example("constraint_layout_tulip",  make_constraint_layout_document_example, make_constraint_layout_tulip_projection_example)
# The dvdrental entity-relationship diagram (live DB + native shim). Kept OUT of
# the `examples` sweep — needs a live database and the built ProjecturedAdaptagrams
# shim. Run directly: `run_example(dvdrental_relationship_example)`.
const dvdrental_relationship_example   = Example("dvdrental_relationship",
    make_dvdrental_relationship_graph_document_example,
    make_dvdrental_relationship_projection_example)

# Examples suitable for the enumeration sweep when a live database / native shim
# is available. The fully-walked dvdrental_* views and dvdrental_relationship are
# excluded (see above).
const examples = [
    dbcatalog_example,
    dvdrental_catalog_example,
    dbcatalog_widget_example,
    dvdrental_catalog_widget_example,
    sql_table_example,
    graph_adaptagrams_example,
    constraint_layout_tulip_example,
]

export make_dbcatalog_document_example, make_dvdrental_catalog_document_example,
       make_dvdrental_dbcatalog_document_example, explore_dbcatalog!,
       make_dvdrental_relationship_graph_document_example,
       make_database_adapter_example, setup_persons_table, teardown_persons_table
export make_dbcatalog_projection_example, make_dbcatalog_widget_projection_example,
       make_dvdrental_dbcatalog_projection_example, make_dvdrental_dbcatalog_widget_projection_example,
       make_dvdrental_object_projection_example, make_dvdrental_object_json_projection_example,
       make_dvdrental_catalog_json_projection_example,
       make_sql_table_projection_example,
       make_graph_adaptagrams_projection_example, make_dvdrental_relationship_projection_example,
       make_constraint_layout_tulip_projection_example
export dbcatalog_example, dvdrental_catalog_example, dbcatalog_widget_example, dvdrental_catalog_widget_example,
       dvdrental_object_example, dvdrental_object_json_example, dvdrental_catalog_json_example,
       sql_table_example, graph_adaptagrams_example, dvdrental_relationship_example,
       constraint_layout_tulip_example, examples
# Re-export the core runners/renderers so `using ProjecturedExtrasExample` is enough.
export Example, run_example, run_console_example, run_web_example,
       print_example, write_example_image, write_example_pdf, record_example_video
