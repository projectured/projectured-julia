"""
    DbCatalogToSyntaxModule

DbCatalog → SyntaxDocument projection. Maps PostgreSQL catalog hierarchy to syntax
tree shapes:

    DbCatalogConnection → SyntaxNode  " host:port"        (indentation 0)
    DbCatalogDatabase   → SyntaxNode  " dbname"           (indentation 1)
    DbCatalogSchema     → SyntaxNode  " schema"           (indentation 2)
    DbCatalogTable      → SyntaxNode  " table"            (indentation 3)
    DbCatalogColumn     → SyntaxLeaf  " column::type"    (indentation 4)

Each level uses DbCatalogToChildren projections to fetch children and projects
them recursively. The output is a hierarchical syntax tree suitable for
expand/collapse visualization when combined with SyntaxToText.
"""
module DbCatalogToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..DbCatalogDocumentModule: DbCatalogConnection, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..DbCatalogToChildrenModule: DbCatalogConnectionToChildren, DbCatalogDatabaseToChildren,
                                   DbCatalogSchemaToChildren, DbCatalogTableToChildren
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_red, color_solarized_green, color_solarized_magenta
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, append_reference
import ..PrinterContextModule: child_context
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode, DbCatalogSchemaToSyntaxNode,
       DbCatalogDatabaseToSyntaxNode, DbCatalogConnectionToSyntaxNode, DbCatalogToSyntax,
       dbcatalog_marker_eligible

# ── DbCatalogColumnToSyntaxLeaf ───────────────────────────────────────────────

struct DbCatalogColumnToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
DbCatalogColumnToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) =
    DbCatalogColumnToSyntaxLeaf(font, color)

function projection_print(p::DbCatalogColumnToSyntaxLeaf, recursion, col::DbCatalogColumn, ctx)
    SimpleIoMap(p, col, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> " " * col.name * "::" * col.data_type, p.font, p.color),
        col.selection))
end

map_reference_forward(::DbCatalogColumnToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::DbCatalogColumnToSyntaxLeaf, iomap, ref) = nothing
projection_read(::DbCatalogColumnToSyntaxLeaf, iomap, op) = nothing

# ── DbCatalogTableToSyntaxNode ────────────────────────────────────────────────
#
# Output shape:
#   SyntaxNode(open="", close="", sep="", indentation=3):
#     children[1] = SyntaxLeaf(" tablename")          ← name leaf
#     children[2] = SyntaxNode(indentation=4):         ← body node
#                     children[1..n] = projected column outputs

struct DbCatalogTableToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogTableToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_green) =
    DbCatalogTableToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogTableToSyntaxNode, recursion, table::DbCatalogTable, ctx)
    # Get children via DbCatalogTableToChildren
    children_iomap = projection_print(DbCatalogTableToChildren(), recursion, table, ctx)
    child_iomaps = Cell(() -> begin
        [projection_print(recursion, recursion, elem, child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children_iomap.output)]
    end)

    name_leaf = SyntaxLeaf(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString(() -> " " * table.name, p.name_font, p.name_color),
        table.selection)

    body_node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        4,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = table.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        3,
        Cell(false),
        sel)

    ChildrenIoMap(p, table, node, child_iomaps)
end

map_reference_forward(::DbCatalogTableToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogTableToSyntaxNode, iomap, op) = nothing

# ── DbCatalogSchemaToSyntaxNode ───────────────────────────────────────────────
#
# Output shape:
#   SyntaxNode(open="", close="", sep="", indentation=2):
#     children[1] = SyntaxLeaf(" schemaname")          ← name leaf
#     children[2] = SyntaxNode(indentation=3):         ← body node
#                     children[1..n] = projected table outputs

struct DbCatalogSchemaToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogSchemaToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_blue) =
    DbCatalogSchemaToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogSchemaToSyntaxNode, recursion, schema::DbCatalogSchema, ctx)
    # Get children via DbCatalogSchemaToChildren
    children_iomap = projection_print(DbCatalogSchemaToChildren(), recursion, schema, ctx)
    child_iomaps = Cell(() -> begin
        [projection_print(recursion, recursion, elem, child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children_iomap.output)]
    end)

    name_leaf = SyntaxLeaf(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString(() -> " " * schema.name, p.name_font, p.name_color),
        schema.selection)

    body_node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        3,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = schema.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        2,
        Cell(false),
        sel)

    ChildrenIoMap(p, schema, node, child_iomaps)
end

map_reference_forward(::DbCatalogSchemaToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToSyntaxNode, iomap, op) = nothing

# ── DbCatalogDatabaseToSyntaxNode ───────────────────────────────────────────────
#
# Output shape:
#   SyntaxNode(open="", close="", sep="", indentation=1):
#     children[1] = SyntaxLeaf(" dbname")              ← name leaf
#     children[2] = SyntaxNode(indentation=2):         ← body node
#                     children[1..n] = projected schema outputs

struct DbCatalogDatabaseToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogDatabaseToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_red) =
    DbCatalogDatabaseToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogDatabaseToSyntaxNode, recursion, db::DbCatalogDatabase, ctx)
    # Get children via DbCatalogDatabaseToChildren
    children_iomap = projection_print(DbCatalogDatabaseToChildren(), recursion, db, ctx)
    child_iomaps = Cell(() -> begin
        [projection_print(recursion, recursion, elem, child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children_iomap.output)]
    end)

    name_leaf = SyntaxLeaf(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString(() -> " " * db.name, p.name_font, p.name_color),
        db.selection)

    body_node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        2,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = db.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        1,
        Cell(false),
        sel)

    ChildrenIoMap(p, db, node, child_iomaps)
end

map_reference_forward(::DbCatalogDatabaseToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToSyntaxNode, iomap, op) = nothing

# ── DbCatalogConnectionToSyntaxNode ────────────────────────────────────────────
#
# Output shape:
#   SyntaxNode(open="", close="", sep="", indentation=0):
#     children[1] = SyntaxLeaf(" host:port")          ← name leaf
#     children[2] = SyntaxNode(indentation=1):         ← body node
#                     children[1..n] = projected database outputs

struct DbCatalogConnectionToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogConnectionToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_red) =
    DbCatalogConnectionToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogConnectionToSyntaxNode, recursion, conn::DbCatalogConnection, ctx)
    # Get children via DbCatalogConnectionToChildren
    children_iomap = projection_print(DbCatalogConnectionToChildren(), recursion, conn, ctx)
    child_iomaps = Cell(() -> begin
        [projection_print(recursion, recursion, elem, child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children_iomap.output)]
    end)

    name_leaf = SyntaxLeaf(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString(() -> " " * conn.host * ":" * string(conn.port), p.name_font, p.name_color),
        conn.selection)

    body_node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        1,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = conn.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        0,
        Cell(false),
        sel)

    ChildrenIoMap(p, conn, node, child_iomaps)
end

map_reference_forward(::DbCatalogConnectionToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogConnectionToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogConnectionToSyntaxNode, iomap, op) = nothing

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
# lands on non-empty catalog nodes (connection, database, schema, table) and never
# on leaf columns or empty body wrappers.
#
#   • indentation < 4          → not a column leaf
#   • children[2] is the body   → catalog node shape (name leaf + body node)
#   • body has children         → non-empty: there is something to fold
"""
    dbcatalog_marker_eligible(node) -> Bool

Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
lands on non-empty catalog nodes and never on leaf columns or empty body wrappers.
"""
dbcatalog_marker_eligible(::SyntaxLeaf) = false
function dbcatalog_marker_eligible(node::SyntaxNode)
    node.indentation < 4 || return false
    children = node.children
    length(children) >= 2 || return false
    body = children[2]
    body isa SyntaxNode && length(body.children) > 0
end

# ── Compound constructor ──────────────────────────────────────────────────────

function DbCatalogToSyntax()
    TypeDispatchingProjection(
        DbCatalogConnection => DbCatalogConnectionToSyntaxNode(),
        DbCatalogDatabase   => DbCatalogDatabaseToSyntaxNode(),
        DbCatalogSchema     => DbCatalogSchemaToSyntaxNode(),
        DbCatalogTable      => DbCatalogTableToSyntaxNode(),
        DbCatalogColumn     => DbCatalogColumnToSyntaxLeaf(),
    )
end

end # module
