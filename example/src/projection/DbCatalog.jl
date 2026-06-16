function make_dbcatalog_projection_example(; measure=sdl_measure_text,
                                             pool=OdbcConnectionPool())
    SequentialProjection(
        # DatabaseInstance → DbCatalogRdbms tree (queries lazily through the pool)
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
        # No DatabaseInstanceToDbCatalog step — the document is already a
        # fully explored DbCatalogRdbms, so we start at DbCatalogToSyntax.
        RecursiveProjection(DbCatalogToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = dbcatalog_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end
