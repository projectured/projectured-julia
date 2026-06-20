# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/SyntaxToWidgetTest.jl
#
# Unit tests for the Syntax → Widget projection (`SyntaxToWidget`): the
# structure-as-widgets / content-as-text path. Covers the structural mapping
# (indented node → collapsible WidgetCard, inline node → HorizontalLayout, leaf →
# embedded TextText), leaf selection forward/backward mapping, and the
# reader-driven collapse retargeting (ToggleCollapseOperation widget → node).
# ═══════════════════════════════════════════════════════════════════════════

function test_syntax_to_widget()

# A small JSON-shaped tree:  { "a": 1 }
#   root (indented object)
#     pair (inline ":")
#       key  leaf  "a"
#       value leaf  1
_make_tree() = begin
    key  = SyntaxLeaf("\"", "\"", "a")
    val  = SyntaxLeaf("", "", "1")
    pair = SyntaxNode(TextString(""), TextString(""), TextString(": "),
                      SyntaxDocument[key, val]; indentation=0)
    root = SyntaxNode(TextString("{"), TextString("}"), TextString(","),
                      SyntaxDocument[pair]; indentation=2)
    (root, pair, key, val)
end

_proj() = RecursiveProjection(SyntaxToWidget())

@testset "indented node → collapsible WidgetCard" begin
    root, _, _, _ = _make_tree()
    iomap = projection_print(_proj(), root)
    card = iomap.output
    @test card isa WidgetCard
    # Header (title) is the open-delimiter line; body holds the children + close.
    @test card.title isa HorizontalLayout
    @test card.content isa VerticalLayout
    # Expanded body: one entry per child (the inline pair) plus the close
    # delimiter span.
    @test length(card.content.children) == 2
end

@testset "inline node → HorizontalLayout of leaves" begin
    _, pair, _, _ = _make_tree()
    iomap = projection_print(_proj(), pair)
    line = iomap.output
    @test line isa HorizontalLayout
    # No open/close delimiter content on the pair node, separator ": " between
    # the two leaves: [key, sep, value].
    @test length(line.children) == 3
    @test line.children[1] isa TextText   # key leaf
    @test line.children[2] isa TextText   # separator
    @test line.children[3] isa TextText   # value leaf
end

@testset "leaf → embedded TextText with three spans" begin
    _, _, key, _ = _make_tree()
    iomap = projection_print(SyntaxLeafToWidget(), nothing, key, PrinterContext())
    tt = iomap.output
    @test tt isa TextText
    @test length(tt.elements) == 3
    @test tt.elements[1].content == "\""
    @test tt.elements[2].content == "a"
    @test tt.elements[3].content == "\""
end

@testset "leaf selection maps forward (cursor wires into the TextText)" begin
    _, _, key, _ = _make_tree()
    # Place a cursor at char 1 of the value span.
    set_selection!(key, @reference value{1})
    iomap = projection_print(SyntaxLeafToWidget(), nothing, key, PrinterContext())
    sel = iomap.output.selection
    # value{1} → elements[2].content{1}
    @test sel == (@reference elements[2].content{1})
end

@testset "leaf reader maps a ReplaceSelectionOperation back to the leaf domain" begin
    _, _, key, _ = _make_tree()
    iomap = projection_print(SyntaxLeafToWidget(), nothing, key, PrinterContext())
    # A Text-domain selection on the value span → leaf `.value{2}`.
    op = projection_read(SyntaxLeafToWidget(), iomap,
                         ReplaceSelectionOperation(@reference elements[2].content{2}))
    @test op isa ReplaceSelectionOperation
    @test op.path == (@reference value{2})
end

@testset "leaf reader retypes nothing for delimiter-span edits" begin
    _, _, key, _ = _make_tree()
    iomap = projection_print(SyntaxLeafToWidget(), nothing, key, PrinterContext())
    # `.elements[span_idx].content[s:e]` reference for a span edit.
    span_range_ref(span_idx, s, e) =
        ConcreteReferencePath(FieldReference("elements"),
          ConcreteReferencePath(RangeReference(span_idx - 1, span_idx),
            ConcreteReferencePath(FieldReference("content"),
              ConcreteReferencePath(RangeReference(s, e), EmptyReferencePath()))))
    # An edit into the open delimiter span (span 1) is declined (only the value
    # span, span 2, is editable here).
    op = projection_read(SyntaxLeafToWidget(), iomap,
                         StringReplaceRangeOperation(span_range_ref(1, 0, 1), "x"))
    @test op === nothing
    # An edit into the value span maps to `.value[1:2]`.
    op2 = projection_read(SyntaxLeafToWidget(), iomap,
                          StringReplaceRangeOperation(span_range_ref(2, 1, 2), "x"))
    @test op2 isa StringReplaceRangeOperation
    @test op2.replacement == "x"
end

@testset "collapse: ToggleCollapseOperation on the card retargets to the node" begin
    root, _, _, _ = _make_tree()
    iomap = projection_print(_proj(), root)
    card = iomap.output
    # The WidgetCard graphics reader emits ToggleCollapseOperation(card); the
    # SyntaxToWidget reader walks the iomap and turns the widget target into the
    # owning SyntaxNode so the editor flips `node.collapsed`.
    op = projection_read(_proj(), iomap, ToggleCollapseOperation(card))
    @test op isa ToggleCollapseOperation
    @test op.target === root
end

@testset "collapse: a nested card retargets to its own node" begin
    # Wrap the object in an outer indented array so there are two cards.
    inner_root, _, _, _ = _make_tree()
    outer = SyntaxNode(TextString("["), TextString("]"), TextString(","),
                       SyntaxDocument[inner_root]; indentation=1)
    iomap = projection_print(_proj(), outer)
    outer_card = iomap.output
    @test outer_card isa WidgetCard
    # The inner card sits in the body's first slot.
    inner_card = outer_card.content.children[1]
    @test inner_card isa WidgetCard
    op = projection_read(_proj(), iomap, ToggleCollapseOperation(inner_card))
    @test op isa ToggleCollapseOperation
    @test op.target === inner_root
end

@testset "collapsed node shows the ellipsis inline in the header, empty body" begin
    root, _, _, _ = _make_tree()
    root.collapsed = true
    iomap = projection_print(_proj(), root)
    card = iomap.output
    # Ellipsis is appended to the header line (inline with the open delimiter),
    # not placed on a separate body line.
    header = card.title
    @test header isa HorizontalLayout
    @test any(c -> c isa TextText && c.elements[1].content == "…", header.children)
    # The body is emptied while collapsed.
    @test card.content isa VerticalLayout
    @test length(card.content.children) == 0
end

@testset "catalog lazy expansion: nodes start collapsed until their data loads" begin
    # A fake catalog whose every child collection is a lazy CellVector that
    # records a side effect when forced — standing in for a DB query. No DB.
    # `CellVector(f)` wraps each value `f()` returns in a Cell, so the thunks
    # return plain value vectors (mirroring `DatabaseInstanceToDbCatalog`).
    queried = String[]
    mkcols(t)   = CellVector(() -> (push!(queried, "cols:$t");
                    DbCatalogColumn[DbCatalogColumn("c1", "int")]))
    mktables()  = CellVector(() -> (push!(queried, "tables");
                    DbCatalogTable[DbCatalogTable("t1", mkcols("t1")),
                                   DbCatalogTable("t2", mkcols("t2"))]))
    mkschemas() = CellVector(() -> (push!(queried, "schemas");
                    DbCatalogSchema[DbCatalogSchema("public", mktables())]))
    mkdbs()     = CellVector(() -> (push!(queried, "databases");
                    DbCatalogDatabase[DbCatalogDatabase("dvd", mkschemas())]))
    rdbms = DbCatalogRdbms("localhost", 5432, mkdbs())

    iomap = projection_print(RecursiveProjection(DbCatalogToSyntax()), rdbms)
    root  = iomap.output

    # Projecting the root must not touch the database. The entity node is always
    # expanded; its "Databases" keyword group starts collapsed because the
    # `databases` collection is not yet materialized.
    @test isempty(queried)
    @test root isa SyntaxNode
    @test root.collapsed == false                  # entity: always expanded
    databases_kw = root.children[1]                # the "Databases" keyword group
    @test databases_kw.open.content == " Databases"
    @test databases_kw.collapsed == true           # not materialized → collapsed
    @test isempty(queried)                         # reading collapse forced nothing

    # Expanding the keyword group forces only the next level (the databases query).
    length(databases_kw.children)
    @test "databases" in queried
    @test !("schemas" in queried)                  # one level only — still lazy

    # The produced database entity is expanded, but its "Schemas" group is
    # collapsed (schemas not yet loaded).
    db_entity = databases_kw.children[1]
    @test db_entity isa SyntaxNode
    @test db_entity.collapsed == false
    schemas_kw = db_entity.children[1]
    @test schemas_kw.collapsed == true
end

@testset "catalog partial walk → expanded along the walked path, collapsed off it" begin
    # Same counting fixture, but pre-walk the path to the FIRST table (exactly
    # what `explore_dbcatalog!` does): databases → schemas → tables list →
    # first table's columns. Everything off that path stays lazy.
    queried = String[]
    mkcols(t)   = CellVector(() -> (push!(queried, "cols:$t");
                    DbCatalogColumn[DbCatalogColumn("c1", "int")]))
    mktables()  = CellVector(() -> (push!(queried, "tables");
                    DbCatalogTable[DbCatalogTable("t1", mkcols("t1")),
                                   DbCatalogTable("t2", mkcols("t2"))]))
    mkschemas() = CellVector(() -> (push!(queried, "schemas");
                    DbCatalogSchema[DbCatalogSchema("public", mktables())]))
    mkdbs()     = CellVector(() -> (push!(queried, "databases");
                    DbCatalogDatabase[DbCatalogDatabase("dvd", mkschemas())]))
    rdbms = DbCatalogRdbms("localhost", 5432, mkdbs())

    # Partial walk (materialize the first-table path only).
    db     = rdbms.databases[1]
    schema = db.schemas[1]
    table1 = schema.tables[1]
    length(table1.columns)
    @test queried == ["databases", "schemas", "tables", "cols:t1"]

    iomap = projection_print(RecursiveProjection(DbCatalogToSyntax()), rdbms)
    root  = iomap.output

    # entity.children[1] is the keyword group; its children are the item entities.
    keyword(entity) = entity.children[1]
    items(entity)   = keyword(entity).children

    # The keyword group at each walked level is expanded; the off-path Columns
    # group (second table) stays collapsed. Entities themselves are expanded.
    @test root.collapsed == false
    @test keyword(root).collapsed == false              # "Databases" — materialized
    db_entity = items(root)[1]
    @test db_entity.collapsed == false
    @test keyword(db_entity).collapsed == false         # "Schemas" — materialized
    schema_entity = items(db_entity)[1]
    @test keyword(schema_entity).collapsed == false     # "Tables" — materialized
    table_entities = items(schema_entity)
    @test keyword(table_entities[1]).collapsed == false # actor's "Columns" — materialized
    @test keyword(table_entities[2]).collapsed == true  # other table's "Columns" — still lazy

    # Walking the syntax tree above triggered no further queries — the domain
    # cells were already cached and the off-path columns stay unqueried.
    @test queried == ["databases", "schemas", "tables", "cols:t1"]
end

@testset "catalog: an already-materialized keyword group renders expanded" begin
    # Eagerly-built (non-lazy) child collections read as materialized, so their
    # keyword group starts expanded — the path opened by e.g. `explore_dbcatalog!`.
    cols   = CellVector(Cell[Cell(DbCatalogColumn("id", "int"))])  # eager → valid
    table  = DbCatalogTable("t1", cols)
    iomap  = projection_print(RecursiveProjection(DbCatalogToSyntax()), table)
    entity = iomap.output
    @test entity isa SyntaxNode
    @test entity.collapsed == false                 # entity always expanded
    columns_kw = entity.children[1]
    @test columns_kw.open.content == " Columns"
    @test columns_kw.collapsed == false             # eager columns → expanded
end

end # test_syntax_to_widget
