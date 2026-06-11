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
