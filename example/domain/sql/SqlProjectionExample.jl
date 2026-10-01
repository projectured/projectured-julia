function make_sql_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_insert_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_update_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_sql_nested_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The live-query SQL→table projection (`sql_table_example`, `make_sql_table_projection_example`)
# lives in the opt-in `ProjecturedODBCExample` package — it executes against a
# live database via `SqlToCellTable` over an ODBC pool, so it carries the ODBC
# dependency out of the base example package.
