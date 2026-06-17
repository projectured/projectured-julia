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

# ── Widget-based pipeline: Domain → Syntax → Text → Widget → Graphics ───

function _dbcatalog_widget()
    TextToWidget(
        content_fill_color = StyleColor(245/255, 245/255, 245/255, 1.0), # light gray bg
        border       = Inset(1, 1, 1, 1),
        border_color = StyleColor(180/255, 180/255, 180/255, 1.0),       # medium gray border
        padding      = Inset(10, 10, 10, 10),
        padding_color = StyleColor(235/255, 235/255, 235/255, 1.0))      # slightly darker padding
end

function make_dbcatalog_widget_projection_example(; measure=sdl_measure_text,
                                                    pool=OdbcConnectionPool())
    SequentialProjection(
        DatabaseInstanceToDbCatalog(pool),
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        _dbcatalog_widget(),
        WidgetAndTextToGraphics(font_ubuntu_monospace_regular_24; measure=measure),
    )
end

function make_dvdrental_dbcatalog_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        _dbcatalog_widget(),
        WidgetAndTextToGraphics(font_ubuntu_monospace_regular_24; measure=measure),
    )
end
