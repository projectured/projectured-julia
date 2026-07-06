"""
    ProjecturedExtrasExample

Opt-in example documents/projections that depend on heavy external engines kept
out of `ProjecturedExample`:

- the live-database (ODBC) `dvdrental_*` / `dbcatalog*` / `sql_table` examples
  (need a reachable PostgreSQL and `ProjecturedOdbc`), and
- the native graph-layout examples `graph_adaptagrams` / `dvdrental_relationship`
  (need the `ProjecturedAdaptagrams` C++ shim built), and
- the LP-solved `constraint_layout_tulip` example (needs `ProjecturedTulip`,
  which pulls `Tulip` + `MathOptInterface`).

Splitting these out lets `ProjecturedExample` — and everything that only needs it,
including the per-domain example/test packages — precompile with no native build
and no database driver. Reuses `ProjecturedExample`'s `Example` struct, runners,
and the shared (engine-free) builders.
"""
module ProjecturedExtrasExample

using Projectured
using ProjecturedOdbc          # OdbcConnectionPool, OdbcDatabaseAdapter, DatabaseInstanceToDbCatalog, SqlToCellTable
using ProjecturedAdaptagrams   # AdaptagramsEngine
using ProjecturedTulip         # TulipConstraintSolver

import ProjecturedExample: Example, run_example, run_console_example, run_web_example,
                           print_example, write_example_image, write_example_pdf, record_example_video,
                           make_graph_document_example, make_graph_projection_example,
                           make_table_projection_example, make_mixed_projection_example,
                           make_database_instance_document_example,
                           make_sql_document_example,
                           make_constraint_layout_document_example, make_constraint_layout_projection_example

const _SRC_DIR = @__DIR__

include(joinpath(_SRC_DIR, "document", "Database.jl"))
include(joinpath(_SRC_DIR, "document", "DbCatalog.jl"))
include(joinpath(_SRC_DIR, "projection", "DbCatalog.jl"))
include(joinpath(_SRC_DIR, "projection", "Graph.jl"))
include(joinpath(_SRC_DIR, "projection", "Layout.jl"))
include(joinpath(_SRC_DIR, "projection", "Sql.jl"))
include(joinpath(_SRC_DIR, "Examples.jl"))

end # module ProjecturedExtrasExample
