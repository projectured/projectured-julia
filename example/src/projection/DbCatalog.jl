# ── Text-based pipeline: Domain → Syntax → Text → Graphics ──────────────

function make_dbcatalog_projection_example(; measure=sdl_measure_text,
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

function make_dvdrental_dbcatalog_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
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

function make_dbcatalog_widget_projection_example(; measure=sdl_measure_text,
                                                    pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToWidget(marker_eligible = dbcatalog_marker_eligible)),
        make_syntax_widget_graphics(measure=measure),
    )
end

function make_dvdrental_dbcatalog_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToWidget(marker_eligible = dbcatalog_marker_eligible)),
        make_syntax_widget_graphics(measure=measure),
    )
end
