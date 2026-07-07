# The live-query SQL→table projection (`sql_table_example`). Split out of
# ProjecturedExample because it executes against a live database via
# `SqlToCellTable` over an ODBC `OdbcConnectionPool`. The static SQL→syntax
# projections stay in the base example package.

function make_sql_table_projection_example(; measure=truetype_measure_text,
                                             pool=OdbcConnectionPool(),
                                             instance=make_database_instance_document_example())
    # The query result cells are JSON documents; render them like the table example.
    w2g  = WidgetToGraphics(font_ubuntu_regular_20; measure=measure)
    json = ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    table_renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[JsonDocument => json],
    )))
    ChainingProjection(
        # SqlSelectStatement → CellTable (executes against the instance via the pool)
        SqlToCellTable(pool, instance),
        # CellTable → WidgetTable
        CellTableToWidgetTable(),
        # WidgetTable → graphics (GridLayout positions cells; the recursion renders
        # each JSON cell through the Json → Syntax → Text → Graphics chain).
        table_renderer,
    )
end
