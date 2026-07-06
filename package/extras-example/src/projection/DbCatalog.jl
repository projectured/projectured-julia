# ── Text-based pipeline: Domain → Syntax → Text → Graphics ──────────────

function make_dbcatalog_projection_example(; measure=truetype_measure_text,
                                             pool=OdbcConnectionPool())
    ChainingProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_20, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_20, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end

function make_dvdrental_dbcatalog_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_20, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_20, color_default),
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
    ChainingProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

