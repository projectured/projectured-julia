function make_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "projectured_test"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    # The catalog document is just a connection spec. No connection is opened
    # here — the DatabaseInstanceToDbCatalog projection queries the database
    # lazily (through its connection pool) when the tree is first forced, so
    # this maker stays safe to run at module-load / precompile time.
    DatabaseInstance(
        database=dbname,
        host=host,
        port=port,
        credentials=DatabaseCredentials(user=user, password=password),
    )
end

function make_dvdrental_catalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "dvdrental"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    # Pure connection spec — safe at module-load time. The
    # DatabaseInstanceToDbCatalog projection in the matching projection
    # example handles the lazy DB connection.
    DatabaseInstance(
        database=dbname,
        host=host,
        port=port,
        credentials=DatabaseCredentials(user=user, password=password),
    )
end

"""
    explore_dbcatalog!(rdbms::DbCatalogRdbms) -> DbCatalogRdbms

Materialize only the **first** table of the catalog (first database → first
schema → first table's columns), leaving every other table's `columns`
`CellVector` lazy. Enumerating each schema's table *list* is forced (so the
table names are known), but the per-table column queries — the expensive part —
are deferred until something forces them (e.g. expanding that table's card in
the widget pipeline). This makes the catalog a good fixture for **testing
laziness**: only one table is opened up front; the rest load on demand.
Returns `rdbms` for chaining.
"""
function explore_dbcatalog!(rdbms::DbCatalogRdbms)
    length(rdbms.databases) >= 1 || return rdbms
    db = rdbms.databases[1]
    length(db.schemas) >= 1 || return rdbms
    schema = db.schemas[1]
    length(schema.tables) >= 1 || return rdbms   # force the table list, not its columns
    table = schema.tables[1]
    length(table.columns)                        # open only the first table's columns
    rdbms
end

"""
    make_dvdrental_dbcatalog_document_example(; ...) -> DbCatalogRdbms

Connect to the dvdrental PostgreSQL sample database and return a fully
explored `DbCatalogRdbms` tree with all schemas, tables, and columns
materialized. Unlike `make_dbcatalog_document_example`, this returns the
catalog tree directly (not a `DatabaseInstance`), so its projection should
start at `DbCatalogToSyntax` rather than `DatabaseInstanceToDbCatalog`.
"""
function make_dvdrental_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "dvdrental"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")),
        pool=OdbcConnectionPool())
    inst = DatabaseInstance(
        database=dbname, host=host, port=port,
        credentials=DatabaseCredentials(user=user, password=password))
    proj = DatabaseInstanceToDbCatalog(pool)
    iomap = print_document(proj, nothing, inst, PrinterContext())
    explore_dbcatalog!(iomap.output)
end

# PostgreSQL spells many built-in types verbosely ("character varying",
# "timestamp without time zone"), which makes the card's Type column — and so the
# whole card — very wide (a `last_update timestamp without time zone` row alone is
# wider than the 260px card floor). Map the verbose spellings to the conventional
# short ER names so cards stay compact; unknown types pass through unchanged.
const _SHORT_TYPES = Dict(
    "timestamp without time zone" => "timestamp",
    "timestamp with time zone"    => "timestamptz",
    "time without time zone"      => "time",
    "time with time zone"         => "timetz",
    "character varying"           => "varchar",
    "character"                   => "char",
    "double precision"            => "double",
    "bit varying"                 => "varbit",
)
_short_type(t::AbstractString) = get(_SHORT_TYPES, t, t)

# One entity-relationship node: a WidgetCard titled with the table name whose
# content is a WidgetTable of the table's columns (Column | Type). Reading
# `t.name` / `t.columns` and `c.name` / `c.data_type` auto-derefs the @document
# Cells; iterating the `columns` CellVector yields the child DbCatalogColumn docs
# (and forces that table's lazy column query).
function _table_card(t::DbCatalogTable)
    rows  = [[c.name, _short_type(c.data_type)] for c in t.columns]
    table = WidgetTable(Point2D(0, 0), ["Column", "Type"], rows)
    WidgetCard(Point2D(0, 0); title=t.name, content=table, width=260)
end

"""
    make_dvdrental_relationship_graph_document_example(; schema="public", <db kwargs>, pool=OdbcConnectionPool()) -> GraphGraph

Build an entity-relationship `GraphGraph` of the dvdrental sample database: one
`GraphVertex` per catalog table (a `WidgetCard` titled with the table name whose
content is a `WidgetTable` of its `Column | Type` rows), and one directed
`GraphEdge` per foreign-key relationship (`from_table → to_table`), de-duplicated
so a multi-column FK draws a single edge.

A read-mostly *view*: it queries the live catalog tree and the live FK
constraints once (no back-mapping to the schema, by design). Needs a reachable
dvdrental database; pair it with `make_dvdrental_relationship_projection_example`
to lay it out (Adaptagrams) and render it. Kept out of the auto-test `examples`
registry — see `make_dvdrental_relationship_example` in `AdaptagramsExamples.jl`.
"""
function make_dvdrental_relationship_graph_document_example(;
        schema="public",
        dbname=get(ENV, "PGDATABASE", "dvdrental"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")),
        pool=OdbcConnectionPool())
    # Connection spec reused for the one-shot FK query below; the catalog tree is
    # built (and its per-table columns forced when the cards read them) through
    # the same pool.
    inst = DatabaseInstance(
        database=dbname, host=host, port=port,
        credentials=DatabaseCredentials(user=user, password=password))
    rdbms = make_dvdrental_dbcatalog_document_example(
        dbname=dbname, user=user, password=password, host=host, port=port, pool=pool)

    # First database → the requested schema.
    length(rdbms.databases) >= 1 || return GraphGraph(GraphVertex[], GraphEdge[])
    db = rdbms.databases[1]
    schema_doc = nothing
    for s in db.schemas
        if s.name == schema
            schema_doc = s
            break
        end
    end
    schema_doc === nothing && return GraphGraph(GraphVertex[], GraphEdge[])

    # One node (WidgetCard vertex) per table, indexed by table name for edge wiring.
    verts    = Dict{String, GraphVertex}()
    vertices = GraphVertex[]
    for t in schema_doc.tables
        v = GraphVertex(_table_card(t))
        verts[t.name] = v
        push!(vertices, v)
    end

    # Real foreign keys → directed edges. Reuse the SAME vertex objects (edges
    # reference vertices by identity, so a fresh GraphVertex would not match the
    # layout), de-dup (from → to) so multi-column FKs draw one edge, and drop
    # self-references (a self-loop has no meaningful ER edge).
    fks = with_connection(pool, inst) do adapter
        get_db_catalog_foreign_keys(adapter, schema)
    end
    edges = GraphEdge[]
    seen  = Set{Tuple{String, String}}()
    for fk in fks
        haskey(verts, fk.from_table) && haskey(verts, fk.to_table) || continue
        fk.from_table == fk.to_table && continue
        key = (fk.from_table, fk.to_table)
        key in seen && continue
        push!(seen, key)
        push!(edges, GraphEdge(verts[fk.from_table], verts[fk.to_table]; directed=true))
    end

    GraphGraph(vertices, edges)
end
