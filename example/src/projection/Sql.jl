function make_sql_syntax_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_insert_syntax_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_update_syntax_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_nested_syntax_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_table_projection_example(; measure=sdl_measure_text,
                                             pool=OdbcConnectionPool(),
                                             instance=make_database_instance_document_example())
    # The query result cells are JSON documents; render them like the table example.
    w2g  = WidgetToGraphics(font_ubuntu_regular_24; measure=measure)
    json = SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    table_renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[JsonDocument => json],
    )))
    SequentialProjection(
        # SqlSelectStatement → CellTable (executes against the instance via the pool)
        SqlToCellTable(pool, instance),
        # CellTable → WidgetTable
        CellTableToWidgetTable(),
        # WidgetTable → graphics (GridLayout positions cells; the recursion renders
        # each JSON cell through the Json → Syntax → Text → Graphics chain).
        table_renderer,
    )
end
