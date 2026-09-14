module OdbcModule

# Imported to extend: this module adds a method to each of these.
import DBInterface
import ODBC
import ProjecturedDatabase.DatabaseModule: DatabaseAdapter, RawDatabaseResult,
                         connect_db!, close_db!, is_db_alive, get_db_rowid_column,
                         query_db, execute_db_raw,
                         insert_into_db!, update_db!, delete_from_db!,
                         get_db_catalog_databases, get_db_catalog_schemas,
                         get_db_catalog_tables, get_db_catalog_columns,
                         get_db_catalog_foreign_keys,
                         make_database_adapter
import Tables

export OdbcDatabaseAdapter
export OdbcConnectionPool, with_connection, get_dsn, close_pool!
export SqlToCellTable
export DatabaseInstanceToDbCatalog


include("OdbcAdapter.jl")
include("ConnectionPool.jl")
include("SqlToCellTable.jl")
include("DatabaseInstanceToDbCatalog.jl")

end # module
