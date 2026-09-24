# Fragment of `OdbcModule`.
#
import ProjecturedCollection.CollectionModule: CellVector
import ProjecturedDatabase.DatabaseModule: DatabaseInstance, DatabaseCredentials
import ProjecturedDbCatalog.DbCatalogModule: DbCatalogRdbms, DbCatalogDatabase,
                                  DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ProjecturedDatabase.DatabaseModule: get_db_catalog_databases, get_db_catalog_schemas,
                         get_db_catalog_tables, get_db_catalog_columns
import ProjecturedKernel.IoMapModule: SimpleIoMap
import ProjecturedKernel.ProjectionModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedKernel.CellModule: Computed, set_cell_function!
import ProjecturedKernel.ReferenceModule: EmptyReference
import ProjecturedKernel.ReferenceModule: var"@reference_case"
import ProjecturedKernel.ReferenceModule: var"@reference"


# ── Lazy tree builders ──────────────────────────────────────────────────────────
# Each helper returns a CellVector whose contents are recomputed lazily by
# querying through the pool. The pool + instance are captured by closure.
#
# A connection reads the schemas of its own database only, so each database of
# the list reads its schemas, tables and columns through an instance of its own.
# The pool opens a connection to that database the first time its schemas are
# read, that is when a person opens its group.

# The instance of `database` on the server of `instance`, with the same credentials.
_make_database_instance(instance::DatabaseInstance, database::String) =
    DatabaseInstance(database = database, host = instance.host, port = instance.port,
                     credentials = DatabaseCredentials(user = instance.credentials.user,
                                                       password = instance.credentials.password))

function _build_columns(pool, inst, schema_name::String, table_name::String)
    CellVector(Computed(() -> begin
        cols = with_connection(pool, inst) do adapter
            get_db_catalog_columns(adapter, schema_name, table_name)
        end
        DbCatalogColumn[DbCatalogColumn(c.name, c.data_type) for c in cols]
    end))
end

function _build_tables(pool, inst, schema_name::String)
    CellVector(Computed(() -> begin
        names = with_connection(pool, inst) do adapter
            get_db_catalog_tables(adapter, schema_name)
        end
        DbCatalogTable[DbCatalogTable(n, _build_columns(pool, inst, schema_name, n))
                       for n in names]
    end))
end

function _build_schemas(pool, inst, database_name::String)
    CellVector(Computed(() -> begin
        names = with_connection(pool, inst) do adapter
            get_db_catalog_schemas(adapter, database_name)
        end
        DbCatalogSchema[DbCatalogSchema(n, _build_tables(pool, inst, n))
                        for n in names]
    end))
end

function _build_databases(pool, inst)
    CellVector(Computed(() -> begin
        names = with_connection(pool, inst) do adapter
            get_db_catalog_databases(adapter)
        end
        DbCatalogDatabase[DbCatalogDatabase(n, _build_schemas(pool, _make_database_instance(inst, n), n))
                          for n in names]
    end))
end

# ── DatabaseInstanceToDbCatalog ─────────────────────────────────────────────────

struct DatabaseInstanceToDbCatalog <: Projection
    pool::OdbcConnectionPool
end

function print_document(p::DatabaseInstanceToDbCatalog,
                          recursion, inst::DatabaseInstance, ctx)
    rdbms = DbCatalogRdbms(inst.host, inst.port, _build_databases(p.pool, inst))
    iomap = SimpleIoMap(p, inst, rdbms)
    # Forward-project the DatabaseInstance's selection onto the freshly-built
    # catalog tree so DbCatalogToSyntax can render a cursor after set_selection!.
    # The instance stores its selection in DbCatalog-domain coordinates wrapped
    # as proj(p, …) (see map_reference_backward); the forward map unwraps it.
    set_cell_function!(getfield(rdbms, :selection), () -> begin
        sel = inst.selection
        sel === nothing && return nothing
        map_reference_forward(p, iomap, sel)
    end)
    iomap
end

# DatabaseInstanceToDbCatalog is opaque (School B): the DbCatalog tree is derived
# by querying the instance, so a selection has no structural counterpart in the
# DatabaseInstance itself. Backward wraps the catalog-domain reference as
# proj(p, …) so it can live on inst.selection; forward unwraps it. Mirrors the
# generic Projection default but strips the leading TypeReferenceStep checkpoint that
# set_selection! annotates onto the (now canonical) instance selection.
function map_reference_forward(p::DatabaseInstanceToDbCatalog, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), inner) => inner
    end
end

function map_reference_backward(p::DatabaseInstanceToDbCatalog, iomap, reference)
    reference isa EmptyReference && return @reference()
    @reference(iomap.input, proj(p, ^(reference)))
end
# No read_intent override — the generic default in Projection.jl handles
# ToggleCollapseOperation (pass-through) and ReplaceSelectionOperation (which now
# re-targets via the non-nothing map_reference_backward above).
