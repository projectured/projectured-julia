function make_sql_syntax_projection_example(; measure=sdl_measure_text)
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
    content_projection = SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    SequentialProjection(
        # SqlSelectStatement → CellTable (executes against the instance via the pool)
        SqlToCellTable(pool, instance),
        # CellTable → TableTable
        CellTableToTable(),
        # TableTable → graphics, nesting the content projection for each cell
        NestingProjection(TableToGraphics(); recursion=content_projection),
    )
end
