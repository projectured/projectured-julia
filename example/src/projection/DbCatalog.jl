# ── Text-based pipeline: Domain → Syntax → Text → Graphics ──────────────

function make_dbcatalog_projection_example(; measure=truetype_measure_text,
                                             pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end

function make_dvdrental_dbcatalog_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end

# ── Generic-reflection pipeline: DatabaseInstance → DbCatalog → ObjectToSyntax →
#    Text → Graphics ───────────────────────────────────────────────────────────
#
# Unlike `make_dbcatalog_projection_example` (which uses the bespoke, *collapsible*
# `DbCatalogToSyntax`), this routes the catalog tree through the generic reflective
# `ObjectToSyntax`. `ObjectToSyntax` reflects every field and every `CellVector`
# element — so it forces the whole `databases → schemas → tables → columns`
# hierarchy, leaving the catalog **fully walked / expanded** (no collapse markers,
# every per-table column query realized). This is the "fully walked children
# state" view of the live dvdrental database, and is deliberately specific to the
# `dvdrental_object_example`. The document stays a lazy `DatabaseInstance`
# connection spec; `DatabaseInstanceToDbCatalog` opens the connection (through its
# pool) only when the tree is first forced at print time.
function make_dvdrental_object_projection_example(; measure=truetype_measure_text,
                                                    pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# ── Generic-reflection pipeline, JSON flavour: DatabaseInstance → DbCatalog →
#    ObjectToJson → JsonToSyntax → Text → Graphics ──────────────────────────────
#
# The JSON counterpart of `make_dvdrental_object_projection_example`. Instead of
# the bespoke s-expression form of `ObjectToSyntax`, the catalog is reflected by
# the generic `ObjectToJson` into a `JsonDocument` tree, then rendered through the
# regular JSON pipeline (`JsonToSyntax → SyntaxToText`). Like the `ObjectToSyntax`
# variant, `ObjectToJson` walks every field and every `CellVector` element — so
# the whole `databases → schemas → tables → columns` hierarchy is **fully walked /
# expanded** (every per-table column query forced, no collapse markers). This is
# the LLM-oriented JSON view of the live dvdrental database, deliberately specific
# to `dvdrental_object_json_example`. The document stays a lazy `DatabaseInstance`
# spec; the connection is opened (through its pool) only when the tree is first
# forced at print time.
function make_dvdrental_object_json_projection_example(; measure=truetype_measure_text,
                                                         pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(ObjectToJson()),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# ── Bespoke-projection pipeline, JSON flavour: DatabaseInstance → DbCatalog →
#    DbCatalogToJson → JsonToSyntax → Text → Graphics ────────────────────────────
#
# The DbCatalog-specific counterpart of `make_dvdrental_object_json_projection_example`.
# `DbCatalogToJson` is the domain-idiomatic JSON view: each level maps to a
# JsonObject of just its meaningful fields plus a nested array of its children
# (RDBMS → `{"host", "port", "databases":[…]}`, table → `{"name", "columns":[…]}`,
# etc.), without the generic projection's `"type"` markers and noise fields. Like
# the `ObjectToJson` / `ObjectToSyntax` variants it recurses through every child
# collection, so this pipeline **fully walks** the catalog — every per-table
# column query is forced, the whole `databases → schemas → tables → columns` tree
# rendered. Use `dvdrental_object_json_example` for the generic structural dump.
function make_dvdrental_catalog_json_projection_example(; measure=truetype_measure_text,
                                                          pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToJson()),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# ── Widget-based pipeline: Domain → Syntax → Widget → Graphics ──────────────
#
# `SyntaxToWidget` turns each indented catalog level (RDBMS, Schema, Table) into
# a collapsible `WidgetCard` and each leaf (column name, type) into embedded
# `TextText`, rendered by the shared widget+text graphics dispatch
# (`make_syntax_widget_graphics`, defined in the Json projection example). This
# replaces the old `TextToWidget` + `WidgetAndTextToGraphics` single-wrapper path.

function make_dbcatalog_widget_projection_example(; measure=truetype_measure_text,
                                                    pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToWidget(marker_eligible = dbcatalog_marker_eligible)),
        make_syntax_widget_graphics(measure=measure),
    )
end

function make_dvdrental_dbcatalog_widget_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToWidget(marker_eligible = dbcatalog_marker_eligible)),
        make_syntax_widget_graphics(measure=measure),
    )
end
