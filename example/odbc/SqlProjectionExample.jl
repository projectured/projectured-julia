# The live-query SQL→table projection (`sql_table_example`). Split out of
# ProjecturedExample because it executes against a live database via
# `SqlToCellTable` over an ODBC `OdbcConnectionPool`. The static SQL→syntax
# projections stay in the base example package.

function make_sql_table_projection_example(; measure=FontFileMeasure(),
                                             pool=OdbcConnectionPool(),
                                             instance=make_database_instance_document_example())
    # The query result cells are base Primitive documents; render them through the
    # primitive → syntax → text → graphics chain.
    w2g       = WidgetToGraphics(font_ubuntu_regular_20; measure=measure)
    primitive = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            PrimitiveString => PrimitiveStringToSyntaxLeaf(),
            PrimitiveNumber => PrimitiveNumberToSyntaxLeaf(),
            PrimitiveBool   => PrimitiveBoolToSyntaxLeaf(),
        )),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    table_renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[PrimitiveDocument => primitive],
    )))
    ChainingProjection(
        # SqlSelectStatement → CellTable (executes against the instance via the pool)
        SqlToCellTable(pool, instance),
        # CellTable → WidgetTable (cells wrapped as Primitive documents)
        CellTableToWidgetTable(),
        # WidgetTable → graphics (GridLayout positions cells; the recursion renders
        # each Primitive cell through the Primitive → Syntax → Text → Graphics chain).
        table_renderer,
    )
end
